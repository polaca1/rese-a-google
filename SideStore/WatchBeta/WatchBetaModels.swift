import Foundation

enum WatchBetaStage: String, Codable, CaseIterable, Identifiable {
    case connection, discovery, account, profile, installation, renewal
    var id: String { rawValue }
    var title: String {
        switch self {
        case .connection: return "Conexión con el iPhone"
        case .discovery: return "Watch enlazado"
        case .account: return "Cuenta Apple"
        case .profile: return "Perfil de watchOS"
        case .installation: return "Instalación en el Watch"
        case .renewal: return "Renovación"
        }
    }
}

enum WatchBetaStatus: String, Codable { case pending, running, passed, failed }
enum WatchBetaIssue: String, Codable {
    case connectionUnavailable, discoveryFailed, noWatch, watchChanged, accountUnavailable
    case profileRequestFailed, invalidProfile, cancelled, installationFailed, accountRequestFailed
    var message: String {
        switch self {
        case .connectionUnavailable: return "Activa la VPN local y configura el archivo de emparejamiento en esta beta."
        case .discoveryFailed: return "No se ha podido consultar el reloj. Comprueba que está desbloqueado y enlazado al iPhone. Esta función necesita el motor Idevice."
        case .noWatch: return "El iPhone no ha devuelto ningún Watch enlazado."
        case .watchChanged: return "Ha cambiado el reloj enlazado. Vuelve a detectarlo antes de probar el perfil."
        case .accountRequestFailed: return "No se completó la comprobación de la cuenta Apple. Consulta el paso y el código del diagnóstico."
        case .accountUnavailable: return "Inicia sesión con tu cuenta Apple en los ajustes de esta beta."
        case .profileRequestFailed: return "Apple no ha entregado el perfil. Puede deberse a la cuota, la sesión o al soporte de esta cuenta. No demuestra que la cuenta gratuita sea incompatible."
        case .invalidProfile: return "El perfil recibido no cumple los requisitos de este Watch. No se ha instalado nada."
        case .installationFailed: return "No se completó la instalación real en el Watch. No se ha borrado la app anterior."
        case .cancelled: return "Comprobación cancelada. Si se había solicitado un registro a Apple, puede haberse completado."
        }
    }
}

/// Fixed values only; raw server messages and identifiers cannot enter this report.
struct WatchBetaProfileDiagnostic: Codable, Equatable {
    enum Operation: String, Codable {
        case resolveTeam, fetchAnisette, listAppIDs, listDevices, registerDevice, downloadProfile, decodeProfile
        var title: String {
            switch self {
            case .resolveTeam: return "Consultar la cuenta Apple"
            case .fetchAnisette: return "Obtener sesión y datos Anisette"
            case .listAppIDs: return "Buscar el App ID existente"
            case .listDevices: return "Consultar dispositivos de watchOS"
            case .registerDevice: return "Registrar el Watch"
            case .downloadProfile: return "Descargar el perfil de watchOS"
            case .decodeProfile: return "Leer el perfil recibido"
            }
        }
    }
    enum Kind: String, Codable {
        case appleAPI, network, invalidResponse, existingAppIDMissing, missingProfile, unknown, notAuthenticated, anisette
    }
    let operation: Operation
    let kind: Kind
    let code: Int?
    var message: String {
        var detail = operation.title
        if let code { detail += " · Código: \(code)" }
        switch kind {
        case .existingAppIDMissing: detail += " · No se encontró el identificador de esta instalación. No se ha creado otro."
        case .notAuthenticated: detail += " · La sesión Apple no está disponible. Inicia sesión de nuevo."
        case .anisette: detail += " · No se pudieron obtener los datos Anisette."
        case .network: detail += " · Fallo de red al contactar con Apple."
        case .invalidResponse, .missingProfile: detail += " · Apple no devolvió una respuesta de perfil válida."
        case .appleAPI: detail += " · Apple rechazó la solicitud."
        case .unknown: detail += " · Error no clasificado."
        }
        return detail
    }
}


/// Only allowlisted platform categories and comparison results leave the device.
struct WatchBetaProfileChecks: Codable, Equatable {
    enum Platform: String, Codable { case iOS, watchOS, other }
    let platforms: [Platform]
    let bundleMatches: Bool
    let teamMatches: Bool
    let containsWatch: Bool
    let notExpired: Bool
    let hasCertificate: Bool
    var platformCompatible: Bool { platforms.contains(.iOS) || platforms.contains(.watchOS) }
    var valid: Bool { platformCompatible && bundleMatches && teamMatches && containsWatch && notExpired && hasCertificate }
    var message: String {
        var failures: [String] = []
        if !platformCompatible { failures.append("plataforma no compatible") }
        if !bundleMatches { failures.append("el App ID no coincide") }
        if !teamMatches { failures.append("la cuenta no coincide") }
        if !containsWatch { failures.append("el perfil no incluye este Watch") }
        if !notExpired { failures.append("perfil caducado; comprueba la fecha del iPhone") }
        if !hasCertificate { failures.append("sin certificado válido") }
        return failures.isEmpty ? "El perfil incluye este Watch y supera las comprobaciones previas. Falta verificar la instalación."
            : "Perfil rechazado: " + failures.joined(separator: "; ") + "."
    }
}
struct WatchBetaInvalidProfile: Error {
    let checks: WatchBetaProfileChecks
}

/// Whitelisted report: never includes device IDs, account names, secrets or raw server errors.
struct WatchBetaReport: Codable, Equatable {
    var schema = 4
    var beta = "0.7.1-build713"
    var statuses: [String: WatchBetaStatus] = Dictionary(uniqueKeysWithValues: WatchBetaStage.allCases.map { ($0.rawValue, .pending) })
    var pairedWatchCount: Int?
    var freeAccount: Bool?
    var issue: WatchBetaIssue?
    var profileDiagnostic: WatchBetaProfileDiagnostic?
    var accountDiagnostic: WatchBetaProfileDiagnostic?
    var profileChecks: WatchBetaProfileChecks?
    var automaticProfileChecks: WatchBetaProfileChecks?
    var physicalInstallationVerified = false
    var renewalVerified = false

