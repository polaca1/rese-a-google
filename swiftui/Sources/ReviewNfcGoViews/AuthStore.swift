import SwiftUI
import CryptoKit
import CommonCrypto
import Security

// MARK: - Models

struct UserProfile: Codable, Equatable {
    let name: String
    let email: String
}

// MARK: - Authentication (central account service)

@MainActor final class AuthStore: ObservableObject {
    @Published private(set) var currentUser: UserProfile?
    @Published var errorMessage: String?
    @Published private(set) var isAuthenticating = false
    var accountService: RemoteAuthClient { remote }
    private let remote: RemoteAuthClient

    private let userKey = "resenago.currentUser"
    private let accountsKey = "resenago.accounts"
    private let defaults: UserDefaults
    private let credentialService: String

    struct Account: Codable {
        let profile: UserProfile
        let passwordHash: String
        var passwordSalt: Data?
        var passwordIterations: Int?
    }

    init(defaults: UserDefaults = .standard,
         credentialService: String = (Bundle.main.bundleIdentifier ?? "reviewNfcGo") + ".accounts") {
        self.defaults = defaults
        self.credentialService = credentialService
        remote = RemoteAuthClient(defaults: defaults, credentialService: credentialService + ".remote-session")
        _ = loadAccounts() // Safely migrate legacy credentials before removing their old copy.
        if let data = defaults.data(forKey: userKey),
           let profile = try? JSONDecoder().decode(UserProfile.self, from: data) {
            if remote.signedIn && remote.session?.user.email == profile.email { currentUser = profile }
            #if DEBUG
            let fixture = ProcessInfo.processInfo.arguments.contains { $0.hasPrefix("--verification-") }
            if fixture { currentUser = profile }
            #endif
        }
    }

