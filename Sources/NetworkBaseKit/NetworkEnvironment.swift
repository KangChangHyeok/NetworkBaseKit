//
//  NetworkEnvironment.swift
//  NetworkBaseKit
//

import Foundation

/// Postman의 Environment에 해당합니다.
/// baseURL과 모든 요청에 공통으로 붙는 헤더를 한곳에서 관리하고,
/// dev / staging / prod 전환은 Provider에 넘기는 환경만 바꾸면 됩니다.
///
/// ```swift
/// extension NetworkEnvironment {
///     static let dev  = NetworkEnvironment(baseURL: "https://dev.api.com/v1")
///     static let prod = NetworkEnvironment(baseURL: "https://api.com/v1",
///                                          headers: ["X-App-Version": "1.0.0"])
/// }
/// ```
public struct NetworkEnvironment: Sendable, Equatable {
    public var baseURL: URL
    /// 모든 요청에 공통으로 붙는 헤더. Endpoint의 headers가 같은 키를 가지면 Endpoint 쪽이 우선합니다.
    public var headers: [String: String]
    /// 요청 타임아웃(초). nil이면 URLSession 설정을 따릅니다.
    public var timeout: TimeInterval?

    public init(baseURL: URL, headers: [String: String] = [:], timeout: TimeInterval? = nil) {
        self.baseURL = baseURL
        self.headers = headers
        self.timeout = timeout
    }

    /// 문자열로 baseURL을 지정합니다. 상수로 정의하는 용도이므로 잘못된 URL이면 즉시 크래시합니다.
    public init(baseURL: String, headers: [String: String] = [:], timeout: TimeInterval? = nil) {
        guard let url = URL(string: baseURL), url.scheme != nil, url.host != nil else {
            preconditionFailure("NetworkEnvironment: 잘못된 baseURL입니다 → \(baseURL)")
        }
        self.init(baseURL: url, headers: headers, timeout: timeout)
    }
}
