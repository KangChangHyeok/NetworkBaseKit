//
//  NetworkResponse.swift
//  NetworkBaseKit
//

import Foundation

/// 디코딩된 값과 함께 상태 코드, 헤더, 원본 데이터를 담은 응답.
/// Postman 응답 패널처럼 Body 외의 정보(헤더, 상태, 소요 시간)가 필요할 때 사용합니다.
public struct NetworkResponse<Value: Sendable>: Sendable {
    public let value: Value
    public let statusCode: Int
    public let headers: [String: String]
    public let data: Data
    /// 요청부터 응답 수신까지 걸린 시간(초)
    public let duration: TimeInterval

    /// 대소문자 구분 없이 헤더 값을 찾습니다.
    public func header(_ name: String) -> String? {
        headers.first { $0.key.caseInsensitiveCompare(name) == .orderedSame }?.value
    }
}

/// body가 없는 응답(204 No Content 등)이나 body를 무시하고 싶을 때 사용하는 타입.
public struct EmptyResponse: Decodable, Sendable, Equatable {
    public init() {}
}
