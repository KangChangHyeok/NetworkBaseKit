import Testing
import Foundation
@testable import NetworkBaseKit

struct EnvironmentTests {

    struct API: Endpoint {
        var baseURL: URL? = nil
        var path: String = "/users"
        var method: HTTPMethod = .get
        var headers: [String: String]? = nil
        var queryItems: [URLQueryItem]? = nil
        var body: HTTPBody? { bodyValue }
        nonisolated(unsafe) var bodyValue: HTTPBody? = nil
    }

    let dev = NetworkEnvironment(baseURL: "https://dev.api.com/v1",
                                 headers: ["X-App-Version": "1.0", "Accept": "application/json"],
                                 timeout: 15)

    @Test("환경의 baseURL 경로 prefix와 Endpoint path가 합쳐짐",
          arguments: [("/users", "https://dev.api.com/v1/users"),
                      ("users", "https://dev.api.com/v1/users"),
                      ("/users/1/posts", "https://dev.api.com/v1/users/1/posts"),
                      ("", "https://dev.api.com/v1")])
    func pathJoining(path: String, expected: String) throws {
        let provider = NetworkProvider(environment: dev)
        let request = try provider.urlRequest(for: API(path: path))
        #expect(request.url?.absoluteString == expected)
    }

    @Test("baseURL 끝의 / 와 포트를 처리")
    func trailingSlashAndPort() throws {
        let env = NetworkEnvironment(baseURL: "http://localhost:8080/")
        let request = try NetworkProvider(environment: env).urlRequest(for: API(path: "/health"))
        #expect(request.url?.absoluteString == "http://localhost:8080/health")
    }

    @Test("Endpoint의 baseURL이 환경보다 우선")
    func endpointBaseURLOverrides() throws {
        let provider = NetworkProvider(environment: dev)
        let request = try provider.urlRequest(for: API(baseURL: URL(string: "https://cdn.com"), path: "/img"))
        #expect(request.url?.absoluteString == "https://cdn.com/img")
    }

    @Test("baseURL이 어디에도 없으면 invalidURL")
    func missingBaseURL() {
        #expect(throws: NetworkError.self) {
            try NetworkProvider().urlRequest(for: API())
        }
    }

    @Test("빈 queryItems는 URL 끝에 ?를 남기지 않고, baseURL 쿼리와 병합")
    func queryMerging() throws {
        let provider = NetworkProvider(environment: dev)
        #expect(try provider.urlRequest(for: API(queryItems: [])).url?.absoluteString
                == "https://dev.api.com/v1/users")

        let env = NetworkEnvironment(baseURL: "https://api.com?key=abc")
        let request = try NetworkProvider(environment: env)
            .urlRequest(for: API(queryItems: [URLQueryItem(name: "page", value: "1")]))
        #expect(request.url?.absoluteString == "https://api.com/users?key=abc&page=1")
    }

    @Test("헤더 병합: 환경 < 자동 Content-Type < Endpoint")
    func headerMerging() throws {
        let provider = NetworkProvider(environment: dev)

        // Endpoint 헤더를 추가해도 환경 헤더는 유지되고, 같은 키는 대소문자 무관하게 Endpoint가 우선
        let request = try provider.urlRequest(for: API(headers: ["Authorization": "Bearer t",
                                                                 "accept": "text/plain"]))
        #expect(request.value(forHTTPHeaderField: "X-App-Version") == "1.0")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer t")
        #expect(request.value(forHTTPHeaderField: "Accept") == "text/plain")
        #expect(request.timeoutInterval == 15)
    }

    @Test("Content-Type은 body가 있을 때만 자동으로 붙고, Endpoint가 덮어쓸 수 있음")
    func contentType() throws {
        let provider = NetworkProvider(environment: dev)
        #expect(try provider.urlRequest(for: API()).value(forHTTPHeaderField: "Content-Type") == nil)

        let post = API(method: .post, bodyValue: ["a": 1])
        #expect(try provider.urlRequest(for: post).value(forHTTPHeaderField: "Content-Type") == "application/json")

        let custom = API(method: .post, headers: ["Content-Type": "application/vnd.api+json"], bodyValue: ["a": 1])
        #expect(try provider.urlRequest(for: custom).value(forHTTPHeaderField: "Content-Type") == "application/vnd.api+json")
    }

    @Test("환경을 바꾸면 같은 Endpoint가 다른 서버로 전송됨")
    func switchingEnvironment() async throws {
        let received = Box<URL?>(nil)
        let server = MockServer { request in
            received.value = request.url
            return (HTTPURLResponse(url: request.url!, statusCode: 204, httpVersion: nil, headerFields: nil)!, nil)
        }
        let prod = NetworkEnvironment(baseURL: "https://api.com")
        try await NetworkProvider(environment: prod, session: server.session).request(API())
        #expect(received.value?.absoluteString == "https://api.com/users")
    }
}
