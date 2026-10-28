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


struct WatchBetaInstallationDiagnostic: Codable, Equatable {
    enum Operation: String, Codable {
        case account, profile, signing, connection, registry, pairingFile, forwardLockdown, connectLockdown
        case pairWatch, watchSession, verifyWatch, startInstaller, forwardInstaller, connectInstaller
        case secureTransfer, prepareTransfer, sendTransfer, waitConfirmation, watchRejected, transport
        var title: String {
            switch self {
            case .account: return "Obtener la cuenta Apple"
            case .profile: return "Preparar el perfil"
            case .signing: return "Firmar la app"
            case .connection: return "Preparar la conexión local"
            case .registry: return "Consultar el Watch enlazado"
            case .pairingFile: return "Leer el emparejamiento del iPhone"
            case .forwardLockdown: return "Abrir el enlace al Watch"
            case .connectLockdown: return "Conectar con el servicio del Watch"
            case .pairWatch: return "Emparejar con el Watch"
            case .watchSession: return "Iniciar sesión en el Watch"
            case .verifyWatch: return "Confirmar la identidad del Watch"
            case .startInstaller: return "Abrir el instalador de watchOS"
            case .forwardInstaller: return "Abrir el enlace al instalador"
            case .connectInstaller: return "Conectar con el instalador"
            case .secureTransfer: return "Proteger la conexión de envío"
            case .prepareTransfer: return "Preparar los archivos firmados"
            case .sendTransfer: return "Enviar la app al Watch"
            case .waitConfirmation: return "Esperar la confirmación de watchOS"
            case .watchRejected: return "watchOS rechazó la app"
            case .transport: return "Instalar en el Watch"
            }
        }
    }
    enum Kind: String, Codable { case operationFailed, certificateMismatch, nativeFailure, watchRejected, timeout, unsupportedPairing }
    let operation: Operation
    let kind: Kind
    let code: Int?
    var message: String {
        if kind == .certificateMismatch { return "El certificado activo no está incluido en el perfil. No se ha enviado la app ni modificado certificados." }
        if kind == .unsupportedPairing { return "El emparejamiento seleccionado no está disponible en este transporte." }
        var result = operation.title
        if let code { result += " · Código: \(code)" }
        if kind == .timeout { result += " · Tiempo de espera agotado." }
        switch code {
        case 40: result += " · Se ha rechazado la confianza. No se volverá a solicitar automáticamente."
        case 41: result += " · Desbloquea el reloj y vuelve a intentarlo."
        case 42: result += " · El reloj no reconoce esta identidad."
        case 43: result += " · El reloj ha devuelto una respuesta de emparejamiento no admitida."
        case 44: result += " · La conexión se ha interrumpido al confirmar la confianza."
        case 45: result += " · No se ha podido preparar el registro de confianza."
        case 46: result += " · La confirmación de confianza sigue pendiente."
        case 47: result += " · No se ha completado el intercambio de confianza."
        case 50: result += " · Falta el registro de emparejamiento."
        case 51: result += " · watchOS ha rechazado el registro de emparejamiento."
        case 52: result += " · watchOS ha rechazado el certificado de confianza."
        case 53: result += " · watchOS no permite emparejar a través de esta conexión."
        case 54: result += " · El Watch no ha podido guardar la confianza."
        case 55: result += " · watchOS ha devuelto PairingFailed."
        case 56: result += " · El dispositivo solicita una identidad de supervisión."
        case 57: result += " · El acceso protegido del Watch está bloqueado."
        case 58, 60: result += " · La sesión de confianza no está activa."
        case 59, 65: result += " · La respuesta de emparejamiento no tiene el formato esperado."
        case 61, 62: result += " · watchOS ha prohibido esta operación."
        case 63: result += " · Falta la identidad del equipo."
        case 64: result += " · watchOS ha rechazado un argumento del intercambio."
        case 101: result += " · La asociación con la app del iPhone no es válida."
        case 102, 108: result += " · La firma y el identificador de la app no coinciden."
        case 103: result += " · watchOS rechazó el perfil incluido."
        case 104: result += " · El reloj está bloqueado."
        case 105: result += " · La versión del sistema no es compatible."
        case 106: result += " · Se ha alcanzado un límite de apps."
        case 111: result += " · No hay espacio suficiente."
        default: break
        }
        return result
    }
    static func native(_ code: Int) -> Self? {
        let operation: Operation
        switch code {
        case 1, 4: operation = .transport
        case 2, 3: operation = .registry
        case 10: operation = .pairingFile
        case 11: operation = .forwardLockdown
        case 12: operation = .connectLockdown
        case 13, 40...47, 50...65: operation = .pairWatch
        case 14: operation = .watchSession
        case 15, 26: operation = .verifyWatch
        case 16: operation = .startInstaller
        case 17: operation = .forwardInstaller
        case 18: operation = .connectInstaller
        case 19: operation = .secureTransfer
        case 20: operation = .prepareTransfer
        case 21: operation = .sendTransfer
        case 22, 24: operation = .waitConfirmation
        case 30: operation = .transport
        case 31: operation = .sendTransfer
        case 100...112, 199: operation = .watchRejected
        default: return nil
        }
        let kind: Kind = (code == 30 || code == 31) ? .timeout
            : (operation == .watchRejected ? .watchRejected : .nativeFailure)
        return Self(operation: operation, kind: kind, code: code)
    }
    /// Parse only our bridge's complete fixed message. Arbitrary library messages never enter exports.
    static func transportReason(_ reason: String) -> Self? {
        if reason == "Watch installer currently requires a TCP pairing file" {
            return Self(operation: .transport, kind: .unsupportedPairing, code: nil)
        }
        let prefix = "Watch installation failed (stage code "
        let suffix = "); no existing app was removed"
        guard reason.hasPrefix(prefix), reason.hasSuffix(suffix),
              let code = Int(reason.dropFirst(prefix.count).dropLast(suffix.count)),
              reason == prefix + String(code) + suffix else { return nil }
        return native(code)
    }
}
struct WatchBetaInstallFailure: Error {
    let diagnostic: WatchBetaInstallationDiagnostic
}

