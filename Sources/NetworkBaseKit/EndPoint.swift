//
//  Endpoint.swift
//  NetworkBaseKit
//
//  Created by changhyeok on 1/23/26.
//

import Foundation

/// API 명세를 정의하는 프로토콜. Postman의 요청 탭 하나에 해당합니다.
///
/// ```swift
/// enum UserAPI: Endpoint {
///     case profile(id: Int)
///
///     var path: String {
///         switch self { case .profile(let id): "/users/\(id)" }
///     }
///     var method: HTTPMethod { .get }
/// }
/// ```
public protocol Endpoint: Sendable {
    /// 이 Endpoint만 다른 서버를 쓸 때 지정합니다. nil이면 Provider의 환경(baseURL)을 사용합니다.
    var baseURL: URL? { get }
    /// 예: "/users", "users/1" (앞의 "/"는 있어도 없어도 됩니다)
    var path: String { get }
    var method: HTTPMethod { get }
    /// 환경 공통 헤더 위에 덮어쓰는(병합되는) 헤더
    var headers: [String: String]? { get }
    /// 예: ?page=1&limit=10
    var queryItems: [URLQueryItem]? { get }
    /// 요청 body. `.json(model)`, `["key": value]`, `.form(...)`, `.multipart(...)`, `.raw(...)`
    var body: HTTPBody? { get }
    /// 이 Endpoint에만 다른 인코딩 전략이 필요할 때 지정합니다. nil이면 Provider의 encoder를 사용합니다.
    var encoder: JSONEncoder? { get }
    /// 이 Endpoint에만 다른 디코딩 전략이 필요할 때 지정합니다. nil이면 Provider의 decoder를 사용합니다.
    var decoder: JSONDecoder? { get }
    /// false면 AuthInterceptor가 토큰을 붙이지 않습니다. (Postman의 "No Auth", 로그인/토큰 갱신 API 등)
    var requiresAuthorization: Bool { get }
}

public extension Endpoint {
    var requiresAuthorization: Bool { true }
    var baseURL: URL? { nil }
    var headers: [String: String]? { nil }
    var queryItems: [URLQueryItem]? { nil }
    var body: HTTPBody? { nil }
    var encoder: JSONEncoder? { nil }
    var decoder: JSONDecoder? { nil }
}

// MARK: - URLRequest 생성

extension Endpoint {

    /// 환경 정보와 합쳐 URLRequest를 만듭니다.
    /// 헤더 우선순위: 환경 공통 헤더 < 자동 Content-Type < Endpoint 헤더
    func asURLRequest(environment: NetworkEnvironment? = nil,
                      encoder defaultEncoder: JSONEncoder = JSONEncoder()) throws(NetworkError) -> URLRequest {
        guard let base = baseURL ?? environment?.baseURL else {
            throw NetworkError.invalidURL
        }
        let url = try Self.makeURL(base: base, path: path, queryItems: queryItems)

        var request = URLRequest(url: url)
        request.httpMethod = method.rawValue
        if let timeout = environment?.timeout {
            request.timeoutInterval = timeout
        }

        // 1. 환경 공통 헤더
        environment?.headers.forEach { request.setValue($1, forHTTPHeaderField: $0) }

        // 2. Body + 자동 Content-Type
        if let body {
            let (data, contentType) = try body.encoded(using: encoder ?? defaultEncoder)
            request.httpBody = data
            request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        }

        // 3. Endpoint 헤더 (가장 우선)
        headers?.forEach { request.setValue($1, forHTTPHeaderField: $0) }

        return request
    }

    /// baseURL의 경로 prefix(/v1 등)와 쿼리를 유지하면서 path와 queryItems를 합칩니다.
    static func makeURL(base: URL, path: String, queryItems: [URLQueryItem]?) throws(NetworkError) -> URL {
        guard var components = URLComponents(url: base, resolvingAgainstBaseURL: false),
              components.scheme != nil, components.host != nil else {
            throw NetworkError.invalidURL
        }

        let basePath = components.path.hasSuffix("/") ? String(components.path.dropLast()) : components.path
        let trimmedPath = path.hasPrefix("/") ? String(path.dropFirst()) : path
        components.path = trimmedPath.isEmpty ? basePath : basePath + "/" + trimmedPath

        let mergedQuery = (components.queryItems ?? []) + (queryItems ?? [])
        components.queryItems = mergedQuery.isEmpty ? nil : mergedQuery

        guard let url = components.url else {
            throw NetworkError.invalidURL
        }
        return url
    }
}
