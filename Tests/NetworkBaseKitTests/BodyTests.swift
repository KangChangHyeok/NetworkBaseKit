import Testing
import Foundation
@testable import NetworkBaseKit

struct BodyTests {

    struct API: Endpoint {
        var path: String = "/items"
        var method: HTTPMethod = .post
        nonisolated(unsafe) var bodyValue: HTTPBody? = nil
        nonisolated(unsafe) var encoderValue: JSONEncoder? = nil
        nonisolated(unsafe) var decoderValue: JSONDecoder? = nil
        var body: HTTPBody? { bodyValue }
        var encoder: JSONEncoder? { encoderValue }
        var decoder: JSONDecoder? { decoderValue }
    }

    struct SignUp: Encodable { let userName: String; let birthDate: Date }
    struct Item: Decodable, Sendable { let itemName: String }

    let env = NetworkEnvironment(baseURL: "https://api.com")

    func json(_ data: Data?) throws -> [String: Any] {
        let data = try #require(data)
        return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    @Test("딕셔너리 리터럴은 기존처럼 JSON body가 됨")
    func dictionaryLiteral() throws {
        let request = try NetworkProvider(environment: env)
            .urlRequest(for: API(bodyValue: ["name": "a", "tags": [1, 2]]))
        let object = try json(request.httpBody)
        #expect(object["name"] as? String == "a")
        #expect(object["tags"] as? [Int] == [1, 2])
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
    }

    @Test("최상위 배열도 jsonObject로 전송 가능")
    func topLevelArray() throws {
        let request = try NetworkProvider(environment: env).urlRequest(for: API(bodyValue: .jsonObject([1, 2, 3])))
        #expect(String(data: request.httpBody!, encoding: .utf8) == "[1,2,3]")
    }

    @Test("Encodable 모델은 Provider의 encoder 전략으로 인코딩")
    func encodableUsesProviderEncoder() throws {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.dateEncodingStrategy = .secondsSince1970
        let provider = NetworkProvider(environment: env, encoder: encoder)

        let request = try provider.urlRequest(for: API(bodyValue: .json(SignUp(userName: "kim", birthDate: Date(timeIntervalSince1970: 100)))))
        let object = try json(request.httpBody)
        #expect(object["user_name"] as? String == "kim")
        #expect(object["birth_date"] as? Double == 100)
    }

    @Test("Endpoint의 encoder가 Provider보다 우선")
    func endpointEncoderOverrides() throws {
        let snake = JSONEncoder()
        snake.keyEncodingStrategy = .convertToSnakeCase
        let request = try NetworkProvider(environment: env, encoder: snake)
            .urlRequest(for: API(bodyValue: .json(["userName": "kim"]), encoderValue: JSONEncoder()))
        #expect(try json(request.httpBody)["userName"] as? String == "kim")
    }

    @Test("x-www-form-urlencoded: 정렬된 키, 공백은 +, 특수문자는 퍼센트 인코딩")
    func formURLEncoded() throws {
        let request = try NetworkProvider(environment: env)
            .urlRequest(for: API(bodyValue: .form(["q": "a b&c=d", "lang": "한"])))
        #expect(String(data: request.httpBody!, encoding: .utf8) == "lang=%ED%95%9C&q=a+b%26c%3Dd")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/x-www-form-urlencoded; charset=utf-8")
    }

    @Test("multipart/form-data: boundary와 파트 구성")
    func multipart() throws {
        let formData = MultipartFormData(boundary: "XYZ", parts: [
            .text(name: "title", value: "hello"),
            .file(name: "image", data: Data([0xFF, 0xD8]), fileName: "a.jpg", mimeType: "image/jpeg"),
        ])
        let request = try NetworkProvider(environment: env).urlRequest(for: API(bodyValue: .multipart(formData)))
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "multipart/form-data; boundary=XYZ")

        var expected = Data()
        expected.append(Data("--XYZ\r\nContent-Disposition: form-data; name=\"title\"\r\n\r\nhello\r\n".utf8))
        expected.append(Data("--XYZ\r\nContent-Disposition: form-data; name=\"image\"; filename=\"a.jpg\"\r\nContent-Type: image/jpeg\r\n\r\n".utf8))
        expected.append(Data([0xFF, 0xD8]))
        expected.append(Data("\r\n--XYZ--\r\n".utf8))
        #expect(request.httpBody == expected)
    }

    @Test("raw body는 지정한 Content-Type 그대로")
    func raw() throws {
        let request = try NetworkProvider(environment: env)
            .urlRequest(for: API(bodyValue: .raw(Data("<a/>".utf8), contentType: "application/xml")))
        #expect(request.httpBody == Data("<a/>".utf8))
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/xml")
    }

    @Test("Provider decoder 전략(snake_case)으로 디코딩, Endpoint decoder가 우선")
    func decoderStrategies() async throws {
        let server = MockServer(statusCode: 200, body: #"{ "item_name": "pen" }"#)
        let snake = JSONDecoder()
        snake.keyDecodingStrategy = .convertFromSnakeCase

        let provider = NetworkProvider(environment: env, decoder: snake, session: server.session)
        let item: Item = try await provider.request(API(method: .get))
        #expect(item.itemName == "pen")

        // Endpoint가 기본 decoder로 덮어쓰면 snake_case 변환이 안 되어 실패해야 함
        await #expect(throws: NetworkError.self) {
            try await provider.request(API(method: .get, decoderValue: JSONDecoder()), type: Item.self)
        }
    }

    @Test("Encodable body가 실제 전송까지 도달")
    func encodableSentOverWire() async throws {
        let received = Box<Data?>(nil)
        let server = MockServer { request in
            received.value = request.bodyData
            return (HTTPURLResponse(url: request.url!, statusCode: 204, httpVersion: nil, headerFields: nil)!, nil)
        }
        try await NetworkProvider(environment: env, session: server.session)
            .request(API(bodyValue: .json(["a": 1])))
        #expect(try json(received.value)["a"] as? Int == 1)
    }
}
