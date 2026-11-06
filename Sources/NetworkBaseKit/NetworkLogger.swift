//
//  NetworkLogger.swift
//  NetworkBaseKit
//
//  Created by changhyeok on 1/24/26.
//

import Foundation
import OSLog

/// Postman Console처럼 요청/응답을 출력하는 로거.
///
/// ```swift
/// var logger = NetworkLogger(level: .verbose)
/// logger.redactedBodyKeys.insert("ssn")
/// let provider = NetworkProvider(environment: .dev, logger: logger)
/// ```
public struct NetworkLogger: Sendable {

    public enum Level: Int, Sendable, Comparable {
        /// 출력하지 않음
        case off = 0
        /// 실패한 요청만 출력
        case error
        /// 요청/응답을 한 줄로 요약 (메서드, URL, 상태 코드, 소요 시간)
        case basic
        /// 헤더, Body, cURL까지 모두 출력
        case verbose

        public static func < (lhs: Level, rhs: Level) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    /// OSLog에 기록할 때의 공개 여부.
    /// `.private`면 디버거가 붙어 있지 않을 때 Console.app에서 `<private>`로 표시됩니다.
    public enum Privacy: Sendable {
        case `public`
        case `private`
    }

    public var level: Level
    public var privacy: Privacy
    /// 값을 가릴 헤더 이름 (대소문자 무시)
    public var redactedHeaders: Set<String>
    /// 값을 가릴 JSON body 키 (대소문자 무시, 중첩 객체/배열까지 적용)
    public var redactedBodyKeys: Set<String>
    /// Body 출력 최대 길이 (초과분은 잘림)
    public var maxBodyLength: Int
    /// verbose 레벨에서 cURL 명령을 함께 출력할지 여부
    public var includesCURL: Bool
    /// 출력 대상. nil이면 OSLog로 출력합니다. (테스트나 자체 로깅 시스템 연동용)
    public var output: (@Sendable (_ message: String, _ isError: Bool) -> Void)?

    public init(level: Level = .verbose,
                privacy: Privacy = .public,
                redactedHeaders: Set<String> = ["Authorization", "Proxy-Authorization", "Cookie", "Set-Cookie", "X-API-Key"],
                redactedBodyKeys: Set<String> = ["password", "token", "accessToken", "refreshToken", "access_token", "refresh_token", "secret"],
                maxBodyLength: Int = 2000,
                includesCURL: Bool = true,
                output: (@Sendable (_ message: String, _ isError: Bool) -> Void)? = nil) {
        self.level = level
        self.privacy = privacy
        self.redactedHeaders = redactedHeaders
        self.redactedBodyKeys = redactedBodyKeys
        self.maxBodyLength = maxBodyLength
        self.includesCURL = includesCURL
        self.output = output
    }

    /// DEBUG 빌드에서는 verbose, 릴리즈 빌드에서는 off
    public static var `default`: NetworkLogger {
        #if DEBUG
        NetworkLogger(level: .verbose)
        #else
        NetworkLogger(level: .off)
        #endif
    }

    public static let disabled = NetworkLogger(level: .off)

    private static let osLogger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "NetworkBaseKit", category: "Network")

    // MARK: - Events

    func logRequest(_ request: URLRequest, id: String, attempt: Int) {
        guard level >= .basic else { return }
        let retry = attempt > 0 ? " (retry #\(attempt))" : ""
        let summary = "📤 [\(id)] \(request.httpMethod ?? "GET") \(request.url?.absoluteString ?? "N/A")\(retry)"

        guard level == .verbose else { return emit(summary, isError: false) }

        var lines = [divider, summary]
        appendHeaders(request.allHTTPHeaderFields ?? [:], to: &lines)
        if let body = request.httpBody, !body.isEmpty {
            lines.append("├─ Body:")
            lines.append(indent(format(body)))
        }
        if includesCURL {
            lines.append("├─ cURL:")
            lines.append(indent(cURL(for: request)))
        }
        lines.append(divider)
        emit(lines.joined(separator: "\n"), isError: false)
    }

    func logResponse(_ response: HTTPURLResponse, data: Data, for request: URLRequest, id: String, duration: TimeInterval) {
        let isSuccess = (200...299).contains(response.statusCode)
        guard level >= .basic || (level == .error && !isSuccess) else { return }

        let emoji = isSuccess ? "✅" : "❌"
        let status = "\(response.statusCode) \(HTTPURLResponse.localizedString(forStatusCode: response.statusCode))"
        let summary = "📥 [\(id)] \(emoji) \(status) \(request.httpMethod ?? "GET") \(request.url?.absoluteString ?? "N/A") (\(formatDuration(duration)), \(formatSize(data.count)))"

        guard level == .verbose || !isSuccess else { return emit(summary, isError: false) }

        var lines = [divider, summary]
        if level == .verbose {
            appendHeaders(response.stringHeaders, to: &lines)
        }
        if !data.isEmpty {
            lines.append("├─ Body:")
            lines.append(indent(format(data)))
        }
        lines.append(divider)
        emit(lines.joined(separator: "\n"), isError: !isSuccess)
    }

