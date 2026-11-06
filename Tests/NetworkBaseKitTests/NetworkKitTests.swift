import Testing
import Foundation
@testable import NetworkBaseKit

struct NetworkKitTests {

    enum TestAPI: Endpoint {
        case profile
        case invalidBody

        var baseURL: URL? { URL(string: "https://test.com") }
        var path: String { "/profile" }
        var method: HTTPMethod { .get }
        var headers: [String: String]? { nil }
        var body: HTTPBody? {
            switch self {
            case .profile: return nil
            case .invalidBody: return ["date": Date()] // JSON으로 직렬화 불가
            }
        }
    }

    struct TestUser: Decodable, Equatable, Sendable {
        let name: String
    }

    @Test("성공적인 API 호출 및 디코딩")
    func requestSuccess() async throws {
        let server = MockServer(statusCode: 200, body: #"{ "name": "Gemini" }"#)
        let provider = NetworkProvider(session: server.session)

        let result = try await provider.request(TestAPI.profile, type: TestUser.self)
        #expect(result.name == "Gemini")
    }

    @Test("타입 추론으로 type: 인자 생략")
    func typeInference() async throws {
        let server = MockServer(statusCode: 200, body: #"{ "name": "Gemini" }"#)
        let provider = NetworkProvider(session: server.session)

        let user: TestUser = try await provider.request(TestAPI.profile)
        #expect(user.name == "Gemini")
    }

    @Test("404 응답 시 clientError와 함께 서버 에러 body 보존")
    func clientErrorKeepsBody() async {
        struct ServerMessage: Decodable { let message: String }
        let server = MockServer(statusCode: 404, body: #"{ "message": "유저 없음" }"#,
                                headers: ["X-Request-ID": "abc"])
        let provider = NetworkProvider(session: server.session)

        let error = await #expect(throws: NetworkError.self) {
            try await provider.request(TestAPI.profile, type: TestUser.self)
        }
        guard case .clientError(let response) = error else {
            Issue.record("clientError가 아님: \(String(describing: error))"); return
        }
        #expect(response.statusCode == 404)
        #expect(error?.isNotFound == true)
        #expect(response.decode(ServerMessage.self)?.message == "유저 없음")
        #expect(response.headers["X-Request-ID"] == "abc")
    }

    @Test("5xx는 serverError, 3xx는 unexpectedStatus", arguments: [500, 503, 302])
    func statusRanges(code: Int) async {
        let server = MockServer(statusCode: code)
        let provider = NetworkProvider(session: server.session)

        let error = await #expect(throws: NetworkError.self) {
            try await provider.request(TestAPI.profile, type: TestUser.self)
        }
        #expect(error?.statusCode == code)
        switch (code, error) {
        case (500...599, .serverError?), (300...399, .unexpectedStatus?): break
        default: Issue.record("잘못된 매핑: \(code) -> \(String(describing: error))")
        }
    }

    @Test("디코딩 실패 시 어떤 키가 문제인지 알려줌")
    func decodingError() async {
        let server = MockServer(statusCode: 200, body: #"{ "isAdult": true }"#)
        let provider = NetworkProvider(session: server.session)

        let error = await #expect(throws: NetworkError.self) {
            try await provider.request(TestAPI.profile, type: TestUser.self)
        }
        guard case .decodingFailed(_, let data) = error else {
            Issue.record("decodingFailed가 아님"); return
        }
        #expect(!data.isEmpty)
        #expect(error?.localizedDescription.contains("name") == true)
    }

    @Test("URLError는 transport로 감싸짐")
    func transportError() async {
        let server = MockServer { _ in throw URLError(.notConnectedToInternet) }
        let provider = NetworkProvider(session: server.session)

        let error = await #expect(throws: NetworkError.self) {
            try await provider.request(TestAPI.profile, type: TestUser.self)
        }
        #expect(error?.isConnectivityError == true)
    }

    @Test("Task 취소 시 .cancelled")
    func cancellation() async {
        let server = MockServer(delay: 2) { request in
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, nil)
        }
        let provider = NetworkProvider(session: server.session)

        let task = Task { try await provider.request(TestAPI.profile, type: TestUser.self) }
        try? await Task.sleep(nanoseconds: 50_000_000)
        task.cancel()
        let result = await task.result
        guard case .failure(let error as NetworkError) = result else {
            Issue.record("실패해야 함: \(result)"); return
        }
        #expect(error.isCancelled)
    }

    @Test("204 No Content는 body 없는 request로 성공")
    func noContent() async throws {
        let server = MockServer(statusCode: 204)
        let provider = NetworkProvider(session: server.session)

        try await provider.request(TestAPI.profile)
        let empty = try await provider.request(TestAPI.profile, type: EmptyResponse.self)
        #expect(empty == EmptyResponse())
    }

    @Test("response()는 상태 코드와 헤더를 함께 반환")
    func responseMetadata() async throws {
        let server = MockServer(statusCode: 201, body: #"{ "name": "A" }"#, headers: ["Link": "<next>"])
        let provider = NetworkProvider(session: server.session)

        let response = try await provider.response(TestAPI.profile, type: TestUser.self)
        #expect(response.value.name == "A")
        #expect(response.statusCode == 201)
        #expect(response.header("link") == "<next>")
        #expect(response.duration >= 0)
    }

    @Test("HTTPURLResponse가 아니면 .noResponse")
    func noResponseError() async {
        let server = MockServer { request in
            (URLResponse(url: request.url!, mimeType: nil, expectedContentLength: 0, textEncodingName: nil), nil)
        }
        let provider = NetworkProvider(session: server.session)

        let error = await #expect(throws: NetworkError.self) {
            try await provider.request(TestAPI.profile, type: TestUser.self)
        }
        guard case .noResponse = error else { Issue.record("noResponse가 아님"); return }
    }

    @Test("직렬화할 수 없는 body는 요청을 보내지 않고 .encodingFailed")
    func encodingFailed() async {
        let didSend = Box(false)
        let server = MockServer { request in
            didSend.value = true
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, nil)
        }
        let provider = NetworkProvider(session: server.session)

        let error = await #expect(throws: NetworkError.self) {
            try await provider.request(TestAPI.invalidBody, type: TestUser.self)
        }
        guard case .encodingFailed = error else { Issue.record("encodingFailed가 아님"); return }
        #expect(didSend.value == false)
    }
}
