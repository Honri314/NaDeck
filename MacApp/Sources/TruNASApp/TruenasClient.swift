import Foundation

// MARK: - 오류

enum TruenasError: LocalizedError {
    case invalidURL
    case http(Int, String)
    case emptyBody
    case network(Error)
    case clientMessage(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return T("주소 형식이 올바르지 않습니다. (예: 192.168.1.100)",
                     "Invalid address format. (e.g. 192.168.1.100)")
        case .emptyBody:
            return T("응답 본문이 비어 있습니다.", "Empty response body.")
        case .network(let underlying):
            return Self.networkMessage(underlying)
        case .clientMessage(let msg):
            return msg
        case .http(let code, let body):
            let base: String
            switch code {
            case 401, 403:
                if body.lowercased().contains("api"),
                   body.lowercased().contains("invalid") || body.lowercased().contains("key") {
                    base = T("API 키가 올바르지 않습니다.\n"
                        + "TrueNAS 웹 UI( Credential -> API Keys )에서 키의 Copy 버튼으로 전체를 복사한 뒤,\n"
                        + "공백/줄바꿈/따옴표 없이 붙여넣었는지 확인하세요.\n"
                        + "키를 지우고 다시 발급해도 좋습니다.",
                        "The API key is invalid.\n"
                        + "Copy the full key via the Copy button in the TrueNAS web UI and paste it without spaces or quotes.\n"
                        + "You can also revoke and re-create the key.")
                } else {
                    base = T("인증 실패 - API 키를 확인하세요.",
                             "Authentication failed - check your API key.")
                }
            case 404:
                base = T("엔드포인트를 찾을 수 없습니다 - TrueNAS 버전을 확인하세요.",
                         "Endpoint not found - check your TrueNAS version.")
            case 400, 422:
                base = T("요청이 거부되었습니다", "The request was rejected")
            case 500...599:
                base = T("서버 오류", "Server error")
            default:
                base = T("연결 오류", "Connection error")
            }
            let detail = body.trimmingCharacters(in: .whitespacesAndNewlines)
            return detail.isEmpty ? base : "\(base)\n(\(detail))"
        }
    }

    /// macOS 시스템 오류(URLError)를 한국어 안내로 변환
    private static func networkMessage(_ underlying: Error) -> String {
        guard let urlError = underlying as? URLError else {
            return underlying.localizedDescription
        }
        switch urlError.code {
        case .cannotFindHost, .dnsLookupFailed:
            return T("서버 주소(호스트)를 찾을 수 없습니다 - 주소 철자와 네트워크 연결을 확인하세요.",
                     "Host not found - check the address spelling and your network.")
        case .cannotConnectToHost:
            return T("서버에 연결할 수 없습니다 - 주소/포트를 확인하고 TrueNAS가 켜져 있는지, 같은 네트워크(또는 테일스케일)에 있는지 확인하세요.",
                     "Could not connect - check address/port and that TrueNAS is powered on and reachable.")
        case .networkConnectionLost, .notConnectedToInternet:
            return T("네트워크에 연결되어 있지 않습니다 - Wi-Fi/이더넷 연결을 확인하세요.",
                     "No network connection - check Wi-Fi/Ethernet.")
        case .timedOut:
            return T("응답 시간이 초과되었습니다 - 주소/포트가 맞는지, 방화벽에서 차단되지 않았는지 확인하세요.",
                     "Timed out - check address/port and firewall rules.")
        case .serverCertificateUntrusted, .serverCertificateHasUnknownRoot,
             .serverCertificateNotYetValid, .serverCertificateHasBadDate:
            return T("TLS 인증서를 신뢰할 수 없습니다 - 설정에서 '자체 서명 인증서 허용'을 켜세요.",
                     "Untrusted TLS certificate - enable the self-signed option in settings.")
        default:
            return T("서버에 연결하지 못했습니다",
                     "Could not connect to the server")
                + " (\(urlError.code.rawValue))"
        }
    }
}

// MARK: - 설정 저장 (다중 프로파일)

struct ProfileStore: Codable {
    var activeName: String = ""
    var profiles: [NasProfile] = []
}

enum ConfigStore {
    private static let key = "truenas.profiles.v1"
    private static let legacyKey = "truenas.config.v1"

