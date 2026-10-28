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
    case profileRequestFailed, invalidProfile, cancelled, installationFailed
    var message: String {
        switch self {
        case .connectionUnavailable: return "Activa la VPN local y configura el archivo de emparejamiento en esta beta."
        case .discoveryFailed: return "No se ha podido consultar el reloj. Comprueba que está desbloqueado y enlazado al iPhone. Esta función necesita el motor Idevice."
        case .noWatch: return "El iPhone no ha devuelto ningún Watch enlazado."
        case .watchChanged: return "Ha cambiado el reloj enlazado. Vuelve a detectarlo antes de probar el perfil."
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
        case listAppIDs, listDevices, registerDevice, downloadProfile, decodeProfile
        var title: String {
            switch self {
            case .listAppIDs: return "Buscar el App ID existente"
            case .listDevices: return "Consultar dispositivos de watchOS"
            case .registerDevice: return "Registrar el Watch"
            case .downloadProfile: return "Descargar el perfil de watchOS"
            case .decodeProfile: return "Leer el perfil recibido"
            }
        }
    }
    enum Kind: String, Codable {
        case appleAPI, network, invalidResponse, existingAppIDMissing, missingProfile, unknown
    }
    let operation: Operation
    let kind: Kind
    let code: Int?
    var message: String {
        var detail = operation.title
        if let code { detail += " · Código: \(code)" }
        switch kind {
        case .existingAppIDMissing: detail += " · No se encontró el identificador de esta instalación. No se ha creado otro."
        case .network: detail += " · Fallo de red al contactar con Apple."
        case .invalidResponse, .missingProfile: detail += " · Apple no devolvió una respuesta de perfil válida."
        case .appleAPI: detail += " · Apple rechazó la solicitud."
        case .unknown: detail += " · Error no clasificado."
        }
        return detail
    }
}

/// Whitelisted report: never includes device IDs, account names, secrets or raw server errors.
struct WatchBetaReport: Codable, Equatable {
    var schema = 2
    var beta = "0.7.1-build711"
    var statuses: [String: WatchBetaStatus] = Dictionary(uniqueKeysWithValues: WatchBetaStage.allCases.map { ($0.rawValue, .pending) })
    var pairedWatchCount: Int?
    var freeAccount: Bool?
    var issue: WatchBetaIssue?
    var profileDiagnostic: WatchBetaProfileDiagnostic?
    var physicalInstallationVerified = false
    var renewalVerified = false

    mutating func set(_ stage: WatchBetaStage, _ status: WatchBetaStatus) { statuses[stage.rawValue] = status }
    func status(_ stage: WatchBetaStage) -> WatchBetaStatus { statuses[stage.rawValue] ?? .pending }
    mutating func invalidateProfile() {
        set(.profile, .pending); issue = nil; profileDiagnostic = nil
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

    static func validProfile(platforms: [String], bundle: String, expectedBundle: String,
                             team: String, expectedTeam: String, devices: [String], selectedWatch: String,
                             expires: Date, certificateCount: Int, now: Date = Date()) -> Bool {
        platforms.contains { $0.lowercased() == "watchos" }
        && !expectedBundle.isEmpty && bundle == expectedBundle
        && !expectedTeam.isEmpty && team == expectedTeam
        && !selectedWatch.isEmpty && devices.contains(selectedWatch)
        && expires > now && certificateCount > 0
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
