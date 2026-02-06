//
//  NetworkLogger.swift
//  NetworkKit
//
//  Created by changhyeok on 1/24/26.
//

import Foundation
import OSLog

public struct NetworkLogger {
    
    // MARK: - OSLog Logger
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "NetworkBaseKit", category: "Network")
    
    // MARK: - 요청(Request) 로그
    public static func log(request: URLRequest) {
        let method = request.httpMethod ?? "UNKNOWN"
        let url = request.url?.absoluteString ?? "N/A"
        
        var message = """
        
        ────────────────────────────────────────
        📤 REQUEST
        ├─ Method: \(method)
        ├─ URL: \(url)
        """
        
        // Header
        if let headers = request.allHTTPHeaderFields, !headers.isEmpty {
            message += "\n├─ Headers:"
            for (key, value) in headers {
                if key.lowercased() == "authorization" {
                    let maskedValue = maskToken(value)
                    message += "\n│     \(key): \(maskedValue)"
                } else {
                    message += "\n│     \(key): \(value)"
                }
            }
        }
        
        // Body (JSON)
        if let body = request.httpBody, !body.isEmpty {
            if let jsonObject = try? JSONSerialization.jsonObject(with: body),
               let prettyData = try? JSONSerialization.data(withJSONObject: jsonObject, options: .prettyPrinted),
               let prettyString = String(data: prettyData, encoding: .utf8) {
                message += "\n├─ Body:\n\(indent(prettyString))"
            } else if let bodyString = String(data: body, encoding: .utf8) {
                message += "\n├─ Body: \(bodyString)"
            }
        }
        
        message += "\n────────────────────────────────────────"
        
        logger.info("\(message)")
    }
    
    // MARK: - 응답(Response) 로그
    public static func log(response: URLResponse?, data: Data?, error: Error? = nil) {
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        let isSuccess = (200...299).contains(statusCode)
        let statusEmoji = isSuccess ? "✅" : "❌"
        let statusText = isSuccess ? "SUCCESS" : "FAILURE"
        let statusDescription = httpStatusDescription(statusCode)
        
        var message = """
        
        ────────────────────────────────────────
        📥 RESPONSE
        ├─ Status: \(statusEmoji) \(statusCode) \(statusText)
        """
        
        // 에러가 있는 경우
        if let error = error {
            message += "\n├─ Error: \(error.localizedDescription)"
        }
        
        // HTTP 상태 코드 설명
        if statusCode != 0 {
            message += "\n├─ Description: \(statusDescription)"
        }
        
        // Data (JSON Pretty Print)
        if let data = data, !data.isEmpty {
            if let jsonObject = try? JSONSerialization.jsonObject(with: data),
               let prettyData = try? JSONSerialization.data(withJSONObject: jsonObject, options: .prettyPrinted),
               let prettyString = String(data: prettyData, encoding: .utf8) {
                if prettyString.count > 1000 {
                    let truncated = String(prettyString.prefix(1000)) + "\n... (truncated)"
                    message += "\n├─ Data (truncated):\n\(indent(truncated))"
                } else {
                    message += "\n├─ Data:\n\(indent(prettyString))"
                }
            } else if let rawString = String(data: data, encoding: .utf8) {
                message += "\n├─ Data (raw): \(rawString)"
            } else {
                message += "\n├─ Data: \(data.count) bytes (binary)"
            }
        }
        
        message += "\n────────────────────────────────────────"
        
        if isSuccess {
            logger.info("\(message)")
        } else {
            logger.error("\(message)")
        }
    }
    
    // MARK: - 에러 로그
    public static func log(error: Error, for request: URLRequest? = nil) {
        let url = request?.url?.absoluteString ?? "N/A"
        
        var message = """
        
        ────────────────────────────────────────
        ⚠️ ERROR
        """
        
        if request != nil {
            message += "\n├─ URL: \(url)"
        }
        
        message += """
        
        ├─ Error: ❌ \(error.localizedDescription)
        ├─ Type: \(type(of: error))
        ────────────────────────────────────────
        """
        
        logger.error("\(message)")
    }
    
    // MARK: - Helper Methods
    
    /// 문자열 들여쓰기
    private static func indent(_ string: String) -> String {
        return string
            .components(separatedBy: "\n")
            .map { "│     " + $0 }
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