    /// 저장된 프로파일 집합을 읽는다. 이전 단일 연결 설정(또는 옛 bundle id 저장소)이
    /// 있으면 "기본 연결" 프로파일로 1회 이식한다.
    static func load() -> ProfileStore {
        let defaults = UserDefaults.standard
        if let data = defaults.data(forKey: key),
           let store = try? JSONDecoder().decode(ProfileStore.self, from: data) {
            return store
        }
        // 마이그레이션 1: NaDeck 이전 bundle id의 단일 설정
        // 마이그레이션 2: 현재 bundle id의 단일 설정
        for source in [(defaults, legacyKey),
                       (UserDefaults(suiteName: "kr.freebuff.truenas-manager"), legacyKey)] {
            guard let d = source.0?.data(forKey: source.1),
                  let c = try? JSONDecoder().decode(TruenasConfig.self, from: d),
                  !(c.baseURL.isEmpty && c.apiKey.isEmpty) else { continue }
            let profile = NasProfile(name: c.name.isEmpty ? "기본 연결" : c.name, from: c)
            var store = ProfileStore(activeName: profile.name, profiles: [profile])
            save(store)
            return store
        }
        return ProfileStore()
    }

    static func save(_ store: ProfileStore) {
        if let data = try? JSONEncoder().encode(store) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    /// 단일 연결 지우기 (설정 화면 '연결 지우기'용)
    static func clearActive(_ store: inout ProfileStore) {
        if let index = store.profiles.firstIndex(where: { $0.name == store.activeName }) {
            store.profiles[index].apiKey = ""
            store.profiles[index].baseURL = ""
        }
    }
}

// MARK: - 클라이언트

enum AuthMode: String {
    case apiKey = "api_key"
    case bearer = "bearer"
    case basic = "basic"
}

final class TruenasClient {
    private let config: TruenasConfig
    private let effectiveBase: String
    private let mode: AuthMode

    init(config: TruenasConfig) {
        self.config = config
        // 포트 지정(선택)이 있으면 주소에 반영 (IP/LAN, 테일스케일 모두 지원)
        self.effectiveBase = TruenasClient.resolveBaseURL(config.baseURL, config.port)
        self.mode = AuthMode(rawValue: config.authMode ?? "") ?? .apiKey
    }

    var baseURL: String { config.baseURL }

    /// 붙여넣은 키의 공백/줄바꿊/따옴표를 제거한다.
    private var cleanKey: String {
        config.apiKey
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
    }

