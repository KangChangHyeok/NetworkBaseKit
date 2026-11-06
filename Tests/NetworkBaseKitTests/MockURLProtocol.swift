//
//  MockURLProtocol.swift
//  NetworkBaseKitTests
//
//  Created by changhyeok on 1/24/26.
//

import Foundation

/// 테스트용 URLProtocol.
/// 세션마다 고유 ID를 헤더로 심어두고, 그 ID로 핸들러를 찾기 때문에
/// 여러 테스트가 병렬로 실행되어도 서로의 핸들러를 덮어쓰지 않습니다.
final class MockURLProtocol: URLProtocol, @unchecked Sendable {
    typealias Handler = @Sendable (URLRequest) throws -> (URLResponse, Data?)

    static let sessionIDHeader = "X-Mock-Session-ID"

    private static let lock = NSLock()
    nonisolated(unsafe) private static var handlers: [String: (delay: TimeInterval, handler: Handler)] = [:]

    static func register(_ id: String, delay: TimeInterval = 0, handler: @escaping Handler) {
        lock.withLock { handlers[id] = (delay, handler) }
    }

    private static func entry(for id: String) -> (delay: TimeInterval, handler: Handler)? {
        lock.withLock { handlers[id] }
    }

    private let isStopped = Box(false)

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let id = request.value(forHTTPHeaderField: Self.sessionIDHeader),
              let (delay, handler) = Self.entry(for: id) else {
            client?.urlProtocol(self, didFailWithError: URLError(.unknown))
            return
        }

        guard delay > 0 else { respond(with: handler); return }
        // 로딩 스레드를 막지 않도록 지연 응답은 비동기로 처리
        DispatchQueue.global().asyncAfter(deadline: .now() + delay) { [self] in
            guard !isStopped.value else { return }
            respond(with: handler)
        }
    }

    private func respond(with handler: Handler) {
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            if let data { client?.urlProtocol(self, didLoad: data) }
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() { isStopped.value = true }
}

/// 한 테스트 전용 Mock 세션.
struct MockServer {
    let session: URLSession
    private let id = UUID().uuidString

    init(delay: TimeInterval = 0, handler: @escaping MockURLProtocol.Handler) {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        config.httpAdditionalHeaders = [MockURLProtocol.sessionIDHeader: id]
        session = URLSession(configuration: config)
        MockURLProtocol.register(id, delay: delay, handler: handler)
    }

    /// 상태 코드와 body만으로 응답하는 간단한 Mock.
    init(statusCode: Int, body: String? = nil, headers: [String: String]? = nil) {
        self.init { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: statusCode,
                                           httpVersion: nil, headerFields: headers)!
            return (response, body?.data(using: .utf8))
        }
    }
}

/// URLSession을 거친 요청은 httpBody가 httpBodyStream으로 바뀌므로 다시 읽어옵니다.
extension URLRequest {
    var bodyData: Data? {
        if let httpBody { return httpBody }
        guard let stream = httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        let bufferSize = 1024
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }
        while stream.hasBytesAvailable {
            let read = stream.read(buffer, maxLength: bufferSize)
            if read <= 0 { break }
            data.append(buffer, count: read)
        }
        return data
    }
}

/// 별도 스레드에서 호출되는 핸들러가 값을 기록할 때 쓰는 thread-safe 상자.
final class Box<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var _value: Value
    init(_ value: Value) { _value = value }
    var value: Value {
        get { lock.withLock { _value } }
        set { lock.withLock { _value = newValue } }
    }
}
