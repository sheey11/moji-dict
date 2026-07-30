import Foundation

enum MojiAPIError: LocalizedError, Sendable {
    case invalidURL
    case invalidResponse
    case httpStatus(Int)
    case rateLimited
    case missingWord
    case authenticationFailed(String?)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            "无法构造查询地址。"
        case .invalidResponse:
            "服务器返回了无法识别的响应。"
        case let .httpStatus(code):
            "服务器返回 HTTP \(code)。"
        case .rateLimited:
            "请求过于频繁，请稍后再试。"
        case .missingWord:
            "没有找到该词条的详情。"
        case let .authenticationFailed(message):
            message ?? "登录失败，请检查邮箱和密码。"
        }
    }
}

actor MojiAPIClient {
    static let shared = MojiAPIClient()

    private struct CachedSearch: Sendable {
        let savedAt: Date
        let response: SearchResponse
    }

    private let session: URLSession
    private let decoder = JSONDecoder()
    private var deviceID: String
    private var searchCache: [String: CachedSearch] = [:]
    private var detailCache: [String: WordDetailResponse] = [:]
    private var relatedCache: [String: WordRelatedGroup] = [:]
    private var sessionToken: String?

    init(session: URLSession? = nil, deviceID: String = UUID().uuidString.lowercased()) {
        self.deviceID = deviceID
        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = 10
            configuration.timeoutIntervalForResource = 15
            configuration.waitsForConnectivity = true
            configuration.requestCachePolicy = .reloadRevalidatingCacheData
            configuration.httpAdditionalHeaders = [
                "Accept": "application/json",
                "User-Agent": "MojiQuickLook/0.1 (macOS; personal read-only client)"
            ]
            self.session = URLSession(configuration: configuration)
        }
    }

    func login(email: String, password: String) async throws -> LoginResponse {
        let request = try Self.loginRequest(
            email: email,
            password: password,
            deviceID: deviceID
        )
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else {
            throw MojiAPIError.invalidResponse
        }
        guard (200..<300).contains(response.statusCode) else {
            throw MojiAPIError.authenticationFailed(Self.errorMessage(from: data))
        }

        do {
            let result = try decoder.decode(LoginResponse.self, from: data)
            sessionToken = result.sessionToken
            detailCache.removeAll()
            relatedCache.removeAll()
            return result
        } catch {
            if let message = Self.errorMessage(from: data) {
                throw MojiAPIError.authenticationFailed(message)
            }
            throw MojiAPIError.invalidResponse
        }
    }

    func logout() {
        sessionToken = nil
        detailCache.removeAll()
        relatedCache.removeAll()
    }

    func restoreSession(token: String, deviceID: String) {
        let normalizedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedDeviceID = deviceID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedToken.isEmpty, !normalizedDeviceID.isEmpty else { return }
        sessionToken = normalizedToken
        self.deviceID = normalizedDeviceID
        detailCache.removeAll()
        relatedCache.removeAll()
    }

    func deviceIdentifier() -> String {
        deviceID
    }

    func search(_ text: String) async throws -> SearchResponse {
        let key = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let cached = searchCache[key], Date().timeIntervalSince(cached.savedAt) < 900 {
            return cached.response
        }

        let url = try Self.searchURL(for: key)
        let data = try await data(from: url)
        let response = try decoder.decode(SearchResponse.self, from: data)
        searchCache[key] = CachedSearch(savedAt: Date(), response: response)
        return response
    }

    func wordDetail(id: String, forceRefresh: Bool = false) async throws -> WordDetailResponse {
        if !forceRefresh, let cached = detailCache[id] {
            return cached
        }

        let url = try Self.wordDetailURL(id: id)
        let data = try await data(from: url)
        let response = try decoder.decode(WordDetailResponse.self, from: data)
        guard response.word != nil else {
            throw MojiAPIError.missingWord
        }
        detailCache[id] = response
        return response
    }

    func wordRelated(id: String, forceRefresh: Bool = false) async throws -> WordRelatedGroup? {
        if !forceRefresh, let cached = relatedCache[id] {
            return cached
        }

        var request = try Self.wordRelatedRequest(id: id, deviceID: deviceID)
        if let sessionToken {
            request.setValue(sessionToken, forHTTPHeaderField: "X-MOJI-TOKEN")
            request.setValue(sessionToken, forHTTPHeaderField: "X-MOJI-SESSION-ID")
        }

        let data = try await data(for: request)
        let response = try decoder.decode(WordRelatedResponse.self, from: data)
        if let related = response.first {
            relatedCache[id] = related
        }
        return response.first
    }

    func clearMemoryCache() {
        searchCache.removeAll()
        detailCache.removeAll()
        relatedCache.removeAll()
    }

    static func searchURL(for text: String) throws -> URL {
        guard var components = URLComponents(
            string: "https://api.mojidict.com/app/mojidict/api/v2/search/all"
        ) else {
            throw MojiAPIError.invalidURL
        }
        components.queryItems = [
            URLQueryItem(name: "text", value: text),
            URLQueryItem(name: "types", value: "102"),
            URLQueryItem(name: "types", value: "106"),
            URLQueryItem(name: "types", value: "103"),
            URLQueryItem(name: "types", value: "671"),
            URLQueryItem(name: "highlight", value: "true")
        ]
        guard let url = components.url else {
            throw MojiAPIError.invalidURL
        }
        return url
    }

    static func wordDetailURL(id: String) throws -> URL {
        guard var components = URLComponents(
            string: "https://api.mojidict.com/app/mojidict/api/v1/word/detailInfo"
        ) else {
            throw MojiAPIError.invalidURL
        }
        components.queryItems = [URLQueryItem(name: "wordId", value: id)]
        guard let url = components.url else {
            throw MojiAPIError.invalidURL
        }
        return url
    }

    static func loginRequest(
        email: String,
        password: String,
        deviceID: String
    ) throws -> URLRequest {
        guard let url = URL(
            string: "https://api.mojidict.com/app/mojidict/api/v1/account/unifiedLogin"
        ) else {
            throw MojiAPIError.invalidURL
        }

        struct LoginPayload: Encodable {
            struct Authentication: Encodable {
                let email: String
                // MOJi's PasswordAuth protocol names the password field "code".
                let code: String
            }

            let authPayload: Authentication
            let authName: String
        }

        let payload = LoginPayload(
            authPayload: .init(
                email: email.trimmingCharacters(in: .whitespacesAndNewlines),
                code: password
            ),
            authName: "PasswordAuth"
        )

        var request = URLRequest(
            url: url,
            cachePolicy: .reloadIgnoringLocalAndRemoteCacheData,
            timeoutInterval: 15
        )
        request.httpMethod = "POST"
        request.httpBody = try JSONEncoder().encode(payload)
        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        applyWebHeaders(to: &request, deviceID: deviceID)
        return request
    }

    static func wordRelatedRequest(id: String, deviceID: String) throws -> URLRequest {
        guard let url = URL(
            string: "https://api.mojidict.com/app/mojidict/api/v1/word/related"
        ) else {
            throw MojiAPIError.invalidURL
        }

        var request = URLRequest(
            url: url,
            cachePolicy: .reloadRevalidatingCacheData,
            timeoutInterval: 10
        )
        request.httpMethod = "POST"
        request.httpBody = try JSONEncoder().encode(["wordIds": [id]])
        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        applyWebHeaders(to: &request, deviceID: deviceID)
        return request
    }

    private func data(from url: URL) async throws -> Data {
        var request = URLRequest(
            url: url,
            cachePolicy: .reloadRevalidatingCacheData,
            timeoutInterval: 10
        )
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        Self.applyWebHeaders(to: &request, deviceID: deviceID)
        if let sessionToken {
            request.setValue(sessionToken, forHTTPHeaderField: "X-MOJI-TOKEN")
            request.setValue(sessionToken, forHTTPHeaderField: "X-MOJI-SESSION-ID")
        }

        return try await data(for: request)
    }

    private func data(for request: URLRequest) async throws -> Data {
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else {
            throw MojiAPIError.invalidResponse
        }
        if response.statusCode == 429 {
            throw MojiAPIError.rateLimited
        }
        guard (200..<300).contains(response.statusCode) else {
            throw MojiAPIError.httpStatus(response.statusCode)
        }
        return data
    }

    private static func applyWebHeaders(to request: inout URLRequest, deviceID: String) {
        request.setValue("PCWeb", forHTTPHeaderField: "X-MOJI-OS")
        request.setValue("4.16.9", forHTTPHeaderField: "X-MOJI-APP-VERSION")
        request.setValue("com.mojitec.mojidict", forHTTPHeaderField: "X-MOJI-APP-ID")
        request.setValue(deviceID, forHTTPHeaderField: "X-MOJI-DEVICE-ID")
    }

    private static func errorMessage(from data: Data) -> String? {
        guard
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return nil
        }
        return object["message"] as? String
    }
}