    /// 인증 방식별 헤더
    private var authHeaders: [String: String] {
        var h: [String: String] = [:]
        switch mode {
        case .apiKey:
            h["X-API-Key"] = cleanKey
        case .bearer:
            h["Authorization"] = "Bearer \(cleanKey)"
        case .basic:
            let user = (config.basicUser ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let raw = "\(user):\(cleanKey)"
            if let data = raw.data(using: .utf8) {
                h["Authorization"] = "Basic \(data.base64EncodedString())"
            }
        }
        return h
    }

    /// 지정한 헤더로 1회 요청을 보내고 (HTTP 상태, 응답 요약)을 돌려준다.
    /// 진단에서 인증 방식별 폴백 실험(X-API-Key / Bearer / Basic)에 사용한다.
    func probe(_ path: String, headers: [String: String]) async -> (Int, String) {
        guard var base = url else { return (-1, T("주소를 해석할 수 없습니다.", "Cannot resolve address.")) }
        var req = URLRequest(url: base.appendingPathComponent(path))
        req.httpMethod = "GET"
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        for (key, value) in headers {
            req.setValue(value, forHTTPHeaderField: key)
        }
        do {
            let (data, resp) = try await session.data(for: req)
            let status = (resp as? HTTPURLResponse)?.statusCode ?? -1
            let body = String(data: data, encoding: .utf8) ?? ""
            return (status, String(body.prefix(200)))
        } catch {
            return (-1, error.localizedDescription)
        }
    }

    /// 지정 인증 방식으로 /system/info 1회 호출</br>성공 여부만 필요한 진단용
    func probeAuth(_ mode: AuthMode, username: String?) async -> (Int, String) {
        var h: [String: String] = [:]
        switch mode {
        case .apiKey: h["X-API-Key"] = cleanKey
        case .bearer: h["Authorization"] = "Bearer \(cleanKey)"
        case .basic:
            let user = (username ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let raw = "\(user):\(cleanKey)"
            if let data = raw.data(using: .utf8) {
                h["Authorization"] = "Basic \(data.base64EncodedString())"
            }
        }
        return await probe("/system/info", headers: h)
    }

    /// 오류 응답에서 사람이 읽을 이유(msg)를 뽑아낸다: error / message / reason 순
    private static func reason(from data: Data) -> String? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        for key in ["error", "message", "reason"] {
            if let s = obj[key] as? String { return s }
            if let n = obj[key] as? NSNumber { return n.stringValue }
        }
        return nil
    }

    /// 기본 포트는 https 443 / http 80. 사용자가 별도 포트를 입력하면 호스트 뒤에 붙인다.
    static func resolveBaseURL(_ raw: String, _ port: String?) -> String {
        let base = normalizeBaseURL(raw)
        let trimmed = (port ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return base }
        // 이미 호스트:포트 형태면 무시
        guard let comps = URLComponents(string: base), comps.port == nil else { return base }
        guard let portNumber = Int(trimmed), portNumber > 0, portNumber <= 65535 else { return base }
        var adjusted = comps
        adjusted.port = portNumber
        return adjusted.string ?? base
    }

    /// "192.168.1.20", "nas.local" 등을 표준 URL로 정규화
    static func normalizeBaseURL(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.isEmpty { return s }
        if !s.lowercased().hasPrefix("http://") && !s.lowercased().hasPrefix("https://") {
            s = "https://" + s
        }
        while s.hasSuffix("/") { s.removeLast() }
        if !s.hasSuffix("/api/v2.0") {
            s += "/api/v2.0"
        }
        return s
    }

    private var session: URLSession {
        let conf = URLSessionConfiguration.ephemeral
        conf.timeoutIntervalForRequest = 30
        conf.timeoutIntervalForResource = 60
        if config.allowInsecure {
            return URLSession(configuration: conf, delegate: InsecurePolicy.shared, delegateQueue: nil)
        }
        return URLSession(configuration: conf)
    }

    private var url: URL? {
        URL(string: effectiveBase)
    }

    // MARK: 저수준 요청

    private func perform(_ method: String, path: String, body: Data? = nil, query: [String: String] = [:]) async throws -> Data {
        guard var base = url else { throw TruenasError.invalidURL }
        var comps = URLComponents(url: base, resolvingAgainstBaseURL: false)!
        comps.path = base.path.components(separatedBy: "/api/v2.0").first.map { $0 + "/api/v2.0" } ?? ""
        if comps.path.isEmpty { comps.path = "/api/v2.0" }
        base = comps.url!
        base = base.appendingPathComponent(path)

        if !query.isEmpty {
            var u = URLComponents(url: base, resolvingAgainstBaseURL: false)!
            u.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
            base = u.url!
        }

        var req = URLRequest(url: base)
        req.httpMethod = method
        req.httpBody = body
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        // 인증은 설정된 방식(api_key/bearer/basic)에 따른다.
        for (key, value) in authHeaders {
            req.setValue(value, forHTTPHeaderField: key)
        }

        let data: Data
        let resp: URLResponse
        do {
            (data, resp) = try await session.data(for: req)
        } catch {
            // macOS 시스템 오류 원문(예: Could not connect to the server.)을
            // 한국어 안내로 변환한다 (TruenasError.network)
            throw TruenasError.network(error)
        }
        guard let http = resp as? HTTPURLResponse else { throw TruenasError.emptyBody }
        guard (200..<300).contains(http.statusCode) else {
            let bodyText = String(data: data, encoding: .utf8) ?? ""
            // TrueNAS는 {"error": ...} 또는 {"message": ...}/{"reason": ...} 형태로 응답함
            let detail = TruenasClient.reason(from: data)
                ?? (bodyText.isEmpty ? "알 수 없는 오류" : String(bodyText.prefix(300)))
            // 404는 어떤 경로가 없는지 앱에 그대로 보여준다 (원인 지리농 방지)
            if http.statusCode == 404 {
                throw TruenasError.http(404, "경로 \(path) - 서버 원문: \(detail)")
            }
            throw TruenasError.http(http.statusCode, detail)
        }
        return data
    }

    func get<T: Decodable>(_ path: String, query: [String: String] = [:]) async throws -> T {
        let data = try await perform("GET", path: path, query: query)
        return try JSONDecoder().decode(T.self, from: data)
    }

    /// 사양 기반의 범용 목록/생성/삭제용: JSON을 직접 사전형으로 반환
    func getAny(_ path: String) async throws -> Any {
        let data = try await perform("GET", path: path)
        return try JSONSerialization.jsonObject(with: data)
    }

    func getAnyList(_ path: String) async throws -> [[String: Any]] {
        let obj = try await getAny(path)
        if let array = obj as? [[String: Any]] { return array }
        if let single = obj as? [String: Any] { return [single] }
        return []
    }

    /// body는 [String: Any]뿐 아니라 문자열(예: /app/start 본문=앱 이름)도 허용한다.
    func postAny(_ path: String, _ body: Any?) async throws -> Any {
        let data: Data?
        switch body {
        case .none:
            data = nil
        case let str as String:
            // 베어 문자열은 유효한 JSON 본문이 아니므로 JSON 문자열 \"...\" 로 인코딩한다.
            // (따옴표 없이 보내면 서버가 JSON 파싱에 실패해 500 Internal Server Error 가 나온다)
            data = try JSONEncoder().encode(str)
        case let obj as [Any]:
            data = try JSONSerialization.data(withJSONObject: obj)
        case let obj as [String: Any]:
            data = try JSONSerialization.data(withJSONObject: obj)
        default:
            data = nil
        }
        let resp = try await perform("POST", path: path, body: data)
        let object = try? JSONSerialization.jsonObject(with: resp)
        return object ?? ""
    }

    /// PUT (편집) 지원 — postAny와 동일한 본문 인코딩
    func putAny(_ path: String, _ body: Any?) async throws -> Any {
        let data: Data?
        switch body {
        case .none:
            data = nil
        case let str as String:
            data = try JSONEncoder().encode(str)
        case let obj as [Any]:
            data = try JSONSerialization.data(withJSONObject: obj)
        case let obj as [String: Any]:
            data = try JSONSerialization.data(withJSONObject: obj)
        default:
            data = nil
        }
        let resp = try await perform("PUT", path: path, body: data)
        let object = try? JSONSerialization.jsonObject(with: resp)
        return object ?? ""
    }

    func getArray<T: Decodable>(_ path: String, query: [String: String] = [:]) async throws -> [T] {
        // 엔드포인트에 따라 리스트가 아닌 단일 오브젝트로 응답 가능
        let data = try await perform("GET", path: path, query: query)
        if let array = try? JSONDecoder().decode([T].self, from: data) {
            return array
        }
        if let single = try? JSONDecoder().decode(T.self, from: data) {
            return [single]
        }
        throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "\(path) 응답 디코딩 실패"))
    }

    func post<T: Decodable>(_ path: String, body: [String: Any]) async throws -> T {
        let json = try JSONSerialization.data(withJSONObject: body)
        let data = try await perform("POST", path: path, body: json)
        return try JSONDecoder().decode(T.self, from: data)
    }

    func postVoid(_ path: String, body: [String: Any]) async throws {
        _ = try await perform("POST", path: path, body: try JSONSerialization.data(withJSONObject: body))
    }

    func put<T: Decodable>(_ path: String, body: [String: Any]) async throws -> T {
        let json = try JSONSerialization.data(withJSONObject: body)
        return try JSONDecoder().decode(T.self, from: try await perform("PUT", path: path, body: json))
    }

    func delete(_ path: String) async throws {
        _ = try await perform("DELETE", path: path)
    }
}

// MARK: - 자체 서명 인증서 허용

final class InsecurePolicy: NSObject, URLSessionDelegate {
    static let shared = InsecurePolicy()

    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let trust = challenge.protectionSpace.serverTrust else {
            completionHandler(.performDefaultHandling, nil)
            return
        }
        completionHandler(.useCredential, URLCredential(trust: trust))
    }
}
