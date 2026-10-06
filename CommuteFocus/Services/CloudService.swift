import Foundation
import Security
import Combine

struct CloudConfiguration {
    let url: URL
    let publicKey: String
    static var current: CloudConfiguration? {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_URL") as? String,
              let url = URL(string: raw), url.scheme == "https", let host = url.host,
              !host.contains("example"), !raw.contains("$("), !raw.contains("YOUR_"),
              let key = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_ANON_KEY") as? String,
              !key.isEmpty, !key.contains("$("), !key.contains("YOUR_") else { return nil }
        return CloudConfiguration(url: url, publicKey: key)
    }
}

struct AuthUser: Codable { var id: UUID; var email: String? }
struct AuthSession: Codable {
    var access_token: String
    var refresh_token: String
    var expires_in: Int
    var user: AuthUser
    var expires_at: Double?
    var expiry: Date { Date(timeIntervalSince1970: expires_at ?? 0) }
}

enum CloudError: LocalizedError {
    case configuration, message(String), expired
    var errorDescription: String? {
        switch self {
        case .configuration: return "尚未配置云服务；本机任务和计时仍可使用。"
        case .message(let message): return message
        case .expired: return "登录已过期，请重新登录；本机数据仍保留。"
        }
    }
}

enum SecureSession {
    static let service = "app.commutefocus.session"
    static func save(_ session: AuthSession?) throws {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: service,
                                    kSecAttrAccount as String: "current"]
        guard let session else {
            let status = SecItemDelete(query as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else {
                throw CloudError.message("无法清除登录状态，请稍后重试。")
            }
            return
        }
        let data = try JSONEncoder().encode(session)
        let attributes: [String: Any] = [kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var insertion = query
            attributes.forEach { insertion[$0.key] = $0.value }
            guard SecItemAdd(insertion as CFDictionary, nil) == errSecSuccess else {
                throw CloudError.message("无法安全保存登录状态")
            }
        } else if status != errSecSuccess { throw CloudError.message("无法更新登录状态") }
    }
    static func load() -> AuthSession? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service, kSecAttrAccount as String: "current",
            kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return try? JSONDecoder().decode(AuthSession.self, from: data)
    }
}

actor CloudAPI {
    static let shared = CloudAPI()
    func request(path: String, method: String = "POST", body: Data? = nil,
                 token: String? = nil) async throws -> Data {
        guard let config = CloudConfiguration.current else { throw CloudError.configuration }
        guard let url = URL(string: config.url.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + path) else {
            throw CloudError.configuration
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 25
        request.httpBody = body
        request.setValue(config.publicKey, forHTTPHeaderField: "apikey")
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw CloudError.message("云服务响应无效") }
        guard (200...299).contains(response.statusCode) else {
            if response.statusCode == 401 { throw CloudError.expired }
            let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            let detail = json?["msg"] as? String ?? json?["message"] as? String ?? json?["error_description"] as? String
            throw CloudError.message(detail ?? "云服务暂不可用（\(response.statusCode)）")
        }
        return data
    }
}

@MainActor
final class AuthService: ObservableObject {
    @Published private(set) var session: AuthSession? = SecureSession.load()
    private var refreshTask: Task<AuthSession, Error>?
    var owner: String { session?.user.id.uuidString.lowercased() ?? "local" }
    var email: String { session?.user.email ?? "本机模式" }

    func token() async throws -> String {
        guard let session else { throw CloudError.expired }
        if session.expiry > Date().addingTimeInterval(90) { return session.access_token }
        if let refreshTask { return try await refreshTask.value.access_token }
        let expectedOwner = owner
        let task = Task<AuthSession, Error> {
            let body = try JSONEncoder().encode(["refresh_token": session.refresh_token])
            let data = try await CloudAPI.shared.request(path: "/auth/v1/token?grant_type=refresh_token", body: body)
            return try Self.decodeSession(data)
        }
        refreshTask = task
        defer { refreshTask = nil }
        let refreshed = try await task.value
        guard owner == expectedOwner else { throw CloudError.expired }
        try install(refreshed)
        return refreshed.access_token
    }

    static func decodeSession(_ data: Data) throws -> AuthSession {
        var session = try JSONDecoder().decode(AuthSession.self, from: data)
        if session.expires_at == nil { session.expires_at = Date().timeIntervalSince1970 + Double(session.expires_in) }
        return session
    }
    func install(_ newSession: AuthSession) throws {
        try SecureSession.save(newSession)
        session = newSession
    }
    func login(email: String, password: String) async throws {
        let body = try JSONEncoder().encode(["email": email, "password": password])
        let data = try await CloudAPI.shared.request(path: "/auth/v1/token?grant_type=password", body: body)
        try install(Self.decodeSession(data))
    }
    func signup(email: String, password: String) async throws -> Bool {
        let data = try await CloudAPI.shared.request(path: "/auth/v1/signup",
            body: JSONEncoder().encode(["email": email, "password": password]))
        if let session = try? Self.decodeSession(data) { try install(session); return true }
        return false
    }
    func sendRecovery(email: String) async throws {
        _ = try await CloudAPI.shared.request(path: "/auth/v1/recover", body: JSONEncoder().encode(["email": email]))
    }
    func verify(email: String, code: String, type: String) async throws {
        let data = try await CloudAPI.shared.request(path: "/auth/v1/verify",
            body: JSONEncoder().encode(["email": email, "token": code, "type": type]))
        try install(Self.decodeSession(data))
    }
    func updatePassword(_ password: String) async throws {
        let access = try await token()
        _ = try await CloudAPI.shared.request(path: "/auth/v1/user", method: "PUT",
            body: JSONEncoder().encode(["password": password]), token: access)
    }
    func signOut() throws {
        try SecureSession.save(nil)
        let oldToken = session?.access_token
        refreshTask?.cancel()
        refreshTask = nil
        session = nil
        if let oldToken {
            Task { _ = try? await CloudAPI.shared.request(path: "/auth/v1/logout?scope=local", token: oldToken) }
        }
    }
}
