import Testing
import Foundation
@testable import NetworkBaseKit

struct InterceptorTests {

    struct API: Endpoint {
        var path: String = "/me"
        var method: HTTPMethod = .get
        var requiresAuthorization: Bool = true
    }

    struct Me: Decodable, Sendable { let id: Int }

    let env = NetworkEnvironment(baseURL: "https://api.com")

    /// 테스트용 토큰 저장소
    actor TokenStore {
        var token: String
        private(set) var refreshCount = 0
        var shouldFail = false
        init(token: String) { self.token = token }
        func refresh() async throws {
            refreshCount += 1
            try await Task.sleep(nanoseconds: 50_000_000) // 동시 요청이 겹치도록 약간 지연
            if shouldFail { throw URLError(.userAuthenticationRequired) }
            token = "new-token"
        }
        func setShouldFail() { shouldFail = true }
    }

    /// "Bearer new-token"이면 200, 아니면 401을 주는 서버
    func authServer(requestCount: Box<Int>) -> MockServer {
        MockServer { request in
            requestCount.value += 1
            let ok = request.value(forHTTPHeaderField: "Authorization") == "Bearer new-token"
            let response = HTTPURLResponse(url: request.url!, statusCode: ok ? 200 : 401,
                                           httpVersion: nil, headerFields: nil)!
            return (response, ok ? Data(#"{"id":1}"#.utf8) : nil)
        }
    }

    func makeAuth(_ store: TokenStore) -> AuthInterceptor {
        AuthInterceptor(tokenProvider: { await store.token },
                        refreshToken: { try await store.refresh() })
    }

    @Test("adapt는 순서대로 적용되어 헤더를 추가")
    func adaptOrder() async throws {
        struct HeaderInterceptor: RequestInterceptor {
            let value: String
            func adapt(_ request: URLRequest, for endpoint: any Endpoint) async throws -> URLRequest {
                var request = request
                let old = request.value(forHTTPHeaderField: "X-Trace") ?? ""
                request.setValue(old + value, forHTTPHeaderField: "X-Trace")
                return request
            }
        }
        let trace = Box<String?>(nil)
        let server = MockServer { request in
            trace.value = request.value(forHTTPHeaderField: "X-Trace")
            return (HTTPURLResponse(url: request.url!, statusCode: 204, httpVersion: nil, headerFields: nil)!, nil)
        }
        let provider = NetworkProvider(environment: env,
                                       interceptors: [HeaderInterceptor(value: "A"), HeaderInterceptor(value: "B")],
                                       session: server.session)
        try await provider.request(API())
        #expect(trace.value == "AB")
    }

    @Test("adapt에서 던진 에러는 interceptorFailed로 감싸지고 요청은 전송되지 않음")
    func adaptFailure() async {
        struct Failing: RequestInterceptor {
            struct Oops: Error {}
            func adapt(_ request: URLRequest, for endpoint: any Endpoint) async throws -> URLRequest { throw Oops() }
        }
        let count = Box(0)
        let provider = NetworkProvider(environment: env, interceptors: [Failing()],
                                       session: authServer(requestCount: count).session)
        let error = await #expect(throws: NetworkError.self) { try await provider.request(API()) }
        guard case .interceptorFailed = error else { Issue.record("interceptorFailed가 아님"); return }
        #expect(count.value == 0)
    }

    @Test("AuthInterceptor: 401이면 토큰 갱신 후 새 토큰으로 재시도")
    func refreshAndRetry() async throws {
        let store = TokenStore(token: "expired")
        let count = Box(0)
        let provider = NetworkProvider(environment: env, interceptors: [makeAuth(store)],
                                       session: authServer(requestCount: count).session)

        let me: Me = try await provider.request(API())
        #expect(me.id == 1)
        #expect(count.value == 2)
        #expect(await store.refreshCount == 1)
    }

    @Test("AuthInterceptor: 동시에 401을 받아도 갱신은 한 번만")
    func concurrentRefreshCoalesced() async throws {
        let store = TokenStore(token: "expired")
        let count = Box(0)
        let provider = NetworkProvider(environment: env, interceptors: [makeAuth(store)],
                                       session: authServer(requestCount: count).session)

        try await withThrowingTaskGroup(of: Me.self) { group in
            for _ in 0..<5 { group.addTask { try await provider.request(API()) } }
            for try await me in group { #expect(me.id == 1) }
        }
        #expect(await store.refreshCount == 1)
    }

    @Test("AuthInterceptor: 갱신 실패 시 원래 401 에러를 던지고 재시도하지 않음")
    func refreshFailure() async {
        let store = TokenStore(token: "expired")
        await store.setShouldFail()
        let count = Box(0)
        let provider = NetworkProvider(environment: env, interceptors: [makeAuth(store)],
                                       session: authServer(requestCount: count).session)

        let error = await #expect(throws: NetworkError.self) { try await provider.request(API()) }
        #expect(error?.isUnauthorized == true)
        #expect(count.value == 1)
    }

    @Test("AuthInterceptor: requiresAuthorization == false면 토큰을 붙이지 않음")
    func noAuth() async throws {
        let header = Box<String?>("unset")
        let server = MockServer { request in
            header.value = request.value(forHTTPHeaderField: "Authorization")
            return (HTTPURLResponse(url: request.url!, statusCode: 204, httpVersion: nil, headerFields: nil)!, nil)
        }
        let provider = NetworkProvider(environment: env, interceptors: [makeAuth(TokenStore(token: "t"))],
                                       session: server.session)
        try await provider.request(API(requiresAuthorization: false))
        #expect(header.value == nil)
    }

    @Test("RetryPolicy: 503을 재시도하다 성공")
    func retryPolicySucceeds() async throws {
        let count = Box(0)
        let server = MockServer { request in
            count.value += 1
            let code = count.value < 3 ? 503 : 200
            return (HTTPURLResponse(url: request.url!, statusCode: code, httpVersion: nil, headerFields: nil)!,
                    code == 200 ? Data(#"{"id":7}"#.utf8) : nil)
        }
        let provider = NetworkProvider(environment: env, interceptors: [RetryPolicy(maxRetries: 2, baseDelay: 0.01)],
                                       session: server.session)
        let me: Me = try await provider.request(API())
        #expect(me.id == 7)
        #expect(count.value == 3)
    }

    @Test("RetryPolicy: POST와 4xx는 재시도하지 않고, maxRetries를 넘지 않음")
    func retryPolicyLimits() async {
        func run(method: HTTPMethod, status: Int) async -> Int {
            let count = Box(0)
            let server = MockServer { request in
                count.value += 1
                return (HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!, nil)
            }
            let provider = NetworkProvider(environment: env, interceptors: [RetryPolicy(maxRetries: 2, baseDelay: 0.01)],
                                           session: server.session)
            _ = try? await provider.request(API(method: method))
            return count.value
        }
        #expect(await run(method: .post, status: 503) == 1)
        #expect(await run(method: .get, status: 400) == 1)
        #expect(await run(method: .get, status: 500) == 3)
    }

    @Test("RetryPolicy: Retry-After 헤더를 따름")
    func retryAfterHeader() async {
        let error = NetworkError.serverError(HTTPErrorResponse(statusCode: 503, headers: ["retry-after": "7"]))
        let decision = await RetryPolicy().retry(URLRequest(url: URL(string: "https://a.com")!), for: API(),
                                                 dueTo: error, attemptCount: 0)
        #expect(decision == .retryAfter(7))
    }

    @Test("Provider의 maxRetryCount가 무한 재시도를 막음")
    func maxRetryCap() async {
        struct AlwaysRetry: RequestInterceptor {
            func retry(_ request: URLRequest, for endpoint: any Endpoint, dueTo error: NetworkError, attemptCount: Int) async -> RetryDecision { .retry }
        }
        let count = Box(0)
        let server = MockServer { request in
            count.value += 1
            return (HTTPURLResponse(url: request.url!, statusCode: 500, httpVersion: nil, headerFields: nil)!, nil)
        }
        let provider = NetworkProvider(environment: env, interceptors: [AlwaysRetry()], maxRetryCount: 3,
                                       session: server.session)
        await #expect(throws: NetworkError.self) { try await provider.request(API()) }
        #expect(count.value == 4) // 최초 1회 + 재시도 3회
    }
}
