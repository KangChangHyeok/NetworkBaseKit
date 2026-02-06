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
        
        logger.info("────────────────────────────────────────")
        logger.info("📤 REQUEST")
        logger.info("├─ Method: \(method)")
        logger.info("├─ URL: \(url)")
        
        // Header
        if let headers = request.allHTTPHeaderFields, !headers.isEmpty {
            logger.info("├─ Headers:")
            for (key, value) in headers {
                // 민감한 정보 마스킹 (예: Authorization)
                if key.lowercased() == "authorization" {
                    let maskedValue = maskToken(value)
                    logger.info("│     \(key): \(maskedValue)")
                } else {
                    logger.info("│     \(key): \(value)")
                }
            }
        }
        
        // Body (JSON)
        if let body = request.httpBody, !body.isEmpty {
            if let jsonObject = try? JSONSerialization.jsonObject(with: body),
               let prettyData = try? JSONSerialization.data(withJSONObject: jsonObject, options: .prettyPrinted),
               let prettyString = String(data: prettyData, encoding: .utf8) {
                logger.info("├─ Body:")
                for line in prettyString.components(separatedBy: "\n") {
                    logger.info("│     \(line)")
                }
            } else if let bodyString = String(data: body, encoding: .utf8) {
                logger.info("├─ Body: \(bodyString)")
            }
        }
        
        logger.info("────────────────────────────────────────")
    }
    
    // MARK: - 응답(Response) 로그
    public static func log(response: URLResponse?, data: Data?, error: Error? = nil) {
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        let isSuccess = (200...299).contains(statusCode)
        let statusEmoji = isSuccess ? "✅" : "❌"
        let statusText = isSuccess ? "SUCCESS" : "FAILURE"
        let statusDescription = httpStatusDescription(statusCode)
        
        logger.info("────────────────────────────────────────")
        
        if isSuccess {
            logger.info("📥 RESPONSE")
            logger.info("├─ Status: \(statusEmoji) \(statusCode) \(statusText)")
        } else {
            logger.error("📥 RESPONSE")
            logger.error("├─ Status: \(statusEmoji) \(statusCode) \(statusText)")
        }
        
        // 에러가 있는 경우
        if let error = error {
            logger.error("├─ Error: \(error.localizedDescription)")
        }
        
        // HTTP 상태 코드 설명
        if statusCode != 0 {
            if isSuccess {
                logger.info("├─ Description: \(statusDescription)")
            } else {
                logger.error("├─ Description: \(statusDescription)")
            }
        }
        
        // Data (JSON Pretty Print)
        if let data = data, !data.isEmpty {
            if let jsonObject = try? JSONSerialization.jsonObject(with: data),
               let prettyData = try? JSONSerialization.data(withJSONObject: jsonObject, options: .prettyPrinted),
               let prettyString = String(data: prettyData, encoding: .utf8) {
                // 데이터가 너무 긴 경우 요약
                let displayString: String
                if prettyString.count > 1000 {
                    displayString = String(prettyString.prefix(1000)) + "\n... (truncated)"
                    logger.info("├─ Data (truncated):")
                } else {
                    displayString = prettyString
                    logger.info("├─ Data:")
                }
                for line in displayString.components(separatedBy: "\n") {
                    logger.info("│     \(line)")
                }
            } else if let rawString = String(data: data, encoding: .utf8) {
                logger.info("├─ Data (raw): \(rawString)")
            } else {
                logger.info("├─ Data: \(data.count) bytes (binary)")
            }
        }
        
        logger.info("────────────────────────────────────────")
    }
    
    // MARK: - 에러 로그
    public static func log(error: Error, for request: URLRequest? = nil) {
        let url = request?.url?.absoluteString ?? "N/A"
        
        logger.error("────────────────────────────────────────")
        logger.error("⚠️ ERROR")
        
        if request != nil {
            logger.error("├─ URL: \(url)")
        }
        
        logger.error("├─ Error: ❌ \(error.localizedDescription)")
        logger.error("├─ Type: \(String(describing: type(of: error)))")
        logger.error("────────────────────────────────────────")
    }
    
    // MARK: - Helper Methods
    
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
