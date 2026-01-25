//
//  File.swift
//  NetworkKit
//
//  Created by changhyeok on 1/24/26.
//

// Test 폴더 내에 작성
import Foundation
import NetworkKit // 라이브러리 임포트

class MockURLProtocol: URLProtocol {
    // 테스트에서 주입할 핸들러 (요청이 오면 무엇을 리턴할지 결정)
    nonisolated(unsafe) static var requestHandler: ((URLRequest) throws -> (URLResponse, Data?))?
    
    override class func canInit(with request: URLRequest) -> Bool {
        return true // 모든 요청을 이 프로토콜이 처리함
    }
    
    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        return request
    }
    
    override func startLoading() {
        guard let handler = MockURLProtocol.requestHandler else {
            fatalError("Handler is unavailable.")
        }
        
        do {
            // 핸들러가 시키는 대로 응답 생성
            let (response, data) = try handler(request)
            
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            if let data = data {
                client?.urlProtocol(self, didLoad: data)
            }
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }
    
    override func stopLoading() {}
}
