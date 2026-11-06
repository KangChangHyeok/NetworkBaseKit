//
//  NetworkProvider.swift
//  NetworkBaseKit
//

import Foundation

/// Endpoint를 실제로 전송하는 객체.
/// 가변 상태가 없으므로 actor 대신 Sendable class로 두어 불필요한 직렬화/await를 피합니다.
public final class NetworkProvider: Sendable {

    public let environment: NetworkEnvironment?
    public let interceptors: [any RequestInterceptor]
    /// Interceptor 설정과 무관하게 적용되는 재시도 안전 상한 (무한 재시도 방지)
    public let maxRetryCount: Int
    /// 응답 디코딩에 사용합니다. Endpoint.decoder가 있으면 그쪽이 우선합니다.
    public let decoder: JSONDecoder
    /// `.json(Encodable)` body 인코딩에 사용합니다. Endpoint.encoder가 있으면 그쪽이 우선합니다.
    public let encoder: JSONEncoder
    public let logger: NetworkLogger
    private let session: URLSession

    /// - Parameters:
    ///   - environment: baseURL과 공통 헤더. Endpoint가 baseURL을 직접 지정하면 생략할 수 있습니다.
    ///   - interceptors: 배열 순서대로 adapt가 적용되고, retry는 처음으로 재시도를 결정한 Interceptor를 따릅니다.
    ///   - maxRetryCount: 한 요청의 최대 재시도 횟수
    ///   - decoder: 예) `decoder.keyDecodingStrategy = .convertFromSnakeCase`
    public init(environment: NetworkEnvironment? = nil,
                interceptors: [any RequestInterceptor] = [],
                maxRetryCount: Int = 3,
                decoder: JSONDecoder = JSONDecoder(),
                encoder: JSONEncoder = JSONEncoder(),
                logger: NetworkLogger = .default,
                session: URLSession = .shared) {
        self.environment = environment
        self.interceptors = interceptors
        self.maxRetryCount = maxRetryCount
        self.decoder = decoder
        self.encoder = encoder
        self.logger = logger
        self.session = session
    }

    // MARK: - Shared

    private static let sharedLock = NSLock()
    nonisolated(unsafe) private static var _shared = NetworkProvider()

    /// static API(`NetworkProvider.request(...)`)가 사용하는 기본 Provider.
    /// 앱 시작 시 `NetworkProvider.shared = NetworkProvider(environment: .prod)`처럼 설정합니다.
    public static var shared: NetworkProvider {
        get { sharedLock.withLock { _shared } }
        set { sharedLock.withLock { _shared = newValue } }
    }

    // MARK: - Public API

    /// 요청을 보내고 응답 body를 `T`로 디코딩합니다.
    /// `let user: User = try await provider.request(.profile)`처럼 타입 추론도 가능합니다.
    public func request<T: Decodable & Sendable>(_ endpoint: Endpoint, type: T.Type = T.self) async throws(NetworkError) -> T {
        try await response(endpoint, type: type).value
    }

    /// 응답 body가 필요 없는 요청(204 No Content, DELETE 등)에 사용합니다.
    public func request(_ endpoint: Endpoint) async throws(NetworkError) {
        _ = try await response(endpoint, type: EmptyResponse.self)
    }

    /// 디코딩된 값과 함께 상태 코드, 헤더, 소요 시간을 반환합니다.
    public func response<T: Decodable & Sendable>(_ endpoint: Endpoint, type: T.Type = T.self) async throws(NetworkError) -> NetworkResponse<T> {
        let baseRequest = try urlRequest(for: endpoint)
        let requestID = Self.makeRequestID()
        var attemptCount = 0

        while true {
            // 재시도마다 adapt를 다시 적용 (갱신된 토큰 반영)
            let request = try await adapt(baseRequest, for: endpoint)
            do {
                return try await perform(request, decoder: endpoint.decoder ?? decoder, type: T.self,
                                         id: requestID, attempt: attemptCount)
            } catch {
                guard !error.isCancelled, attemptCount < maxRetryCount else { throw error }

                switch await retryDecision(for: request, endpoint: endpoint, error: error, attemptCount: attemptCount) {
                case .doNotRetry:
                    throw error
                case .retry:
                    break
                case .retryAfter(let delay):
                    do {
                        try await Task.sleep(nanoseconds: UInt64(max(0, delay) * 1_000_000_000))
                    } catch {
                        throw .cancelled
                    }
                }
                attemptCount += 1
            }
        }
    }