    #if DEBUG
    func createAccount(name: String, email: String, password: String) -> Bool {
        let cleanEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              cleanEmail.range(of: #"^[^\s@]+@[^\s@]+\.[^\s@]+$"#, options: .regularExpression) != nil,
              (8...128).contains(password.count) else {
            errorMessage = "Introduce un nombre y un correo válidos. La contraseña debe tener entre 8 y 128 caracteres."
            return false
        }
        guard var accounts = loadAccounts() else { return storageFailure() }
        guard accounts[cleanEmail] == nil else {
            errorMessage = "Ya existe una cuenta con ese correo."
            return false
        }
        let profile = UserProfile(name: name.trimmingCharacters(in: .whitespacesAndNewlines), email: cleanEmail)
        guard let account = Self.secureAccount(profile, password: password) else { return storageFailure() }
        accounts[cleanEmail] = account
        guard saveAccounts(accounts) else { return storageFailure() }
        setCurrent(profile)
        errorMessage = nil
        return true
    }

    func login(email: String, password: String) -> Bool {
        let cleanEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard var accounts = loadAccounts() else { return storageFailure() }
        guard let account = accounts[cleanEmail] else {
            errorMessage = "Correo o contraseña incorrectos."
            return false
        }
        let candidate: String?
        if let salt = account.passwordSalt, let iterations = account.passwordIterations {
            candidate = Self.derive(password, salt: salt, iterations: iterations)
        } else {
            candidate = Self.legacyHash(password)
        }
        guard let candidate, Self.equal(candidate, account.passwordHash) else {
            errorMessage = "Correo o contraseña incorrectos."
            return false
        }
        // Existing short passwords remain valid. Strengthen their stored hash on login.
        if account.passwordSalt == nil {
            guard let upgraded = Self.secureAccount(account.profile, password: password) else { return storageFailure() }
            accounts[cleanEmail] = upgraded
            guard saveAccounts(accounts) else { return storageFailure() }
        }
        setCurrent(account.profile)
        errorMessage = nil
        return true
    }

    #endif

    func logout() {
        currentUser = nil
        defaults.removeObject(forKey: userKey)
        errorMessage = nil
        remote.logout()
    }
    func authenticate(name: String?, email: String, password: String) async {
        guard !isAuthenticating else { return }
        isAuthenticating = true; defer { isAuthenticating = false }
        do {
            let user = try await remote.authenticate(email: email, password: password, name: name)
            setCurrent(UserProfile(name: user.name, email: user.email)); errorMessage = nil
        } catch { errorMessage = error.localizedDescription }
    }
    func authenticateWithGoogle() async {
        guard !isAuthenticating else { return }
        isAuthenticating = true; errorMessage = nil
        defer { isAuthenticating = false }
        do {
            let user = try await remote.authenticateWithGoogle(expectedEmail: currentUser?.email)
            setCurrent(UserProfile(name: user.name, email: user.email))
        } catch is CancellationError { }
        catch { errorMessage = error.localizedDescription }
    }
    func validateServerSession() async {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains(where: { $0.hasPrefix("--verification-") }) { return }
        #endif
        guard currentUser != nil else { return }
        do { _ = try await remote.validate() }
        catch {
            if !remote.signedIn { currentUser = nil; defaults.removeObject(forKey: userKey) }
            errorMessage = error.localizedDescription
        }
    }

    private func setCurrent(_ profile: UserProfile) {
        currentUser = profile
        if let data = try? JSONEncoder().encode(profile) { defaults.set(data, forKey: userKey) }
    }

    private var credentialQuery: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: credentialService, kSecAttrAccount as String: "local-accounts"]
    }
    private func loadAccounts() -> [String: Account]? {
        var query = credentialQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecSuccess {
            guard let data = result as? Data,
                  let value = try? JSONDecoder().decode([String: Account].self, from: data) else { return nil }
            return value
        }
        guard status == errSecItemNotFound else { return nil }
        guard let data = defaults.data(forKey: accountsKey) else { return [:] }
        guard let legacy = try? JSONDecoder().decode([String: Account].self, from: data) else { return nil }
        // Delete the preferences copy only after the Keychain write succeeds.
        if saveAccounts(legacy) { defaults.removeObject(forKey: accountsKey) }
        return legacy
    }
    private func saveAccounts(_ accounts: [String: Account]) -> Bool {
        guard let data = try? JSONEncoder().encode(accounts) else { return false }
        let attributes: [String: Any] = [kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
        var status = SecItemUpdate(credentialQuery as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            status = SecItemAdd(credentialQuery.merging(attributes) { _, new in new } as CFDictionary, nil)
        }
        return status == errSecSuccess
    }
    private func storageFailure() -> Bool {
        errorMessage = "No se pudo acceder a tus credenciales. Desbloquea el iPhone y vuelve a intentarlo."
        return false
    }
    private static func secureAccount(_ profile: UserProfile, password: String) -> Account? {
        var salt = Data(count: 16)
        let status = salt.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, 16, $0.baseAddress!) }
        guard status == errSecSuccess, let hash = derive(password, salt: salt, iterations: 120_000) else { return nil }
        return Account(profile: profile, passwordHash: hash, passwordSalt: salt, passwordIterations: 120_000)
    }
    private static func derive(_ password: String, salt: Data, iterations: Int) -> String? {
        guard salt.count == 16, (10_000...500_000).contains(iterations), password.utf8.count <= 1024 else { return nil }
        let input = Array(password.utf8)
        var output = Data(count: 32)
        let status = input.withUnsafeBytes { bytes in
            salt.withUnsafeBytes { saltBytes in
                output.withUnsafeMutableBytes { result in
                    CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2), bytes.baseAddress?.assumingMemoryBound(to: Int8.self), input.count,
                        saltBytes.baseAddress?.assumingMemoryBound(to: UInt8.self), salt.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256), UInt32(iterations),
                        result.baseAddress?.assumingMemoryBound(to: UInt8.self), 32)
                }
            }
        }
        guard status == kCCSuccess else { return nil }
        return output.map { String(format: "%02x", $0) }.joined()
    }
    private static func legacyHash(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }
    private static func equal(_ left: String, _ right: String) -> Bool {
        let a = Array(left.utf8), b = Array(right.utf8)
        guard a.count == b.count else { return false }
        return zip(a, b).reduce(UInt8(0)) { $0 | ($1.0 ^ $1.1) } == 0
    }
}
