# NetworkBaseKit

Postman / Apidog을 쓰던 감각 그대로 API를 코드로 정의하는 Swift 네트워킹 라이브러리입니다.

| Postman | NetworkBaseKit |
|---|---|
| Request 탭 (Method, URL, Params, Headers, Body) | `Endpoint` |
| Environment (`{{baseURL}}`, 공통 변수) | `NetworkEnvironment` |
| Collection Auth / Pre-request Script | `RequestInterceptor`, `AuthInterceptor` |
| Body 탭 (raw JSON, form-data, x-www-form-urlencoded, binary) | `HTTPBody` |
| 응답 패널 (Status, Headers, Time) | `NetworkResponse` |
| Console | `NetworkLogger` (cURL 출력 포함) |

- Swift 6 / async-await / typed throws (`throws(NetworkError)`)
- 외부 의존성 없음
- iOS 14+, macOS 11+, watchOS 7+

---

## 설치 (Swift Package Manager)

```swift
dependencies: [
    .package(url: "https://github.com/KangChangHyeok/NetworkBaseKit", from: "2.0.0")
]
```

```swift
import NetworkBaseKit
```

---

## 빠른 시작

### 1. 환경 정의 (Postman Environment)

```swift
extension NetworkEnvironment {
    static let dev  = NetworkEnvironment(baseURL: "https://dev.api.com/v1")
    static let prod = NetworkEnvironment(
        baseURL: "https://api.com/v1",
        headers: ["X-App-Version": "1.0.0"],   // 모든 요청에 붙는 공통 헤더
        timeout: 15
    )
}
```

### 2. API 정의 (Postman Request)

```swift
enum UserAPI: Endpoint {
    case me
    case user(id: Int)
    case search(keyword: String, page: Int)
    case signUp(SignUpRequest)
    case delete(id: Int)

    var path: String {
        switch self {
        case .me:               "/users/me"
        case .user(let id):     "/users/\(id)"
        case .search:           "/users/search"
        case .signUp:           "/users"
        case .delete(let id):   "/users/\(id)"
        }
    }

    var method: HTTPMethod {
        switch self {
        case .me, .user, .search: .get
        case .signUp:             .post
        case .delete:             .delete
        }
    }

    var queryItems: [URLQueryItem]? {
        guard case .search(let keyword, let page) = self else { return nil }
        return [URLQueryItem(name: "q", value: keyword),
                URLQueryItem(name: "page", value: "\(page)")]
    }

    var body: HTTPBody? {
        guard case .signUp(let request) = self else { return nil }
        return .json(request)
    }
}
```

`path`, `method`만 필수이고 나머지는 모두 기본값이 있습니다.

