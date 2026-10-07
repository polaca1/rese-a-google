import Foundation
import Combine
import Security

struct RemoteUser: Codable { let name: String; let email: String }
struct RemoteSession: Codable { let token: String; let expiresAt: Double; let user: RemoteUser }
enum RemoteAuthError: LocalizedError {
    case invalidURL, notReady, unavailable, keychain, rejected(String)
    var errorDescription: String? {
        switch self {
        case .invalidURL: return "La dirección del servicio de cuentas no es válida."
        case .notReady: return "El servicio de cuentas todavía no está activado. Inténtalo cuando esté disponible."
        case .unavailable: return "No se puede conectar con el servidor. Comprueba tu conexión e inténtalo de nuevo. Tu cuenta no se ha creado en este dispositivo."
        case .keychain: return "No se ha podido guardar la sesión en el llavero."
        case .rejected(let message): return message
        }
    }
}
private final class AuthRedirectPolicy: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}

/// Shared by iPhone and Mac. Server login never falls back to a local password check.
@MainActor final class RemoteAuthClient: ObservableObject {
    static let shared = RemoteAuthClient()
    @Published private(set) var server = ""
    @Published private(set) var session: RemoteSession?
    private let defaults: UserDefaults
    private let service: String
    private let urlSession: URLSession
    private let serverKey = "reviewNfcGo.accountsServer.verified"
    // One address managed by the app owner. End users never enter a server URL.
    private static let directoryURL = URL(string: "https://raw.githubusercontent.com/polaca1/rese-a-google/refs/heads/sidestore/accounts-server.json")!
    private struct Directory: Decodable { let schema: Int; let serverURL: String? }
    private struct StoredSession: Codable { let server: String; let session: RemoteSession }
    private var lastResolution: Date?
    private static func cleanOrigin(_ address: String) throws -> String {
        guard let url = URLComponents(string: address), url.scheme == "https", let host = url.host, !host.isEmpty,
              url.port == nil || url.port == 443, url.user == nil, url.password == nil,
              url.query == nil, url.fragment == nil, url.path.isEmpty || url.path == "/" else {
            throw RemoteAuthError.invalidURL
        }
        return "https://" + host.lowercased()
    }
    var configured: Bool { !server.isEmpty }
    var signedIn: Bool { session.map { $0.expiresAt > Date().timeIntervalSince1970 } ?? false }
    init(defaults: UserDefaults = .standard, credentialService: String? = nil, networkSession: URLSession? = nil) {
        self.defaults = defaults
        service = credentialService ?? (Bundle.main.bundleIdentifier ?? "reviewNfcGo") + ".remote-session"
        urlSession = networkSession ?? URLSession(configuration: .ephemeral, delegate: AuthRedirectPolicy(), delegateQueue: nil)
        server = (try? Self.cleanOrigin(defaults.string(forKey: serverKey) ?? "")) ?? ""
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                   kSecAttrAccount as String: "session", kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var result: CFTypeRef?
        if SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data {
            if let stored = try? JSONDecoder().decode(StoredSession.self, from: data), stored.server == server {
                session = stored.session
            }
        }
    }
    private func resolveServer() async throws {
        if configured, let lastResolution, Date().timeIntervalSince(lastResolution) < 300 { return }
        var lookup = URLRequest(url: Self.directoryURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 12)
        lookup.setValue("application/json", forHTTPHeaderField: "Accept")
        let response: (Data, URLResponse)
        do { response = try await urlSession.data(for: lookup) }
        catch {
            if Task.isCancelled { throw CancellationError() }
            // A previously verified address still points at the owner's PC.
            // This never substitutes a local registration or local password check.
            if configured { return }
            throw RemoteAuthError.unavailable
        }
        guard let http = response.1 as? HTTPURLResponse, http.statusCode == 200, response.0.count <= 4096,
              let directory = try? JSONDecoder().decode(Directory.self, from: response.0), directory.schema == 1 else {
            if configured { return }
            throw RemoteAuthError.notReady
        }
        guard let address = directory.serverURL, !address.isEmpty else { throw RemoteAuthError.notReady }
        let origin = try Self.cleanOrigin(address)
        if origin != server { clearSession(); server = origin; defaults.set(origin, forKey: serverKey) }
        lastResolution = Date()
    }
    func authenticate(email: String, password: String, name: String? = nil) async throws -> RemoteUser {
        try await resolveServer()
        var body = ["email": email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), "password": password]
        if let name { body["name"] = name.trimmingCharacters(in: .whitespacesAndNewlines) }
        let origin = server
        let response: RemoteSession = try await request(name == nil ? "login" : "register", method: "POST", body: body, authorized: false)
        guard server == origin else { throw CancellationError() }
        try saveSession(response); return response.user
    }
    func validate() async throws -> RemoteUser {
        try await resolveServer()
        guard signedIn else { clearSession(); throw RemoteAuthError.rejected("La sesión ha caducado. Vuelve a entrar.") }
        if session!.expiresAt - Date().timeIntervalSince1970 < 12 * 3600 {
            let response: RemoteSession = try await request("refresh", method: "POST", authorized: true)
            try saveSession(response); return response.user
        }
        return try await request("me", method: "GET", authorized: true)
    }
    func logout() {
        let old = session
        let address = server
        clearSession()
        guard let old, let base = URL(string: address) else { return }
        var revoke = URLRequest(url: base.appendingPathComponent("v1/auth/logout"), timeoutInterval: 15)
        revoke.httpMethod = "POST"
        revoke.setValue("Bearer " + old.token, forHTTPHeaderField: "Authorization")
        Task { _ = try? await urlSession.data(for: revoke) }
    }
    private struct EmptyResponse: Decodable {}
    private func request<Response: Decodable>(_ path: String, method: String, body: [String: String]? = nil, authorized: Bool) async throws -> Response {
        guard let base = URL(string: server), base.scheme == "https" else { throw RemoteAuthError.invalidURL }
        var request = URLRequest(url: base.appendingPathComponent("v1/auth").appendingPathComponent(path), timeoutInterval: 15)
        request.httpMethod = method; request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let body { request.httpBody = try JSONEncoder().encode(body) }
        if authorized { guard let session else { throw RemoteAuthError.rejected("Vuelve a iniciar sesión.") }; request.setValue("Bearer " + session.token, forHTTPHeaderField: "Authorization") }
        let origin = server
        let sentToken = authorized ? session?.token : nil
        let response: (Data, URLResponse)
        do { response = try await urlSession.data(for: request) }
        catch { if Task.isCancelled { throw CancellationError() }; throw RemoteAuthError.unavailable }
        guard server == origin, !authorized || session?.token == sentToken else { throw CancellationError() }
        guard let http = response.1 as? HTTPURLResponse, response.0.count <= 64_000 else { throw RemoteAuthError.unavailable }
        guard (200...299).contains(http.statusCode) else {
            if authorized && http.statusCode == 401 { clearSession() }
            let json = try? JSONSerialization.jsonObject(with: response.0) as? [String: Any]
            throw RemoteAuthError.rejected(json?["detail"] as? String ?? "El servidor no ha aceptado la solicitud. Revisa tus datos.")
        }
        return try JSONDecoder().decode(Response.self, from: http.statusCode == 204 ? Data("{}".utf8) : response.0)
    }
    private func saveSession(_ value: RemoteSession) throws {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: "session"]
        let data = try JSONEncoder().encode(StoredSession(server: server, session: value))
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var create = query; create[kSecValueData as String] = data
            create[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            guard SecItemAdd(create as CFDictionary, nil) == errSecSuccess else { throw RemoteAuthError.keychain }
        } else if status != errSecSuccess { throw RemoteAuthError.keychain }
        session = value
    }
    func clearSession() {
        SecItemDelete([kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: "session"] as CFDictionary)
        session = nil
    }
}
