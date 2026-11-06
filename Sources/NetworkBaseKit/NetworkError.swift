//
//  NetworkError.swift
//  NetworkBaseKit
//
//  Created by changhyeok on 1/23/26.
//

import Foundation

/// 서버가 2xx가 아닌 상태 코드로 응답했을 때의 응답 정보.
/// Postman에서 실패 응답도 Body/Headers를 볼 수 있는 것처럼, 응답을 버리지 않고 보관합니다.
public struct HTTPErrorResponse: Sendable, Equatable {
    public let statusCode: Int
    public let data: Data
    public let headers: [String: String]

    public init(statusCode: Int, data: Data = Data(), headers: [String: String] = [:]) {
        self.statusCode = statusCode
        self.data = data
        self.headers = headers
    }

    /// 에러 응답 body를 원하는 모델로 디코딩합니다. 예: `{"message": "이미 가입된 이메일"}`
    public func decode<T: Decodable>(_ type: T.Type, using decoder: JSONDecoder = JSONDecoder()) -> T? {
        try? decoder.decode(type, from: data)
    }

    /// 에러 응답 body를 문자열로 반환합니다.
    public var bodyString: String? { String(data: data, encoding: .utf8) }
}

public enum NetworkError: Error {
    // 요청 생성 단계
    case invalidURL                                   // URL 생성 실패
    case encodingFailed(underlying: (any Error)?)     // Body 인코딩 실패
    case interceptorFailed(underlying: any Error)     // Interceptor의 adapt 실패

    // 전송 단계
    case transport(URLError)                          // 오프라인, 타임아웃, DNS 실패 등
    case cancelled                                    // Task 취소 / URLError.cancelled
    case noResponse                                   // HTTPURLResponse가 아닌 응답

    // 응답 단계
    case clientError(HTTPErrorResponse)               // 4xx
    case serverError(HTTPErrorResponse)               // 5xx
    case unexpectedStatus(HTTPErrorResponse)          // 1xx, 3xx 등 그 외
    case decodingFailed(underlying: any Error, data: Data) // 디코딩 실패
}

// MARK: - 상태 코드 매핑

extension NetworkError {
    /// 2xx면 nil, 아니면 상태 코드 범위에 맞는 에러를 반환합니다.
    init?(response: HTTPURLResponse, data: Data) {
        let errorResponse = HTTPErrorResponse(statusCode: response.statusCode, data: data,
                                              headers: response.stringHeaders)

        switch response.statusCode {
        case 200...299: return nil
        case 400...499: self = .clientError(errorResponse)
        case 500...599: self = .serverError(errorResponse)
        default:        self = .unexpectedStatus(errorResponse)
        }
    }

    /// URLSession이 던진 에러를 NetworkError로 변환합니다.
    static func from(transportError error: any Error) -> NetworkError {
        if let networkError = error as? NetworkError { return networkError }
        if error is CancellationError { return .cancelled }
        if let urlError = error as? URLError {
            return urlError.code == .cancelled ? .cancelled : .transport(urlError)
        }
        return .transport(URLError(.unknown, userInfo: [NSUnderlyingErrorKey: error]))
    }
}

// MARK: - 편의 프로퍼티

public extension NetworkError {
    /// HTTP 상태 코드 에러일 때의 응답 정보
    var response: HTTPErrorResponse? {
        switch self {
        case .clientError(let r), .serverError(let r), .unexpectedStatus(let r): return r
        default: return nil
        }
    }

    /// HTTP 상태 코드 (상태 코드 에러가 아니면 nil)
    var statusCode: Int? { response?.statusCode }

    var isUnauthorized: Bool { statusCode == 401 }
    var isForbidden: Bool { statusCode == 403 }
    var isNotFound: Bool { statusCode == 404 }

    /// 네트워크 연결 문제(오프라인, 타임아웃 등)인지 여부
    var isConnectivityError: Bool {
        guard case .transport(let error) = self else { return false }
        return [.notConnectedToInternet, .timedOut, .networkConnectionLost,
                .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed].contains(error.code)
    }

    var isCancelled: Bool {
        if case .cancelled = self { return true }
        return false
    }
}

// MARK: - 에러 메시지

extension NetworkError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "유효하지 않은 URL입니다."
        case .encodingFailed(let error):
            return "요청 Body 인코딩에 실패했습니다." + (error.map { " (\($0.localizedDescription))" } ?? "")
        case .interceptorFailed(let error):
            return "요청 준비(Interceptor) 중 오류가 발생했습니다. (\(error.localizedDescription))"
        case .transport(let error):
            return "네트워크 오류가 발생했습니다. (\(error.localizedDescription))"
        case .cancelled:
            return "요청이 취소되었습니다."
        case .noResponse:
            return "서버로부터 올바른 응답을 받지 못했습니다."
        case .clientError(let r):
            return "요청 오류입니다. (\(r.statusCode) \(HTTPURLResponse.localizedString(forStatusCode: r.statusCode)))"
        case .serverError(let r):
            return "서버 오류입니다. (\(r.statusCode) \(HTTPURLResponse.localizedString(forStatusCode: r.statusCode)))"
        case .unexpectedStatus(let r):
            return "예상하지 못한 상태 코드입니다. (\(r.statusCode))"
        case .decodingFailed(let error, _):
            return "데이터 디코딩에 실패했습니다. (\(Self.describe(decodingError: error)))"
        }
    }

    /// DecodingError를 어떤 키에서 실패했는지 알 수 있게 풀어서 설명합니다.
    static func describe(decodingError error: any Error) -> String {
        guard let error = error as? DecodingError else { return error.localizedDescription }
        func path(_ context: DecodingError.Context) -> String {
            let path = context.codingPath.map(\.stringValue).joined(separator: ".")
            return path.isEmpty ? "<root>" : path
        }
        switch error {
        case .keyNotFound(let key, let context):
            return "키 '\(key.stringValue)'가 없습니다. 위치: \(path(context))"
        case .typeMismatch(let type, let context):
            return "타입 불일치 (\(type) 기대). 위치: \(path(context))"
        case .valueNotFound(let type, let context):
            return "값이 null입니다 (\(type) 기대). 위치: \(path(context))"
        case .dataCorrupted(let context):
            return "데이터 손상: \(context.debugDescription). 위치: \(path(context))"
        @unknown default:
            return error.localizedDescription
        }
    }
}
