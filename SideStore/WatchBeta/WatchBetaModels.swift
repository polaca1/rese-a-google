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
    case profileRequestFailed, invalidProfile, cancelled
    var message: String {
        switch self {
        case .connectionUnavailable: return "Activa la VPN local y configura el archivo de emparejamiento en esta beta."
        case .discoveryFailed: return "No se ha podido consultar el reloj. Comprueba que está desbloqueado y enlazado al iPhone. Esta función necesita el motor Idevice."
        case .noWatch: return "El iPhone no ha devuelto ningún Watch enlazado."
        case .watchChanged: return "Ha cambiado el reloj enlazado. Vuelve a detectarlo antes de probar el perfil."
        case .accountUnavailable: return "Inicia sesión con tu cuenta Apple en los ajustes de esta beta."
        case .profileRequestFailed: return "Apple no ha entregado el perfil. Puede deberse a la cuota, la sesión o al soporte de esta cuenta. No demuestra que la cuenta gratuita sea incompatible."
        case .invalidProfile: return "El perfil recibido no cumple los requisitos de este Watch. No se ha instalado nada."
        case .cancelled: return "Comprobación cancelada. Si se había solicitado un registro a Apple, puede haberse completado."
        }
    }
}

/// Whitelisted report: never includes device IDs, account names, secrets or raw server errors.
struct WatchBetaReport: Codable, Equatable {
    var schema = 1
    var beta = "0.1.0"
    var statuses: [String: WatchBetaStatus] = Dictionary(uniqueKeysWithValues: WatchBetaStage.allCases.map { ($0.rawValue, .pending) })
    var pairedWatchCount: Int?
    var freeAccount: Bool?
    var issue: WatchBetaIssue?
    var physicalInstallationVerified = false
    var renewalVerified = false

    mutating func set(_ stage: WatchBetaStage, _ status: WatchBetaStatus) { statuses[stage.rawValue] = status }
    func status(_ stage: WatchBetaStage) -> WatchBetaStatus { statuses[stage.rawValue] ?? .pending }
    func export() -> String {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return String(data: (try? encoder.encode(self)) ?? Data(), encoding: .utf8) ?? "{}"
    }
}

enum WatchBetaValidation {
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