    func logError(_ error: NetworkError, for request: URLRequest, id: String, duration: TimeInterval? = nil) {
        guard level >= .error else { return }
        let elapsed = duration.map { " (\(formatDuration($0)))" } ?? ""
        let message = "⚠️ [\(id)] \(request.httpMethod ?? "GET") \(request.url?.absoluteString ?? "N/A")\(elapsed)\n└─ \(error.localizedDescription)"
        emit(message, isError: true)
    }

    // MARK: - cURL

    /// Postman이나 터미널에 그대로 붙여 넣어 재현할 수 있는 cURL 명령. 민감한 값은 가려집니다.
    public func cURL(for request: URLRequest) -> String {
        var parts = ["curl -X \(request.httpMethod ?? "GET")"]
        parts.append(shellQuote(request.url?.absoluteString ?? ""))
        for (key, value) in (request.allHTTPHeaderFields ?? [:]).sorted(by: { $0.key < $1.key }) {
            parts.append("-H \(shellQuote("\(key): \(redactHeader(key, value))"))")
        }
        if let body = request.httpBody, !body.isEmpty {
            if let string = String(data: redactBody(body), encoding: .utf8) {
                parts.append("--data-raw \(shellQuote(string))")
            } else {
                parts.append("--data-binary '<\(body.count) bytes>'")
            }
        }
        return parts.joined(separator: " \\\n  ")
    }

    // MARK: - Redaction

    func redactHeader(_ name: String, _ value: String) -> String {
        guard redactedHeaders.contains(where: { $0.caseInsensitiveCompare(name) == .orderedSame }) else { return value }
        guard value.count > 12 else { return "****" }
        return "\(value.prefix(6))…\(value.suffix(4))"
    }

    func redactBody(_ data: Data) -> Data {
        guard !redactedBodyKeys.isEmpty,
              let object = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]),
              let redacted = try? JSONSerialization.data(withJSONObject: redact(object), options: [.fragmentsAllowed, .sortedKeys]) else {
            return data
        }
        return redacted
    }

    private func redact(_ object: Any) -> Any {
        let keys = Set(redactedBodyKeys.map { $0.lowercased() })
        if let dictionary = object as? [String: Any] {
            return dictionary.reduce(into: [String: Any]()) { result, pair in
                result[pair.key] = keys.contains(pair.key.lowercased()) ? "****" : redact(pair.value)
            }
        }
        if let array = object as? [Any] {
            return array.map(redact)
        }
        return object
    }

    // MARK: - Formatting

    private var divider: String { "────────────────────────────────────────" }

    private func appendHeaders(_ headers: [String: String], to lines: inout [String]) {
        guard !headers.isEmpty else { return }
        lines.append("├─ Headers:")
        for (key, value) in headers.sorted(by: { $0.key < $1.key }) {
            lines.append("│     \(key): \(redactHeader(key, value))")
        }
    }

    /// JSON이면 마스킹 후 pretty print, 아니면 문자열 또는 바이트 수
    private func format(_ data: Data) -> String {
        let text: String
        if let object = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]),
           let pretty = try? JSONSerialization.data(withJSONObject: redact(object),
                                                    options: [.prettyPrinted, .sortedKeys, .fragmentsAllowed]),
           let string = String(data: pretty, encoding: .utf8) {
            text = string
        } else if let string = String(data: data, encoding: .utf8) {
            text = string
        } else {
            return "<\(formatSize(data.count)) binary>"
        }
        guard text.count > maxBodyLength else { return text }
        return String(text.prefix(maxBodyLength)) + "\n… (truncated, total \(formatSize(data.count)))"
    }

    private func indent(_ string: String) -> String {
        string.split(separator: "\n", omittingEmptySubsequences: false)
            .map { "│     " + $0 }
            .joined(separator: "\n")
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        duration < 1 ? "\(Int(duration * 1000))ms" : String(format: "%.2fs", duration)
    }

    private func formatSize(_ bytes: Int) -> String {
        bytes < 1024 ? "\(bytes)B" : String(format: "%.1fKB", Double(bytes) / 1024)
    }

    private func shellQuote(_ string: String) -> String {
        "'" + string.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    // MARK: - Output

    private func emit(_ message: String, isError: Bool) {
        if let output {
            output(message, isError)
            return
        }
        let type: OSLogType = isError ? .error : .info
        switch privacy {
        case .public:  Self.osLogger.log(level: type, "\(message, privacy: .public)")
        case .private: Self.osLogger.log(level: type, "\(message, privacy: .private)")
        }
    }
}
