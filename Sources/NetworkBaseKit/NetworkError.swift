//
//  File.swift
//  NetworkKit
//
//  Created by changhyeok on 1/23/26.
//

import Foundation

public enum NetworkError: Error, Equatable {
    // 400 ~ 406: Client Errors
    case badRequest          // 400: 잘못된 요청
    case unauthorized        // 401: 인증 실패 (로그인 필요)
    case paymentRequired     // 402: 결제 필요
    case forbidden           // 403: 접근 금지 (권한 없음)
    case notFound            // 404: 찾을 수 없음
    case methodNotAllowed    // 405: 허용되지 않은 메서드
    case notAcceptable       // 406: 허용되지 않은 포맷

    // 500: Server Error
    case serverError         // 500: 내부 서버 오류
    
    // 그 외 처리
    case unexpected(statusCode: Int) // 정의되지 않은 나머지 에러 코드
    case invalidURL                  // URL 생성 실패
    case noResponse                  // 응답 없음
    case decodingError               // 디코딩 실패
}

// 상태 코드로 에러를 매핑하는 생성자
extension NetworkError {
    /// HTTP 상태 코드를 받아서 적절한 에러를 반환합니다.
    /// 200~299 사이의 성공 코드인 경우 nil을 반환합니다.
    init?(statusCode: Int) {
        switch statusCode {
        case 200...299: return nil // 성공이므로 에러 없음
            
        case 400: self = .badRequest
        case 401: self = .unauthorized
        case 402: self = .paymentRequired
        case 403: self = .forbidden
        case 404: self = .notFound
        case 405: self = .methodNotAllowed
        case 406: self = .notAcceptable
            
        case 500: self = .serverError
            
        default: self = .unexpected(statusCode: statusCode)
        }
    }
}

// 에러 메시지를 사람이 읽기 쉽게 변환 (디버깅 용이)
extension NetworkError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .badRequest:       return "잘못된 요청입니다. (400)"
        case .unauthorized:     return "인증이 필요합니다. (401)"
        case .paymentRequired:  return "결제가 필요합니다. (402)"
        case .forbidden:        return "접근 권한이 없습니다. (403)"
        case .notFound:         return "요청한 리소스를 찾을 수 없습니다. (404)"
        case .methodNotAllowed: return "허용되지 않은 HTTP 메서드입니다. (405)"
        case .notAcceptable:    return "허용되지 않은 콘텐츠 포맷입니다. (406)"
        case .serverError:      return "서버 내부 오류가 발생했습니다. (500)"
        case .unexpected(let code): return "알 수 없는 에러가 발생했습니다. 상태 코드: \(code)"
        case .invalidURL:       return "유효하지 않은 URL입니다."
        case .noResponse:       return "서버로부터 응답이 없습니다."
        case .decodingError:    return "데이터 디코딩에 실패했습니다."
        }
    }
}