    /// 실제로 전송될 URLRequest를 만들어 반환합니다. (Interceptor 적용 전, 디버깅/테스트용)
    public func urlRequest(for endpoint: Endpoint) throws(NetworkError) -> URLRequest {
        try endpoint.asURLRequest(environment: environment, encoder: encoder)
    }

    // MARK: - Interceptor

    private func adapt(_ request: URLRequest, for endpoint: Endpoint) async throws(NetworkError) -> URLRequest {
        var request = request
        for interceptor in interceptors {
            do {
                request = try await interceptor.adapt(request, for: endpoint)
            } catch let error as NetworkError {
                throw error
            } catch {
                throw .interceptorFailed(underlying: error)
            }
        }
        return request
    }

    private func retryDecision(for request: URLRequest, endpoint: Endpoint,
                               error: NetworkError, attemptCount: Int) async -> RetryDecision {
        for interceptor in interceptors {
            let decision = await interceptor.retry(request, for: endpoint, dueTo: error, attemptCount: attemptCount)
            if decision != .doNotRetry { return decision }
        }
        return .doNotRetry
    }

    // MARK: - Transport

    private func perform<T: Decodable & Sendable>(_ request: URLRequest, decoder: JSONDecoder, type: T.Type,
                                                  id: String, attempt: Int) async throws(NetworkError) -> NetworkResponse<T> {
        logger.logRequest(request, id: id, attempt: attempt)

        let start = Date()
        let data: Data
        let urlResponse: URLResponse
        do {
            (data, urlResponse) = try await session.data(for: request)
        } catch {
            let networkError = NetworkError.from(transportError: error)
            logger.logError(networkError, for: request, id: id, duration: Date().timeIntervalSince(start))
            throw networkError
        }
        let duration = Date().timeIntervalSince(start)

        guard let httpResponse = urlResponse as? HTTPURLResponse else {
            logger.logError(.noResponse, for: request, id: id, duration: duration)
            throw .noResponse
        }
        logger.logResponse(httpResponse, data: data, for: request, id: id, duration: duration)

        if let error = NetworkError(response: httpResponse, data: data) {
            throw error
        }

        let value = try decode(T.self, from: data, decoder: decoder, request: request, id: id)
        return NetworkResponse(value: value, statusCode: httpResponse.statusCode,
                               headers: httpResponse.stringHeaders, data: data, duration: duration)
    }

    // MARK: - Decoding

    private func decode<T: Decodable>(_ type: T.Type, from data: Data, decoder: JSONDecoder,
                                      request: URLRequest, id: String) throws(NetworkError) -> T {
        // body가 비어 있고 EmptyResponse를 기대하면 디코딩 없이 성공 처리
        if data.isEmpty, let empty = EmptyResponse() as? T {
            return empty
        }
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            let networkError = NetworkError.decodingFailed(underlying: error, data: data)
            logger.logError(networkError, for: request, id: id)
            throw networkError
        }
    }
}

// MARK: - Helpers

extension NetworkProvider {
    /// 로그에서 요청/응답/에러를 짝지을 수 있도록 붙이는 짧은 ID
    static func makeRequestID() -> String {
        String(UUID().uuidString.prefix(6))
    }
}

extension HTTPURLResponse {
    var stringHeaders: [String: String] {
        allHeaderFields.reduce(into: [String: String]()) { result, pair in
            if let key = pair.key as? String { result[key] = "\(pair.value)" }
        }
    }
}

// MARK: - Static API

extension NetworkProvider {
    /// `NetworkProvider.shared`로 요청합니다.
    public static func request<T: Decodable & Sendable>(_ endpoint: Endpoint, type: T.Type = T.self) async throws(NetworkError) -> T {
        try await shared.request(endpoint, type: type)
    }

    /// `NetworkProvider.shared`로 body 없는 요청을 보냅니다.
    public static func request(_ endpoint: Endpoint) async throws(NetworkError) {
        try await shared.request(endpoint)
    }
}
