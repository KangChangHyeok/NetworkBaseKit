import Testing
import Foundation
@testable import NetworkBaseKit

struct LoggerTests {

    struct API: Endpoint {
        var path: String = "/login"
        var method: HTTPMethod = .post
        var headers: [String: String]? = ["Authorization": "Bearer abcdefghijklmnop", "X-Trace": "t1"]
        var body: HTTPBody? { ["id": "kim", "password": "p@ss", "profile": ["token": "nested-secret"]] }
    }

    struct User: Decodable, Sendable { let name: String }

    let env = NetworkEnvironment(baseURL: "https://api.com")

    /// 출력된 로그를 모아두는 로거
    func capturingLogger(_ level: NetworkLogger.Level) -> (NetworkLogger, Box<[(String, Bool)]>) {
        let box = Box<[(String, Bool)]>([])
        let logger = NetworkLogger(level: level, output: { message, isError in box.value.append((message, isError)) })
        return (logger, box)
    }

    @Test("verbose: 헤더/Body/cURL을 출력하고 민감 정보는 마스킹")
    func verboseRedaction() async throws {
        let (logger, logs) = capturingLogger(.verbose)
        let server = MockServer(statusCode: 200, body: #"{"name":"kim","accessToken":"server-secret"}"#)
        let provider = NetworkProvider(environment: env, logger: logger, session: server.session)

        let _: User = try await provider.request(API())
        let all = logs.value.map(\.0).joined(separator: "\n")

        #expect(logs.value.count == 2) // 요청 1 + 응답 1
        #expect(all.contains("POST https://api.com/login"))
        #expect(all.contains("X-Trace: t1"))
        #expect(all.contains("curl -X POST"))
        // 마스킹 확인
        #expect(!all.contains("abcdefghijklmnop"))
        #expect(all.contains("Bearer…mnop"))
        #expect(!all.contains("p@ss"))
        #expect(!all.contains("nested-secret"))
        #expect(!all.contains("server-secret"))
        #expect(all.contains("\"kim\""))
    }

    @Test("요청과 응답이 같은 ID로 짝지어지고, 응답에 URL과 소요 시간이 포함")
    func requestIDAndDuration() async throws {
        let (logger, logs) = capturingLogger(.basic)
        let server = MockServer(statusCode: 200, body: #"{"name":"a"}"#)
        let provider = NetworkProvider(environment: env, logger: logger, session: server.session)

        let _: User = try await provider.request(API())
        #expect(logs.value.count == 2)
        let ids = logs.value.compactMap { line in
            line.0.range(of: #"\[[0-9A-F]{6}\]"#, options: .regularExpression).map { String(line.0[$0]) }
        }
        #expect(ids.count == 2 && ids[0] == ids[1])
        let response = logs.value[1].0
        #expect(response.contains("200"))
        #expect(response.contains("https://api.com/login"))
        #expect(response.range(of: #"\(\d+ms, \d+B\)"#, options: .regularExpression) != nil)
        // basic은 한 줄 요약만
        #expect(!logs.value[0].0.contains("Headers"))
    }

    @Test("error 레벨: 성공은 출력하지 않고 실패만 출력 (에러 body 포함)")
    func errorLevel() async {
        let (logger, logs) = capturingLogger(.error)
        let okProvider = NetworkProvider(environment: env, logger: logger,
                                         session: MockServer(statusCode: 204).session)
        try? await okProvider.request(API())
        #expect(logs.value.isEmpty)

        let failProvider = NetworkProvider(environment: env, logger: logger,
                                           session: MockServer(statusCode: 422, body: #"{"message":"invalid"}"#).session)
        try? await failProvider.request(API())
        #expect(logs.value.count == 1)
        #expect(logs.value[0].1 == true)
        #expect(logs.value[0].0.contains("422"))
        #expect(logs.value[0].0.contains("invalid"))
    }

    @Test("off 레벨은 아무것도 출력하지 않음")
    func offLevel() async {
        let (logger, logs) = capturingLogger(.off)
        let provider = NetworkProvider(environment: env, logger: logger,
                                       session: MockServer(statusCode: 500).session)
        try? await provider.request(API())
        #expect(logs.value.isEmpty)
    }

    @Test("전송 실패(URLError)도 로그에 남음")
    func transportErrorLogged() async {
        let (logger, logs) = capturingLogger(.error)
        let server = MockServer { _ in throw URLError(.timedOut) }
        let provider = NetworkProvider(environment: env, logger: logger, session: server.session)
        try? await provider.request(API())
        #expect(logs.value.count == 1)
        #expect(logs.value[0].0.contains("⚠️"))
        #expect(logs.value[0].0.contains("https://api.com/login"))
    }

    @Test("디코딩 실패 시 어떤 키가 문제인지 로그에 남음")
    func decodingErrorLogged() async {
        let (logger, logs) = capturingLogger(.error)
        let provider = NetworkProvider(environment: env, logger: logger,
                                       session: MockServer(statusCode: 200, body: #"{"nick":"a"}"#).session)
        _ = try? await provider.request(API(), type: User.self)
        #expect(logs.value.contains { $0.0.contains("name") && $0.1 })
    }

    @Test("재시도 요청은 retry 번호가 표시됨")
    func retryLogged() async {
        let (logger, logs) = capturingLogger(.basic)
        let provider = NetworkProvider(environment: env, interceptors: [RetryPolicy(maxRetries: 1, baseDelay: 0.01)],
                                       logger: logger, session: MockServer(statusCode: 503).session)
        try? await provider.request(API(method: .get))
        #expect(logs.value.contains { $0.0.contains("(retry #1)") })
    }

    @Test("cURL: 작은따옴표 이스케이프, 헤더 정렬, 마스킹")
    func cURLFormat() throws {
        var request = URLRequest(url: URL(string: "https://api.com/a")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("secret-cookie-value", forHTTPHeaderField: "Cookie")
        request.httpBody = Data(#"{"msg":"it's"}"#.utf8)

        let curl = NetworkLogger(level: .verbose).cURL(for: request)
        #expect(curl == """
        curl -X POST \\
          'https://api.com/a' \\
          -H 'Content-Type: application/json' \\
          -H 'Cookie: secret…alue' \\
          --data-raw '{"msg":"it'\\''s"}'
        """)
    }

    @Test("긴 Body는 maxBodyLength에서 잘림")
    func truncation() async throws {
        let (base, logs) = capturingLogger(.verbose)
        var logger = base
        logger.maxBodyLength = 50
        let long = "{\"name\":\"" + String(repeating: "x", count: 500) + "\"}"
        let provider = NetworkProvider(environment: env, logger: logger,
                                       session: MockServer(statusCode: 200, body: long).session)
        let _: User = try await provider.request(API(method: .get))
        #expect(logs.value.last?.0.contains("truncated") == true)
        #expect(logs.value.last?.0.contains(String(repeating: "x", count: 100)) == false)
    }
}