    mutating func set(_ stage: WatchBetaStage, _ status: WatchBetaStatus) { statuses[stage.rawValue] = status }
    func status(_ stage: WatchBetaStage) -> WatchBetaStatus { statuses[stage.rawValue] ?? .pending }
    /// Once the registry succeeded, subsequent failures belong to the account step.
    var detectionFailureStage: WatchBetaStage {
        if status(.discovery) == .passed { return .account }
        return status(.connection) == .passed ? .discovery : .connection
    }
    mutating func invalidateProfile() {
        set(.profile, .pending); issue = nil; profileDiagnostic = nil; profileChecks = nil; automaticProfileChecks = nil
    }
    func export() -> String {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return String(data: (try? encoder.encode(self)) ?? Data(), encoding: .utf8) ?? "{}"
    }
}

enum WatchBetaValidation {
    static func preferredPortalID(available: [String], saved: String?, runtime: String,
        profileBundle: String?, profileTeam: String?, sessionTeam: String) -> String? {
        let allowed = Set(available.filter { !$0.isEmpty && !$0.contains("*") })
        if let saved, allowed.contains(saved) { return saved }
        if profileTeam == sessionTeam, let profileBundle, allowed.contains(profileBundle) { return profileBundle }
        return allowed.contains(runtime) ? runtime : nil
    }
    static func newerBuild(currentVersion: String, currentBuild: String, version: String, build: String?) -> Bool {
        guard currentVersion == version, let build, let current = Int(currentBuild), let next = Int(build) else { return false }
        return current >= 0 && next > current
    }
    static func trustedBetaSource(_ source: String, download: String) -> Bool {
        let prefix = "https://raw.githubusercontent.com/polaca1/rese-a-google/refs/heads/sidestore-watch-source/"
        return [prefix+"source.json", prefix+"source-compatible.json"].contains(source)
            && download.hasPrefix("https://github.com/polaca1/rese-a-google/releases/download/sidestore-watch-beta-")
    }

    static func safeArchiveEntry(name: String, size: Int64, attributes: UInt32) -> Bool {
        !name.isEmpty && !name.hasPrefix("/") && !name.contains("\\")
        && !name.split(separator: "/").contains("..") && !name.contains("\0")
        && size >= 0 && size <= 100_000_000
        && (attributes >> 16) & 0o170000 != 0o120000
    }

    /// watchOS companion profiles can use Apple's iOS provisioning family.
    /// Platform alone never authorizes a Watch: exact device, team and bundle remain required.
    static func profileChecks(platforms: [String], bundle: String, expectedBundle: String,
                              team: String, expectedTeam: String, devices: [String], selectedWatch: String,
                              expires: Date, certificateCount: Int, now: Date = Date()) -> WatchBetaProfileChecks {
        let categories = platforms.map { value -> WatchBetaProfileChecks.Platform in
            switch value.lowercased() {
            case "ios": return .iOS
            case "watchos": return .watchOS
            default: return .other
            }
        }
        return WatchBetaProfileChecks(platforms: categories,
            bundleMatches: !expectedBundle.isEmpty && bundle == expectedBundle,
            teamMatches: !expectedTeam.isEmpty && team == expectedTeam,
            containsWatch: !selectedWatch.isEmpty && devices.contains(selectedWatch),
            notExpired: expires > now, hasCertificate: certificateCount > 0)
    }
    static func validProfile(platforms: [String], bundle: String, expectedBundle: String,
                             team: String, expectedTeam: String, devices: [String], selectedWatch: String,
                             expires: Date, certificateCount: Int, now: Date = Date()) -> Bool {
        profileChecks(platforms: platforms, bundle: bundle, expectedBundle: expectedBundle,
            team: team, expectedTeam: expectedTeam, devices: devices, selectedWatch: selectedWatch,
            expires: expires, certificateCount: certificateCount, now: now).valid
    }
    static func validRegistry(_ identifiers: [String]) -> Bool {
        identifiers.count <= 32 && Set(identifiers).count == identifiers.count
        && identifiers.allSatisfy { !$0.isEmpty && $0.utf8.count <= 128
            && $0.unicodeScalars.allSatisfy { CharacterSet.alphanumerics.contains($0) || $0 == "-" } }
    }
}

/// Restore cellular data after successful, failed and cancelled device operations.
@MainActor
enum WatchBetaLocalSession {
    static func run<T>(turnOff: () async -> Void, turnOn: () async -> Void,
                       operation: () async throws -> T) async throws -> T {
        await turnOff()
        let result: Result<T, Error>
        do { try Task.checkCancellation(); result = .success(try await operation()) }
        catch { result = .failure(error) }
        await turnOn()
        return try result.get()
    }
}


/// One-time preset requested for this personal variant; later user changes are preserved.
enum WatchBetaAnisettePreset {
    static let serverURL = "https://mac-ani.jkcoxson.com"
    static let pendingKey = "watchBetaAnisettePresetPending"
    private static let appliedKey = "watchBetaRemoteAnisettePresetV1"
    static func apply(to defaults: UserDefaults) {
        guard !defaults.bool(forKey: appliedKey) else { return }
        defaults.set(false, forKey: "useOnDeviceAnisette")
        defaults.set(serverURL, forKey: "menuAnisetteURL")
        defaults.set(true, forKey: pendingKey)
        defaults.set(true, forKey: appliedKey)
    }
}
