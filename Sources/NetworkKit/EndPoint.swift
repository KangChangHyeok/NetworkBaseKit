//
//  File.swift
//  NetworkKit
//
//  Created by changhyeok on 1/23/26.
//

import Foundation

/// API의 명세(Specs)를 정의하는 프로토콜
public protocol Endpoint: Sendable {
    var scheme: String { get }              // 예: "https"
    var host: String { get }                // 예: "api.networkkit.com"
    var path: String { get }                // 예: "/users"
    var method: HTTPMethod { get }          // 예: .get, .post
    var headers: [String: String]? { get }  // 예: ["Content-Type": "application/json"]
    var queryItems: [URLQueryItem]? { get } // 예: ?page=1&limit=10 (GET용)
    var body: [String: Any]? { get }        // 예: JSON 데이터 (POST/PUT용)
}

// 자주 쓰는 값들은 기본값(Default)을 줘서 코드를 줄여줍니다.
public extension Endpoint {
    var scheme: String { "https" }
    var headers: [String: String]? { ["Content-Type": "application/json"] }
    var queryItems: [URLQueryItem]? { nil }
    var body: [String: Any]? { nil }
}

extension Endpoint {
    
    // Endpoint -> URLRequest 변환 메서드
    func asURLRequest() throws -> URLRequest {
        var components = URLComponents()
        components.scheme = scheme
        components.host = host
        components.path = path
        components.queryItems = queryItems // 쿼리 파라미터(GET) 처리
        
        // 1. URL 생성 검증
        guard let url = components.url else {
            throw NetworkError.invalidURL
        }
        
        // 2. Request 생성 및 설정
        var request = URLRequest(url: url)
        request.httpMethod = method.rawValue
        request.allHTTPHeaderFields = headers
        
        // 3. Body(POST/PUT) 처리
        
        if let body = body {
            // Dictionary를 JSON Data로 변환
            request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        }
        
        return request
    }
}
