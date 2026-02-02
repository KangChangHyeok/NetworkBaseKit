//
//  NetworkLogger.swift
//  NetworkKit
//
//  Created by changhyeok on 1/24/26.
//

import Foundation

public struct NetworkLogger {
    
    // MARK: - 요청(Request) 로그
    static func log(request: URLRequest) {
        let method = request.httpMethod ?? "UNKNOWN"
        let url = request.url?.absoluteString ?? "N/A"
        
        print("")
        print("🌐 [Network] ────────────────────────────────────────")
        print("🌐 [Network] 📤 REQUEST")
        print("🌐 [Network] ├─ Method: \(method)")
        print("🌐 [Network] ├─ URL: \(url)")
        
        // Header
        if let headers = request.allHTTPHeaderFields, !headers.isEmpty {
            print("🌐 [Network] ├─ Headers:")
            for (key, value) in headers {
                // 민감한 정보 마스킹 (예: Authorization)
                if key.lowercased() == "authorization" {
                    let maskedValue = maskToken(value)
                    print("🌐 [Network] │     \(key): \(maskedValue)")
                } else {
                    print("🌐 [Network] │     \(key): \(value)")
                }
            }
        }
        
        // Body (JSON)
        if let body = request.httpBody, !body.isEmpty {
            if let jsonObject = try? JSONSerialization.jsonObject(with: body),
               let prettyData = try? JSONSerialization.data(withJSONObject: jsonObject, options: .prettyPrinted),
               let prettyString = String(data: prettyData, encoding: .utf8) {
                let indentedBody = indentString(prettyString, prefix: "🌐 [Network] │     ")
                print("🌐 [Network] ├─ Body:")
                print(indentedBody)
            } else if let bodyString = String(data: body, encoding: .utf8) {
                print("🌐 [Network] ├─ Body: \(bodyString)")
            }
        }
        
        print("🌐 [Network] ────────────────────────────────────────")
        print("")
    }
    
    // MARK: - 응답(Response) 로그
    static func log(response: URLResponse?, data: Data?, error: Error? = nil) {
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        let isSuccess = (200...299).contains(statusCode)
        let statusEmoji = isSuccess ? "✅" : "❌"
        let statusText = isSuccess ? "SUCCESS" : "FAILURE"
        
        print("")
        print("🌐 [Network] ────────────────────────────────────────")
        print("🌐 [Network] 📥 RESPONSE")
        print("🌐 [Network] ├─ Status: \(statusEmoji) \(statusCode) \(statusText)")
        
        // 에러가 있는 경우
        if let error = error {
            print("🌐 [Network] ├─ Error: \(error.localizedDescription)")
        }
        
        // HTTP 상태 코드 설명
        if statusCode != 0 {
            let statusDescription = httpStatusDescription(statusCode)
            print("🌐 [Network] ├─ Description: \(statusDescription)")
        }
        
        // Data (JSON Pretty Print)
        if let data = data, !data.isEmpty {
            if let jsonObject = try? JSONSerialization.jsonObject(with: data),
               let prettyData = try? JSONSerialization.data(withJSONObject: jsonObject, options: .prettyPrinted),
               let prettyString = String(data: prettyData, encoding: .utf8) {
                // 데이터가 너무 긴 경우 요약
                if prettyString.count > 1000 {
                    let truncated = String(prettyString.prefix(1000)) + "\n... (truncated)"
                    let indentedData = indentString(truncated, prefix: "🌐 [Network] │     ")
                    print("🌐 [Network] ├─ Data (truncated):")
                    print(indentedData)
                } else {
                    let indentedData = indentString(prettyString, prefix: "🌐 [Network] │     ")
                    print("🌐 [Network] ├─ Data:")
                    print(indentedData)
                }
            } else if let rawString = String(data: data, encoding: .utf8) {
                print("🌐 [Network] ├─ Data (raw): \(rawString)")
            } else {
                print("🌐 [Network] ├─ Data: \(data.count) bytes (binary)")
            }
        }
        
        print("🌐 [Network] ────────────────────────────────────────")
        print("")
    }
    
    // MARK: - 에러 로그
    static func log(error: Error, for request: URLRequest? = nil) {
        let url = request?.url?.absoluteString ?? "N/A"
        
        print("")
        print("🌐 [Network] ────────────────────────────────────────")
        print("🌐 [Network] ⚠️ ERROR")
        if request != nil {
            print("🌐 [Network] ├─ URL: \(url)")
        }
        print("🌐 [Network] ├─ Error: ❌ \(error.localizedDescription)")
        print("🌐 [Network] ├─ Type: \(type(of: error))")
        print("🌐 [Network] ────────────────────────────────────────")
        print("")
    }
    
    // MARK: - Helper Methods
    
    /// 문자열 들여쓰기
    private static func indentString(_ string: String, prefix: String) -> String {
        return string
            .components(separatedBy: "\n")
            .map { prefix + $0 }
            .joined(separator: "\n")
    }
    
    /// 토큰 마스킹 (보안)
    private static func maskToken(_ token: String) -> String {
        if token.count <= 10 {
            return "****"
        }
        let prefix = String(token.prefix(6))
        let suffix = String(token.suffix(4))
        return "\(prefix)...\(suffix)"
    }
    
    /// HTTP 상태 코드 설명
    private static func httpStatusDescription(_ code: Int) -> String {
        switch code {
        case 200: return "OK"
        case 201: return "Created"
        case 204: return "No Content"
        case 400: return "Bad Request"
        case 401: return "Unauthorized"
        case 403: return "Forbidden"
        case 404: return "Not Found"
        case 405: return "Method Not Allowed"
        case 408: return "Request Timeout"
        case 409: return "Conflict"
        case 422: return "Unprocessable Entity"
        case 429: return "Too Many Requests"
        case 500: return "Internal Server Error"
        case 502: return "Bad Gateway"
        case 503: return "Service Unavailable"
        case 504: return "Gateway Timeout"
        default: return "Unknown Status"
        }
    }
}
