//
//  RequestInterceptor.swift
//  NetworkBaseKit
//

import Foundation

/// 재시도 여부 결정
public enum RetryDecision: Sendable, Equatable {
    case doNotRetry
    case retry
    case retryAfter(TimeInterval)
}

/// 모든 요청에 끼어드는 미들웨어. Postman의 Collection Pre-request Script / Auth 상속에 해당합니다.
///
/// - `adapt`: 전송 직전에 요청을 수정합니다. (토큰 주입, 공통 헤더, 서명 등)
///   재시도할 때도 매번 다시 호출되므로, 갱신된 토큰이 재시도 요청에 반영됩니다.
/// - `retry`: 요청이 실패했을 때 재시도할지 결정합니다. (401 → 토큰 갱신, 5xx → 백오프 재시도 등)
public protocol RequestInterceptor: Sendable {
    func adapt(_ request: URLRequest, for endpoint: any Endpoint) async throws -> URLRequest

    /// - Parameter attemptCount: 지금까지 재시도한 횟수 (첫 실패 시 0)
    func retry(_ request: URLRequest, for endpoint: any Endpoint,
               dueTo error: NetworkError, attemptCount: Int) async -> RetryDecision
}

public extension RequestInterceptor {
    func adapt(_ request: URLRequest, for endpoint: any Endpoint) async throws -> URLRequest { request }

    func retry(_ request: URLRequest, for endpoint: any Endpoint,
               dueTo error: NetworkError, attemptCount: Int) async -> RetryDecision { .doNotRetry }
}

// MARK: - AuthInterceptor

/// 토큰을 헤더에 주입하고, 401 응답 시 토큰을 갱신한 뒤 한 번 재시도합니다.
///
/// ```swift
/// let auth = AuthInterceptor(
///     tokenProvider: { await TokenStore.shared.accessToken },
///     refreshToken: { try await TokenStore.shared.refresh() }
/// )
/// let provider = NetworkProvider(environment: .prod, interceptors: [auth])
/// ```
///
/// 여러 요청이 동시에 401을 받아도 갱신은 한 번만 실행되고, 나머지는 그 결과를 기다립니다.
/// `Endpoint.requiresAuthorization`이 false인 요청(로그인, 토큰 갱신 API 등)에는 적용되지 않습니다.
public struct AuthInterceptor: RequestInterceptor {
    public let headerName: String
    public let tokenPrefix: String
    private let tokenProvider: @Sendable () async -> String?
    private let refreshToken: (@Sendable () async throws -> Void)?
    private let coordinator = RefreshCoordinator()

    public init(headerName: String = "Authorization",
                tokenPrefix: String = "Bearer ",
                tokenProvider: @escaping @Sendable () async -> String?,
                refreshToken: (@Sendable () async throws -> Void)? = nil) {
        self.headerName = headerName
        self.tokenPrefix = tokenPrefix
        self.tokenProvider = tokenProvider
        self.refreshToken = refreshToken
    }

    public func adapt(_ request: URLRequest, for endpoint: any Endpoint) async throws -> URLRequest {
        guard endpoint.requiresAuthorization, let token = await tokenProvider() else { return request }
        var request = request
        request.setValue(tokenPrefix + token, forHTTPHeaderField: headerName)
        return request
    }

    public func retry(_ request: URLRequest, for endpoint: any Endpoint,
                      dueTo error: NetworkError, attemptCount: Int) async -> RetryDecision {
        guard error.isUnauthorized, endpoint.requiresAuthorization,
              let refreshToken, attemptCount == 0 else {
            return .doNotRetry
        }

        // 이 요청이 실패한 사이에 다른 요청이 이미 토큰을 갱신했다면, 갱신 없이 새 토큰으로 재시도
        let sentToken = request.value(forHTTPHeaderField: headerName)
        let currentToken = await tokenProvider().map { tokenPrefix + $0 }
        if let currentToken, currentToken != sentToken {
            return .retry
        }

        do {
            try await coordinator.refresh(using: refreshToken)
            return .retry
        } catch {
            return .doNotRetry
        }
    }
}

/// 동시에 들어온 토큰 갱신 요청을 하나로 합칩니다.
actor RefreshCoordinator {
    private var inFlight: Task<Void, any Error>?

    func refresh(using operation: @escaping @Sendable () async throws -> Void) async throws {
        if let inFlight {
            return try await inFlight.value
        }
        let task = Task { try await operation() }
        inFlight = task
        defer { inFlight = nil }
        try await task.value
    }
}

// MARK: - RetryPolicy

/// 일시적인 오류(연결 끊김, 타임아웃, 5xx, 429)에 지수 백오프로 재시도합니다.
/// 기본적으로 멱등(idempotent) 메서드만 재시도해서 POST가 중복 실행되지 않게 합니다.
public struct RetryPolicy: RequestInterceptor {
    public let maxRetries: Int
    public let baseDelay: TimeInterval
    public let retryableMethods: Set<HTTPMethod>
    public let retryableStatusCodes: Set<Int>

    public init(maxRetries: Int = 2,
                baseDelay: TimeInterval = 0.5,
                retryableMethods: Set<HTTPMethod> = [.get, .head, .put, .delete, .options],
                retryableStatusCodes: Set<Int> = [408, 429, 500, 502, 503, 504]) {
        self.maxRetries = maxRetries
        self.baseDelay = baseDelay
        self.retryableMethods = retryableMethods
        self.retryableStatusCodes = retryableStatusCodes
    }

    public func retry(_ request: URLRequest, for endpoint: any Endpoint,
                      dueTo error: NetworkError, attemptCount: Int) async -> RetryDecision {
        guard attemptCount < maxRetries, retryableMethods.contains(endpoint.method) else {
            return .doNotRetry
        }

        let isRetryable: Bool
        if let statusCode = error.statusCode {
            isRetryable = retryableStatusCodes.contains(statusCode)
        } else {
            isRetryable = error.isConnectivityError
        }
        guard isRetryable else { return .doNotRetry }

        // 서버가 Retry-After(초)를 주면 그대로 따름
        if let retryAfter = error.response?.headers.first(where: { $0.key.caseInsensitiveCompare("Retry-After") == .orderedSame })?.value,
           let seconds = TimeInterval(retryAfter) {
            return .retryAfter(seconds)
        }
        return .retryAfter(baseDelay * pow(2, Double(attemptCount)))
    }
}
