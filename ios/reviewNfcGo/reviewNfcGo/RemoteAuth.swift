import Foundation
import Combine
import Security

struct RemoteUser: Codable { let name: String; let email: String }
struct RemoteSession: Codable {
    let token: String; let expiresAt: Double; let user: RemoteUser
    var refreshToken: String? = nil
}
enum RemoteAuthError: LocalizedError {
    case invalidURL, notReady, unavailable, keychain, rejected(String)
    var errorDescription: String? {
        switch self {
        case .invalidURL: return "La dirección del servicio de cuentas no es válida."
        case .notReady: return "El servicio de cuentas todavía no está activado. Inténtalo cuando esté disponible."
        case .unavailable: return "No se puede conectar con el servidor. Comprueba tu conexión e inténtalo de nuevo."
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
    private let configurationKey = "reviewNfcGo.accountsConfiguration.verified"
    private enum Provider: String { case selfHosted, supabase }
    private var provider: Provider = .selfHosted
    private var publishableKey = ""
    // One address managed by the app owner. End users never enter a server URL.
    private static let directoryURL = URL(string: "https://raw.githubusercontent.com/polaca1/rese-a-google/refs/heads/sidestore/accounts-server.json")!
    private struct Directory: Codable {
        let schema: Int; let serverURL: String?
        var provider: String? = nil
        var publishableKey: String? = nil
    }
    private struct StoredSession: Codable { let server: String; let session: RemoteSession; var provider: String? = nil }
    private var lastResolution: Date?
    private var authorizationGeneration = UUID()
    private var googleAttempt: UUID?
    private var googleBrowser: NativeGoogleBrowser?
    private static func cleanOrigin(_ address: String) throws -> String {
        guard let url = URLComponents(string: address), url.scheme == "https", let host = url.host, !host.isEmpty,
              url.port == nil || url.port == 443, url.user == nil, url.password == nil,
              url.query == nil, url.fragment == nil, url.path.isEmpty || url.path == "/" else {
            throw RemoteAuthError.invalidURL
        }
        return "https://" + host.lowercased()
    }
    var configured: Bool { !server.isEmpty }
    var signedIn: Bool {
        session.map { $0.expiresAt > Date().timeIntervalSince1970 || (provider == .supabase && $0.refreshToken?.isEmpty == false) } ?? false
    }
    init(defaults: UserDefaults = .standard, credentialService: String? = nil, networkSession: URLSession? = nil) {
        self.defaults = defaults
        service = credentialService ?? (Bundle.main.bundleIdentifier ?? "reviewNfcGo") + ".remote-session"
        urlSession = networkSession ?? URLSession(configuration: .ephemeral, delegate: AuthRedirectPolicy(), delegateQueue: nil)
        server = (try? Self.cleanOrigin(defaults.string(forKey: serverKey) ?? "")) ?? ""
        if let data = defaults.data(forKey: configurationKey), let cached = try? JSONDecoder().decode(Directory.self, from: data),
           let validated = try? Self.validatedConfiguration(cached) {
            server = validated.0; provider = validated.1; publishableKey = validated.2
        }
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                   kSecAttrAccount as String: "session", kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var result: CFTypeRef?
        if SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data {
            if let stored = try? JSONDecoder().decode(StoredSession.self, from: data), stored.server == server,
               (stored.provider ?? Provider.selfHosted.rawValue) == provider.rawValue {
                session = stored.session
            }
        }
    }
    private static func validatedConfiguration(_ value: Directory) throws -> (String, Provider, String) {
        guard value.schema == 1, let address = value.serverURL, !address.isEmpty else { throw RemoteAuthError.notReady }
        let origin = try cleanOrigin(address)
        guard let provider = Provider(rawValue: value.provider ?? Provider.selfHosted.rawValue) else { throw RemoteAuthError.invalidURL }
        let key = value.publishableKey ?? ""
        if provider == .supabase {
            guard URL(string: origin)?.host?.range(of: #"^[a-z0-9]+\.supabase\.co$"#, options: .regularExpression) != nil,
                  key.range(of: #"^sb_publishable_[A-Za-z0-9_-]{16,1024}$"#, options: .regularExpression) != nil else {
                throw RemoteAuthError.invalidURL
            }
        }
        return (origin, provider, key)
    }
    private func resolveServer() async throws {
        if configured, let lastResolution, Date().timeIntervalSince(lastResolution) < 300 { return }
        var lookup = URLRequest(url: Self.directoryURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 12)
        lookup.setValue("application/json", forHTTPHeaderField: "Accept")
        let response: (Data, URLResponse)
        do { response = try await urlSession.data(for: lookup) }
        catch {
            if Task.isCancelled { throw CancellationError() }
            // Reuse only a previously verified owner configuration during a directory outage.
            // This never substitutes a local registration or local password check.
            if configured { return }
            throw RemoteAuthError.unavailable
        }
        guard let http = response.1 as? HTTPURLResponse, http.statusCode == 200, response.0.count <= 4096,
              let directory = try? JSONDecoder().decode(Directory.self, from: response.0), directory.schema == 1 else {
            if configured { return }
            throw RemoteAuthError.notReady
        }
        let (origin, nextProvider, key) = try Self.validatedConfiguration(directory)
        if origin != server || nextProvider != provider { clearSession() }
        server = origin; provider = nextProvider; publishableKey = key
        defaults.set(origin, forKey: serverKey)
        defaults.set(try JSONEncoder().encode(directory), forKey: configurationKey)
        lastResolution = Date()
    }
    func authenticate(email: String, password: String, name: String? = nil) async throws -> RemoteUser {
        invalidateAuthorization()
        let generation = authorizationGeneration
        try await resolveServer()
        guard generation == authorizationGeneration else { throw CancellationError() }
        var body: [String: Any] = ["email": email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), "password": password]
        if let name {
            let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
            if provider == .supabase { body["data"] = ["name": cleanName] }
            else { body["name"] = cleanName }
        }
        let origin = server
        let response: RemoteSession
        if provider == .supabase {
            let value: SupabaseSession = try await request(name == nil ? "token" : "signup", method: "POST", body: body,
                                                        authorized: false, query: name == nil ? "grant_type=password" : nil)
            response = try value.remoteSession()
        } else {
            response = try await request(name == nil ? "login" : "register", method: "POST", body: body, authorized: false)
        }
        guard server == origin, generation == authorizationGeneration, !Task.isCancelled else { throw CancellationError() }
        try saveSession(response); return response.user
    }
    func authenticateWithGoogle(expectedEmail: String? = nil, openBrowser: ((URL) async throws -> URL)? = nil) async throws -> RemoteUser {
        guard googleAttempt == nil else { throw RemoteAuthError.rejected("Ya hay un acceso en curso.") }
        invalidateAuthorization()
        let attempt = authorizationGeneration
        googleAttempt = attempt
        defer {
            if googleAttempt == attempt { googleAttempt = nil; googleBrowser = nil }
        }
        func checkAttempt() throws {
            guard googleAttempt == attempt, authorizationGeneration == attempt, !Task.isCancelled else { throw CancellationError() }
        }
        try await resolveServer()
        try checkAttempt()
        guard provider == .supabase else { throw RemoteAuthError.rejected("El acceso con Google todavía no está disponible. Puedes entrar con tu correo.") }
        let origin = server
        let settings: SupabaseSettings = try await request("settings", method: "GET", authorized: false)
        try checkAttempt()
        guard settings.external?.google == true else {
            throw RemoteAuthError.rejected("El acceso con Google todavía no está disponible. Puedes entrar con tu correo.")
        }
        let flow = try GoogleOAuthRequest(origin: origin)
        let callback: URL
        if let openBrowser { callback = try await openBrowser(flow.authorizeURL) }
        else {
            let browser = NativeGoogleBrowser(); googleBrowser = browser
            callback = try await browser.open(flow.authorizeURL)
        }
        try checkAttempt()
        guard server == origin else { throw CancellationError() }
        let code = try flow.code(from: callback)
        let value: SupabaseSession = try await request("token", method: "POST", body: ["auth_code": code, "code_verifier": flow.verifier],
                                                     authorized: false, query: "grant_type=pkce")
        try checkAttempt()
        let response = try value.remoteSession()
        if let expectedEmail, response.user.email != expectedEmail.lowercased() {
            revoke(response, address: origin, provider: .supabase, key: publishableKey)
            throw RemoteAuthError.rejected("Selecciona la cuenta de Google de \(expectedEmail). Para utilizar otra cuenta, cierra la sesión actual.")
        }
        try saveSession(response)
        return response.user
    }
    private struct SupabaseSettings: Decodable {
        var external: External?
        struct External: Decodable { var google: Bool? }
    }
    private func invalidateAuthorization() {
        authorizationGeneration = UUID()
        googleAttempt = nil
        googleBrowser?.cancel(); googleBrowser = nil
    }
    func validate() async throws -> RemoteUser {
        try await resolveServer()
        guard signedIn else { clearSession(); throw RemoteAuthError.rejected("La sesión ha caducado. Vuelve a entrar.") }
        if provider == .supabase {
            if session!.expiresAt - Date().timeIntervalSince1970 < 120 {
                guard let refreshToken = session?.refreshToken, !refreshToken.isEmpty else {
                    clearSession(); throw RemoteAuthError.rejected("La sesión ha caducado. Vuelve a entrar.")
                }
                let value: SupabaseSession = try await request("token", method: "POST", body: ["refresh_token": refreshToken],
                                                             authorized: false, query: "grant_type=refresh_token", boundToSession: true)
                try saveSession(value.remoteSession())
                return session!.user
            }
            let value: SupabaseUser = try await request("user", method: "GET", authorized: true)
            return try value.remoteUser()
        }
        if session!.expiresAt - Date().timeIntervalSince1970 < 12 * 3600 {
            let response: RemoteSession = try await request("refresh", method: "POST", authorized: true)
            try saveSession(response); return response.user
        }
        return try await request("me", method: "GET", authorized: true)
    }
    func logout() {
        invalidateAuthorization()
        let old = session
        let address = server
        let oldProvider = provider
        let oldKey = publishableKey
        clearSession()
        if let old { revoke(old, address: address, provider: oldProvider, key: oldKey) }
    }
    private func revoke(_ value: RemoteSession, address: String, provider: Provider, key: String) {
        guard let base = URL(string: address) else { return }
        var components = URLComponents(url: base.appendingPathComponent(provider == .supabase ? "auth/v1/logout" : "v1/auth/logout"), resolvingAgainstBaseURL: false)!
        if provider == .supabase { components.query = "scope=local" }
        var revoke = URLRequest(url: components.url!, timeoutInterval: 15)
        revoke.httpMethod = "POST"
        revoke.setValue("Bearer " + value.token, forHTTPHeaderField: "Authorization")
        if provider == .supabase { revoke.setValue(key, forHTTPHeaderField: "apikey") }
        // Start immediately: a deferred Task could outlive an injected session's teardown.
        urlSession.dataTask(with: revoke) { _, _, _ in }.resume()
    }
    private struct SupabaseUser: Decodable {
        let email: String?
        var user_metadata: Metadata?
        struct Metadata: Decodable { var name: String?; var full_name: String? }
        func remoteUser() throws -> RemoteUser {
            guard let email, !email.isEmpty else { throw RemoteAuthError.unavailable }
            return RemoteUser(name: user_metadata?.name ?? user_metadata?.full_name ?? String(email.split(separator: "@").first ?? ""), email: email.lowercased())
        }
    }
    private struct SupabaseSession: Decodable {
        var access_token: String?; var refresh_token: String?
        var expires_at: Double?; var expires_in: Double?
        let user: SupabaseUser
        func remoteSession() throws -> RemoteSession {
            guard let token = access_token, !token.isEmpty, let refresh = refresh_token, !refresh.isEmpty else {
                throw RemoteAuthError.rejected("Comprueba tu correo para confirmar la cuenta antes de iniciar sesión.")
            }
            guard let expiry = expires_at ?? expires_in.map({ Date().timeIntervalSince1970 + $0 }), expiry > Date().timeIntervalSince1970 else {
                throw RemoteAuthError.unavailable
            }
            return RemoteSession(token: token, expiresAt: expiry, user: try user.remoteUser(), refreshToken: refresh)
        }
    }
    private struct EmptyResponse: Decodable {}
    private func request<Response: Decodable>(_ path: String, method: String, body: [String: Any]? = nil, authorized: Bool,
                                              query: String? = nil, boundToSession: Bool = false) async throws -> Response {
        guard let base = URL(string: server), base.scheme == "https" else { throw RemoteAuthError.invalidURL }
        var components = URLComponents(url: base.appendingPathComponent(provider == .supabase ? "auth/v1" : "v1/auth").appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        components.query = query
        var request = URLRequest(url: components.url!, timeoutInterval: 15)
        request.httpMethod = method; request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let body { request.httpBody = try JSONSerialization.data(withJSONObject: body) }
        if provider == .supabase { request.setValue(publishableKey, forHTTPHeaderField: "apikey") }
        if authorized { guard let session else { throw RemoteAuthError.rejected("Vuelve a iniciar sesión.") }; request.setValue("Bearer " + session.token, forHTTPHeaderField: "Authorization") }
        let origin = server
        let sentProvider = provider
        let sentToken = (authorized || boundToSession) ? session?.token : nil
        let response: (Data, URLResponse)
        do { response = try await urlSession.data(for: request) }
        catch { if Task.isCancelled { throw CancellationError() }; throw RemoteAuthError.unavailable }
        guard server == origin, provider == sentProvider, !(authorized || boundToSession) || session?.token == sentToken else { throw CancellationError() }
        guard let http = response.1 as? HTTPURLResponse, response.0.count <= 64_000 else { throw RemoteAuthError.unavailable }
        guard (200...299).contains(http.statusCode) else {
            if (authorized && http.statusCode == 401) || (boundToSession && [400, 401].contains(http.statusCode)) { clearSession() }
            let json = try? JSONSerialization.jsonObject(with: response.0) as? [String: Any]
            if provider == .supabase {
                let code = json?["error_code"] as? String ?? json?["code"] as? String ?? ""
                let message: String
                switch code {
                case "invalid_credentials": message = "Correo o contraseña incorrectos."
                case "email_not_confirmed": message = "Comprueba tu correo para confirmar la cuenta."
                case "user_already_exists": message = "Ya existe una cuenta con ese correo."
                case "signup_disabled": message = "El registro todavía no está disponible."
                default: message = http.statusCode == 429 ? "Demasiados intentos. Espera unos minutos." : "No se pudo completar el acceso. Revisa tus datos o inténtalo más tarde."
                }
                throw RemoteAuthError.rejected(message)
            }
            throw RemoteAuthError.rejected(json?["detail"] as? String ?? "El servidor no ha aceptado la solicitud. Revisa tus datos.")
        }
        return try JSONDecoder().decode(Response.self, from: http.statusCode == 204 ? Data("{}".utf8) : response.0)
    }
    private func saveSession(_ value: RemoteSession) throws {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: "session"]
        let data = try JSONEncoder().encode(StoredSession(server: server, session: value, provider: provider.rawValue))
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
