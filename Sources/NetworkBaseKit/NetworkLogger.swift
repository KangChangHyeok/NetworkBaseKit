//
//  File.swift
//  NetworkKit
//
//  Created by changhyeok on 1/24/26.
//

import Foundation

struct NetworkLogger {
    
    // 1. 요청(Request)을 찍어주는 함수
    static func log(request: URLRequest) {
        print("\n - - - - - - - - - - 🛫 NETWORK REQUEST 🛫 - - - - - - - - - -")
        defer { print("- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - \n") }
        
        // URL & Method
        if let url = request.url, let method = request.httpMethod {
            print("URL: \(url.absoluteString)")
            print("Method: \(method)")
        }
        
        // Header
        if let header = request.allHTTPHeaderFields {
            print("Header: \(header)")
        }
        
        // Body (JSON)
        if let body = request.httpBody,
           let jsonString = String(data: body, encoding: .utf8) {
            print("Body: \(jsonString)")
        }
    }
    
    // 2. 응답(Response)을 찍어주는 함수
    static func log(response: URLResponse?, data: Data?) {
        print("\n - - - - - - - - - - 🛬 NETWORK RESPONSE 🛬 - - - - - - - - - -")
        defer { print("- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - \n") }
        
        // Status Code
        if let httpResponse = response as? HTTPURLResponse {
            print("Status Code: \(httpResponse.statusCode)")
        }
        
        // Data (JSON Pretty Print)
        if let data = data {
            // 보기에 좋게 JSON 예쁘게 출력
            if let jsonObject = try? JSONSerialization.jsonObject(with: data),
               let prettyData = try? JSONSerialization.data(withJSONObject: jsonObject, options: .prettyPrinted),
               let prettyString = String(data: prettyData, encoding: .utf8) {
                print("Data: \n\(prettyString)")
            } else {
                // JSON이 아니면 그냥 문자열로 출력
                print("Data: \(String(data: data, encoding: .utf8) ?? "데이터 없음")")
            }
        }
    }
}