| 프로퍼티 | 기본값 | 설명 |
|---|---|---|
| `baseURL` | `nil` | 지정하면 환경의 baseURL 대신 사용 |
| `path` | 필수 | 앞의 `/`는 있어도 없어도 됨 |
| `method` | 필수 | `.get .post .put .patch .delete .head .options` |
| `headers` | `nil` | 환경 공통 헤더 위에 **병합** (같은 키면 Endpoint가 우선) |
| `queryItems` | `nil` | |
| `body` | `nil` | [HTTPBody](#body-postman-body-탭) 참고 |
| `requiresAuthorization` | `true` | `false`면 AuthInterceptor가 토큰을 붙이지 않음 |
| `encoder` / `decoder` | `nil` | 이 Endpoint만 다른 JSON 전략이 필요할 때 |

### 3. 요청

```swift
let provider = NetworkProvider(environment: .prod)

// 반환 타입으로 추론
let me: User = try await provider.request(UserAPI.me)

// 타입을 명시
let users = try await provider.request(UserAPI.search(keyword: "kim", page: 1), type: [User].self)

// 응답 body가 필요 없는 요청 (204 No Content 등)
try await provider.request(UserAPI.delete(id: 3))

// 상태 코드, 헤더, 소요 시간까지 필요할 때
let response = try await provider.response(UserAPI.me, type: User.self)
response.value              // User
response.statusCode         // 200
response.header("Link")     // 대소문자 무시
response.duration           // 초
```

#### 싱글톤으로 쓰기

```swift
// 앱 시작 시 한 번 설정
NetworkProvider.shared = NetworkProvider(environment: .prod, interceptors: [auth])

// 어디서든
let me: User = try await NetworkProvider.request(UserAPI.me)
```

---

## Body (Postman Body 탭)

```swift
var body: HTTPBody? {
    switch self {
    // raw (JSON) - Encodable 모델. Provider의 JSONEncoder 전략을 따름
    case .signUp(let request):
        .json(request)

    // raw (JSON) - 딕셔너리 리터럴
    case .login(let id, let pw):
        ["id": id, "password": pw]

    // raw (JSON) - 최상위 배열 등 임의의 JSON 객체
    case .bulk(let ids):
        .jsonObject(ids)

    // x-www-form-urlencoded
    case .token(let code):
        .form(["grant_type": "authorization_code", "code": code])

    // form-data (파일 업로드)
    case .upload(let image):
        .multipart([
            .text(name: "title", value: "프로필"),
            .file(name: "image", data: image, fileName: "profile.jpg", mimeType: "image/jpeg"),
        ])

    // binary / 그 외
    case .raw(let data):
        .raw(data, contentType: "application/octet-stream")
    }
}
```

`Content-Type`은 body 종류에 맞게 자동으로 설정됩니다. `headers`에 `Content-Type`을 직접 지정하면 그 값이 우선합니다.

---

## Encoder / Decoder 설정

```swift
let decoder = JSONDecoder()
decoder.keyDecodingStrategy = .convertFromSnakeCase
decoder.dateDecodingStrategy = .iso8601

let encoder = JSONEncoder()
encoder.keyEncodingStrategy = .convertToSnakeCase

let provider = NetworkProvider(environment: .prod, decoder: decoder, encoder: encoder)
```

특정 API만 다른 전략을 써야 하면 Endpoint에서 덮어씁니다.

```swift
var decoder: JSONDecoder? {
    if case .legacy = self { return JSONDecoder() }
    return nil
}
```

---

## 에러 처리

모든 API는 `throws(NetworkError)`이므로 `catch`에서 받는 에러가 바로 `NetworkError`입니다.

```swift
do {
    let me: User = try await provider.request(UserAPI.me)
} catch {
    switch error {
    case .clientError(let response):            // 4xx
        // 서버가 내려준 에러 body를 그대로 디코딩
        let message = response.decode(ServerError.self)?.message
    case .serverError(let response):            // 5xx
        print(response.statusCode, response.bodyString ?? "")
    case .transport(let urlError):              // 오프라인, 타임아웃, DNS 등
        print(urlError.code)
    case .decodingFailed(let underlying, let data):
        print(error.localizedDescription)       // "키 'name'가 없습니다. 위치: user" 처럼 위치까지 표시
    case .cancelled:
        break
    default:
        print(error.localizedDescription)
    }
}
```

| case | 발생 시점 |
|---|---|
| `invalidURL` | baseURL이 없거나 URL 생성 실패 |
| `encodingFailed(underlying:)` | body 인코딩 실패 (요청은 전송되지 않음) |
| `interceptorFailed(underlying:)` | Interceptor의 `adapt`가 에러를 던짐 |
| `transport(URLError)` | 네트워크 연결 문제 |
| `cancelled` | Task 취소 |
| `noResponse` | HTTP 응답이 아님 |
| `clientError(HTTPErrorResponse)` | 4xx |
| `serverError(HTTPErrorResponse)` | 5xx |
| `unexpectedStatus(HTTPErrorResponse)` | 1xx, 3xx 등 |
| `decodingFailed(underlying:data:)` | 응답 디코딩 실패 |

편의 프로퍼티: `statusCode`, `response`, `isUnauthorized`, `isForbidden`, `isNotFound`, `isConnectivityError`, `isCancelled`

---

## Interceptor (Collection Auth / Pre-request Script)

### 토큰 주입 + 401 자동 갱신

```swift
let auth = AuthInterceptor(
    tokenProvider: { await TokenStore.shared.accessToken },
    refreshToken:  { try await TokenStore.shared.refresh() }
)

let provider = NetworkProvider(environment: .prod, interceptors: [auth])
```

- 모든 요청에 `Authorization: Bearer <token>`을 붙입니다. (`headerName`, `tokenPrefix`로 변경 가능)
- 401을 받으면 토큰을 갱신하고 **새 토큰으로 한 번 재시도**합니다.
- 여러 요청이 동시에 401을 받아도 **갱신은 한 번만** 실행됩니다.
- 로그인, 토큰 갱신 API처럼 토큰이 필요 없는 Endpoint는 `requiresAuthorization`을 `false`로 두세요.

```swift
var requiresAuthorization: Bool {
    switch self {
    case .login, .refreshToken: false
    default: true
    }
}
```

### 일시적 오류 재시도

```swift
let provider = NetworkProvider(
    environment: .prod,
    interceptors: [auth, RetryPolicy(maxRetries: 2, baseDelay: 0.5)]
)
```

- 연결 오류, 408, 429, 500, 502, 503, 504에 대해 지수 백오프(0.5s → 1s …)로 재시도합니다.
- 서버가 `Retry-After` 헤더를 주면 그 시간만큼 기다립니다.
- 기본적으로 멱등 메서드(GET, HEAD, PUT, DELETE, OPTIONS)만 재시도해서 **POST가 중복 실행되지 않습니다.**

### 직접 만들기

```swift
struct DeviceHeaderInterceptor: RequestInterceptor {
    // 전송 직전에 요청 수정 (재시도할 때마다 다시 호출됨)
    func adapt(_ request: URLRequest, for endpoint: any Endpoint) async throws -> URLRequest {
        var request = request
        request.setValue(UIDevice.current.identifierForVendor?.uuidString,
                         forHTTPHeaderField: "X-Device-ID")
        return request
    }

    // 실패 시 재시도 여부 결정 (필요 없으면 구현하지 않아도 됨)
    func retry(_ request: URLRequest, for endpoint: any Endpoint,
               dueTo error: NetworkError, attemptCount: Int) async -> RetryDecision {
        .doNotRetry   // .retry, .retryAfter(초)
    }
}
```

- `adapt`는 배열 순서대로 적용되고, `retry`는 처음으로 재시도를 결정한 Interceptor를 따릅니다.
- 무한 재시도를 막기 위해 Provider의 `maxRetryCount`(기본 3)가 상한으로 적용됩니다.

---

## 로깅 (Postman Console)

기본값은 **DEBUG 빌드에서 `verbose`, 릴리즈 빌드에서 `off`**이며 OSLog로 출력됩니다.

```
────────────────────────────────────────
📤 [3F2A1C] POST https://api.com/v1/login
├─ Headers:
│     Authorization: Bearer…mnop
│     Content-Type: application/json
├─ Body:
│     {
│       "id" : "kim",
│       "password" : "****"
│     }
├─ cURL:
│     curl -X POST \
│       'https://api.com/v1/login' \
│       -H 'Authorization: Bearer…mnop' \
│       -H 'Content-Type: application/json' \
│       --data-raw '{"id":"kim","password":"****"}'
────────────────────────────────────────
📥 [3F2A1C] ✅ 200 no error POST https://api.com/v1/login (132ms, 48B)
```

```swift
var logger = NetworkLogger(level: .basic)
logger.redactedHeaders.insert("X-Session")
logger.redactedBodyKeys.insert("ssn")
logger.maxBodyLength = 500
logger.includesCURL = false

let provider = NetworkProvider(environment: .prod, logger: logger)
```

| 레벨 | 출력 내용 |
|---|---|
| `.off` | 없음 |
| `.error` | 실패한 요청만 (에러 응답 body 포함) |
| `.basic` | 요청/응답 한 줄 요약 (메서드, URL, 상태 코드, 소요 시간, 크기) |
| `.verbose` | 헤더, body, cURL까지 전부 |

- 같은 요청의 요청/응답/에러 로그에는 같은 ID(`[3F2A1C]`)가 붙고, 재시도는 `(retry #1)`로 표시됩니다.
- `Authorization`, `Cookie`, `X-API-Key` 등의 헤더와 `password`, `token`, `accessToken` 등의 JSON 키(중첩 포함)는 자동으로 마스킹됩니다.
- `privacy: .private`로 두면 OSLog에 private으로 기록됩니다.
- `output` 클로저를 지정하면 OSLog 대신 원하는 곳으로 보낼 수 있습니다.

```swift
let logger = NetworkLogger(level: .error, output: { message, isError in
    Crashlytics.log(message)
})
```

---

## 테스트

`URLSession`을 주입할 수 있어서 `URLProtocol` 기반 Mock으로 테스트할 수 있습니다.

```swift
let config = URLSessionConfiguration.ephemeral
config.protocolClasses = [MockURLProtocol.self]
let provider = NetworkProvider(environment: .dev, session: URLSession(configuration: config))
```

실제로 전송될 요청을 확인하려면 `urlRequest(for:)`를 사용하세요. (Interceptor 적용 전)

```swift
let request = try provider.urlRequest(for: UserAPI.me)
print(request.url!)   // https://dev.api.com/v1/users/me
```

---

## 1.x → 2.0 마이그레이션

| 1.x | 2.0 |
|---|---|
| `var scheme` / `var host` | 삭제. `NetworkEnvironment(baseURL:)` 또는 Endpoint의 `baseURL` 사용 |
| `var body: [String: Any]?` | `var body: HTTPBody?` (딕셔너리 리터럴은 그대로 사용 가능) |
| `headers` 기본값 `["Content-Type": "application/json"]` | 기본값 `nil`. Content-Type은 body에 맞춰 자동 설정, 환경 헤더와 병합 |
| `NetworkError.notFound` 등 상태 코드별 case | `.clientError` / `.serverError` / `.unexpectedStatus` + `statusCode`, `isNotFound` 등 |
| `NetworkError.decodingError` | `.decodingFailed(underlying:data:)` |
| `NetworkError: Equatable` | 제거 (원본 에러를 담기 위함) |
| `URLError`가 그대로 throw됨 | `.transport(URLError)` / `.cancelled`로 감싸짐 |
| `actor NetworkProvider` | `final class NetworkProvider: Sendable` (호출 코드는 동일) |
| `NetworkLogger.log(...)` static 메서드 | `NetworkLogger` 설정값을 Provider에 주입 |

```swift
// 1.x
enum API: Endpoint {
    var host: String { "api.com" }
    var path: String { "/users" }
    var method: HTTPMethod { .get }
}
let users = try await NetworkProvider.request(API.users, type: [User].self)

// 2.0
NetworkProvider.shared = NetworkProvider(environment: NetworkEnvironment(baseURL: "https://api.com"))

enum API: Endpoint {
    var path: String { "/users" }
    var method: HTTPMethod { .get }
}
let users: [User] = try await NetworkProvider.request(API.users)
```