/// Whitelisted report: never includes device IDs, account names, secrets or raw server errors.
struct WatchBetaReport: Codable, Equatable {
    var schema = 5
    var beta = "0.7.1-build717"
    var statuses: [String: WatchBetaStatus] = Dictionary(uniqueKeysWithValues: WatchBetaStage.allCases.map { ($0.rawValue, .pending) })
    var pairedWatchCount: Int?
    var freeAccount: Bool?
    var issue: WatchBetaIssue?
    var profileDiagnostic: WatchBetaProfileDiagnostic?
    var accountDiagnostic: WatchBetaProfileDiagnostic?
    var profileChecks: WatchBetaProfileChecks?
    var automaticProfileChecks: WatchBetaProfileChecks?
    var installationDiagnostic: WatchBetaInstallationDiagnostic?
    var automaticInstallationDiagnostic: WatchBetaInstallationDiagnostic?
    var activeCertificateMatchesProfile: Bool?
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
    static func bootstrapPortalID(available: [String], phoneBundle: String) -> String? {
        guard !phoneBundle.isEmpty else { return nil }
        let allowed = Set(available.filter { !$0.contains("*") })
        for suffix in [".watch", ".SideBackup", ".AltWidget"] {
            let identifier = phoneBundle + suffix
            if allowed.contains(identifier) { return identifier }
        }
        return nil
    }
    static func canRunAutomaticInstallation(working: Bool, manualUIVisible: Bool, manualOperationRunning: Bool) -> Bool {
        !working && !manualUIVisible && !manualOperationRunning
    }
    static func matchingCertificate(active: Data?, allowed: [Data]) -> Bool {
        guard let active, !active.isEmpty else { return false }
        return allowed.contains(active)
    }
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
