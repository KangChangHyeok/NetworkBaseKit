import Testing
import Foundation
@testable import NetworkKit

@Suite(.serialized)
struct NetworkKitTests {
    
    // 테스트용 가짜 API 정의
    enum TestAPI: Endpoint {
        case profile
        var host: String { "test.com" }
        var path: String { "/profile" }
        var method: HTTPMethod { .get }
        var header: [String : String]? { nil }
        var body: [String : Any]? { nil }
    }
    
    // 테스트용 데이터 모델
    struct TestUser: Decodable, Equatable {
        let name: String
    }
    
    // 1. Mock 설정 (URLSession이 MockURLProtocol을 쓰도록 설정)
    let mockSession = {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: config)
    }()

    @Test("성공적인 API 호출 및 디코딩 테스트")
    func testRequestSuccess() async throws {
        
        
        let manager = NetworkProvider(session: mockSession)
        
        // 2. 가짜 응답 데이터 준비
        let mockData = """
        { "name": "Gemini" }
        """.data(using: .utf8)!
        
        // 3. 요청이 오면 200 OK와 함께 데이터를 주라고 설정
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!,
                                           statusCode: 200,
                                           httpVersion: nil,
                                           headerFields: nil)!
            return (response, mockData)
        }
        
        // 4. 실행 및 검증 (#expect 사용)
        let result = try await manager.request(TestAPI.profile, type: TestUser.self)
        
        #expect(result.name == "Gemini")
    }
    
    @Test("404 에러 발생 시 적절한 NetworkError 반환 테스트")
    func testRequestFailure() async throws {
        let manager = NetworkProvider(session: mockSession)
        
        // 2. 요청이 오면 404 Not Found를 주라고 설정
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!,
                                           statusCode: 404,
                                           httpVersion: nil,
                                           headerFields: nil)!
            return (response, nil)
        }
        
        // 3. 에러가 발생하는지 검증 (expect throws)
        await #expect(throws: NetworkError.notFound) {
            try await manager.request(TestAPI.profile, type: TestUser.self)
        }
    }
    
    @Test("⚠️ [실패] JSON 키가 다르거나 타입이 틀리면 .decodingError 발생")
        func testDecodingError() async {
            
            let manager = NetworkProvider(session: mockSession)
            
            // Given: 'name'과 'age'가 필요한데, 'age' 대신 'isAdult'가 있는 엉뚱한 데이터 준비
            let wrongData = """
            {
                "isAdult": true
            }
            """.data(using: .utf8)!
            
            MockURLProtocol.requestHandler = { request in
                let response = HTTPURLResponse(url: request.url!,
                                               statusCode: 200, // 서버는 성공(200)이라고 줌
                                               httpVersion: nil,
                                               headerFields: nil)!
                return (response, wrongData)
            }
            
            // When & Then: 디코딩 에러가 발생하는지 확인
            await #expect(throws: NetworkError.decodingError) {
                try await manager.request(TestAPI.profile, type: TestUser.self)
            }
        }
        
        // MARK: - 2. 응답 없음/형식 오류 테스트 (No Response)
        
        @Test("🚫 [실패] HTTPURLResponse가 아닌 응답이 오면 .noResponse 발생")
        func testNoResponseError() async {
            let manager = NetworkProvider(session: mockSession)
            // Given: HTTPURLResponse가 아니라 그냥 URLResponse를 반환 (비정상 응답 시뮬레이션)
            MockURLProtocol.requestHandler = { request in
                let nonHttpResponse = URLResponse(url: request.url!,
                                                  mimeType: nil,
                                                  expectedContentLength: 0,
                                                  textEncodingName: nil)
                return (nonHttpResponse, nil)
            }
            
            // When & Then: guard let httpResponse = response as? HTTPURLResponse 실패 확인
            await #expect(throws: NetworkError.noResponse) {
                try await manager.request(TestAPI.profile, type: TestUser.self)
            }
        }
}
