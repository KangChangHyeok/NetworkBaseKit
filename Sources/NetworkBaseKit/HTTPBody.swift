//
//  HTTPBody.swift
//  NetworkBaseKit
//

import Foundation

/// 요청 Body. Postman Body 탭의 각 옵션에 대응합니다.
///
/// ```swift
/// var body: HTTPBody? {
///     switch self {
///     case .signUp(let request): .json(request)                  // raw (JSON) - Encodable 모델
///     case .login(let id, let pw): ["id": id, "pw": pw]          // raw (JSON) - 딕셔너리 리터럴
///     case .token(let code): .form(["code": code])                // x-www-form-urlencoded
///     case .upload(let image): .multipart([.file(name: "image", data: image,
///                                                fileName: "a.jpg", mimeType: "image/jpeg")])
///     case .binary(let data): .raw(data, contentType: "application/octet-stream")
///     }
/// }
/// ```
public enum HTTPBody {
    /// Encodable 모델을 JSON으로 인코딩 (Provider 또는 Endpoint의 JSONEncoder 사용)
    case json(any Encodable)
    /// `[String: Any]`, `[Any]` 등 JSONSerialization으로 직렬화할 수 있는 값
    case jsonObject(Any)
    /// application/x-www-form-urlencoded
    case formURLEncoded([URLQueryItem])
    /// multipart/form-data (파일 업로드)
    case multipart(MultipartFormData)
    /// 임의의 데이터와 Content-Type
    case raw(Data, contentType: String)

    /// `[String: String]`으로 form body를 만듭니다. (키 순서는 정렬되어 항상 같은 결과를 냅니다)
    public static func form(_ fields: [String: String]) -> HTTPBody {
        .formURLEncoded(fields.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) })
    }

    /// Part 배열로 multipart body를 만듭니다.
    public static func multipart(_ parts: [MultipartFormData.Part]) -> HTTPBody {
        .multipart(MultipartFormData(parts: parts))
    }
}

/// 기존 `[String: Any]` 방식과의 호환: `var body: HTTPBody? { ["key": value] }`
extension HTTPBody: ExpressibleByDictionaryLiteral {
    public init(dictionaryLiteral elements: (String, Any)...) {
        self = .jsonObject(Dictionary(elements, uniquingKeysWith: { _, last in last }))
    }
}

extension HTTPBody {
    /// Body를 Data와 Content-Type으로 변환합니다.
    func encoded(using encoder: JSONEncoder) throws(NetworkError) -> (data: Data, contentType: String) {
        switch self {
        case .json(let value):
            do {
                return (try encoder.encode(value), "application/json")
            } catch {
                throw .encodingFailed(underlying: error)
            }

        case .jsonObject(let object):
            guard JSONSerialization.isValidJSONObject(object) else {
                throw .encodingFailed(underlying: nil)
            }
            do {
                return (try JSONSerialization.data(withJSONObject: object), "application/json")
            } catch {
                throw .encodingFailed(underlying: error)
            }

        case .formURLEncoded(let items):
            let body = items
                .map { "\(Self.formEncode($0.name))=\(Self.formEncode($0.value ?? ""))" }
                .joined(separator: "&")
            return (Data(body.utf8), "application/x-www-form-urlencoded; charset=utf-8")

        case .multipart(let formData):
            return (formData.encode(), formData.contentType)

        case .raw(let data, let contentType):
            return (data, contentType)
        }
    }

    /// application/x-www-form-urlencoded 규칙: 영숫자와 `-._*`만 그대로, 공백은 `+`
    private static func formEncode(_ string: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._* ")
        return (string.addingPercentEncoding(withAllowedCharacters: allowed) ?? string)
            .replacingOccurrences(of: " ", with: "+")
    }
}

// MARK: - Multipart

/// multipart/form-data body 빌더
public struct MultipartFormData: Sendable {

    public struct Part: Sendable {
        public let name: String
        public let data: Data
        public let fileName: String?
        public let mimeType: String?

        public init(name: String, data: Data, fileName: String? = nil, mimeType: String? = nil) {
            self.name = name
            self.data = data
            self.fileName = fileName
            self.mimeType = mimeType
        }

        /// 텍스트 필드
        public static func text(name: String, value: String) -> Part {
            Part(name: name, data: Data(value.utf8))
        }

        /// 파일 필드
        public static func file(name: String, data: Data, fileName: String, mimeType: String) -> Part {
            Part(name: name, data: data, fileName: fileName, mimeType: mimeType)
        }
    }

    public let boundary: String
    public private(set) var parts: [Part]

    public init(boundary: String = "NetworkBaseKit.\(UUID().uuidString)", parts: [Part] = []) {
        self.boundary = boundary
        self.parts = parts
    }

    public mutating func append(_ part: Part) {
        parts.append(part)
    }

    public var contentType: String { "multipart/form-data; boundary=\(boundary)" }

    public func encode() -> Data {
        var data = Data()
        let lineBreak = "\r\n"
        for part in parts {
            data.append(Data("--\(boundary)\(lineBreak)".utf8))
            var disposition = "Content-Disposition: form-data; name=\"\(Self.escape(part.name))\""
            if let fileName = part.fileName {
                disposition += "; filename=\"\(Self.escape(fileName))\""
            }
            data.append(Data((disposition + lineBreak).utf8))
            if let mimeType = part.mimeType {
                data.append(Data("Content-Type: \(mimeType)\(lineBreak)".utf8))
            }
            data.append(Data(lineBreak.utf8))
            data.append(part.data)
            data.append(Data(lineBreak.utf8))
        }
        data.append(Data("--\(boundary)--\(lineBreak)".utf8))
        return data
    }

    /// 헤더 값 안의 따옴표와 줄바꿈이 헤더를 깨뜨리지 않도록 이스케이프합니다.
    private static func escape(_ value: String) -> String {
        value.replacingOccurrences(of: "\"", with: "%22")
            .replacingOccurrences(of: "\r", with: "%0D")
            .replacingOccurrences(of: "\n", with: "%0A")
    }
}
