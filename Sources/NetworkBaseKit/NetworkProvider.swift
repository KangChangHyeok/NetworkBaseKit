// The Swift Programming Language
// https://docs.swift.org/swift-book



import Foundation

public actor NetworkProvider {
    
    // 1. 싱글톤 인스턴스
    fileprivate static let shared = NetworkProvider()
    
    // 2. 세션 설정 (필요하면 커스텀 가능)
    private let session: URLSession
    
    // 커스텀 세션 주입 가능성 열어둠
    public init(session: URLSession = .shared) {
        self.session = session
    }
    
    // 3. 실제 네트워킹 로직
    // T: Decodable - 어떤 데이터 모델이든 들어올 수 있음 (Generic)
    public func request<T: Decodable & Sendable>(_ endpoint: Endpoint, type: T.Type) async throws -> T {
        
        // 1) Endpoint -> URLRequest 변환
        let request = try endpoint.asURLRequest()
        
        // ✅ [Logger] 요청 로그 출력 (출발 전)
        NetworkLogger.log(request: request)
        
        // 2) 통신 수행 (비동기)
        let (data, response) = try await session.data(for: request)
        
        // ✅ [Logger] 응답 로그 출력 (도착 후)
        NetworkLogger.log(response: response, data: data)
        
        // 3) HTTP 상태 코드 검증
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NetworkError.noResponse
        }
        
        // 앞서 만든 상태 코드별 에러 처리 로직
        if let error = NetworkError(statusCode: httpResponse.statusCode) {
            throw error
        }
        
        // 4) 디코딩 (Data -> Struct)
        do {
            let decoder = JSONDecoder()
            // 서버에서 snake_case로 올 경우를 대비해 keyDecodingStrategy 설정 가능
            // decoder.keyDecodingStrategy = .convertFromSnakeCase
            let decodedData = try decoder.decode(T.self, from: data)
            return decodedData
        } catch {
            NetworkLogger.log(error: error, for: request)
            throw NetworkError.decodingError
        }
    }
}

// NetworkManager(또는 API) 내부에 추가
extension NetworkProvider {
    
    // static 메서드가 내부의 shared를 대신 호출해줌
    public static func request<T: Decodable & Sendable>(_ endpoint: Endpoint, type: T.Type) async throws -> T {
        return try await shared.request(endpoint, type: type)
    }
}
