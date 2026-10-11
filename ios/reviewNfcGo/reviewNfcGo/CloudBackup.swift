import Foundation
import Combine
import CryptoKit

struct CloudBackupRecord: Codable {
    let user_id: String
    let revision: Int64
    let payload: BusinessBackup
    var updated_at: String? = nil
}
enum CloudBackupError: LocalizedError {
    case unavailable, notConfigured, conflict, invalid
    var errorDescription: String? {
        switch self {
        case .unavailable: return "Pendiente de conexión. Tus cambios siguen guardados en este dispositivo."
        case .notConfigured: return "El guardado en la nube aún no está disponible. Conserva una copia en Archivos."
        case .conflict: return "Hay cambios distintos en este dispositivo y en la nube. Elige qué copia conservar."
        case .invalid: return "No se pudo validar la copia de la nube. Tus datos locales se han conservado."
        }
    }
}
@MainActor protocol CloudBackupTransport: AnyObject {
    func loadCloudHistory(owner: String) async throws -> [CloudBackupRecord]
    func loadCloudBackup(owner: String) async throws -> CloudBackupRecord?
    func saveCloudBackup(_ value: BusinessBackup, expectedRevision: Int64?) async throws -> CloudBackupRecord
}
extension CloudBackupTransport {
    func loadCloudHistory(owner: String) async throws -> [CloudBackupRecord] { [] }
}
extension BusinessBackup {
    var hasContent: Bool { !records.isEmpty || !money.products.isEmpty || !money.transactions.isEmpty || !money.sales.isEmpty || photo != nil || money.weeklyGoals != nil || !(money.quickSales ?? []).isEmpty || !(money.quotations ?? []).isEmpty }
    func cloudFingerprint() throws -> String {
        var stable = self; stable.createdAt = Date(timeIntervalSince1970: 0)
        return SHA256.hash(data: try stable.encoded()).map { String(format: "%02x", $0) }.joined()
    }
}

/// Download first; an empty installation must never overwrite the existing cloud copy.
@MainActor final class CloudBackupController: ObservableObject {
    enum State: Equatable { case signedOut, checking, empty, pending, saved, conflict, failed(String) }
    @Published private(set) var state: State = .signedOut
    @Published private(set) var lastSaved: Date?
    private let defaults: UserDefaults
    private var owner: String?
    private var transport: CloudBackupTransport?
    private var read: (() throws -> BusinessBackup)?
    private var apply: ((BusinessBackup) throws -> Void)?
    private var generation = UUID()
    private var running = false
    private var applying = false
    private var repeatPass = false
    private var scheduled: Task<Void, Never>?
    private var heartbeat: Task<Void, Never>?
    private var conflictCopy: CloudBackupRecord?
    private var baselineKey: String { "reviewNfcGo.cloud.baseline." + (owner ?? "") }
    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    func recoveryData(remote: Bool) -> Data? {
        guard let owner else { return nil }
        return defaults.data(forKey: "reviewNfcGo.cloud.recovery." + (remote ? "remote." : "local.") + owner)
    }
    var message: String {
        switch state {
        case .signedOut: return "Inicia sesión para guardar tus datos en la nube."
        case .checking: return "Comprobando tus datos en la nube…"
        case .empty: return "Nube conectada. Tus próximos cambios se guardarán automáticamente."
        case .pending: return "Cambios guardados en este dispositivo, pendientes de subir…"
        case .saved: return "Guardado en la nube"
        case .conflict: return CloudBackupError.conflict.localizedDescription
        case .failed(let message): return message
        }
    }
    /// Closing the session disconnects automatic sync; warn whenever a save isn't confirmed.
    var hasSaveProblem: Bool {
        switch state {
        case .conflict, .failed: return true
        default: return false
        }
    }
    var shouldConfirmSignOut: Bool {
        switch state {
        case .checking, .pending, .conflict, .failed: return true
        case .signedOut, .empty, .saved: return false
        }
    }
    func connect(owner: String?, transport: CloudBackupTransport, read: @escaping () throws -> BusinessBackup,
                 apply: @escaping (BusinessBackup) throws -> Void, automatic: Bool = true) {
        scheduled?.cancel(); heartbeat?.cancel()
        generation = UUID(); running = false; applying = false; repeatPass = false; conflictCopy = nil
        self.owner = owner; self.transport = transport; self.read = read; self.apply = apply; lastSaved = nil
        state = owner == nil ? .signedOut : .checking
        guard owner != nil, automatic else { return }
        requestSync(immediate: true)
        let active = generation
        heartbeat = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(60)) } catch { return }
                guard let self, self.generation == active else { return }
                self.requestSync(immediate: true)
            }
        }
    }
    func localChanged() {
        guard owner != nil, !applying else { return }
        if state != .conflict { state = .pending }
        requestSync()
    }
    func requestSync(immediate: Bool = false) {
        guard owner != nil, state != .conflict else { return }
        if running { repeatPass = true; return }
        scheduled?.cancel()
        scheduled = Task { [weak self] in
            if !immediate { do { try await Task.sleep(for: .milliseconds(800)) } catch { return } }
            guard !Task.isCancelled else { return }
            await self?.synchronize()
        }
    }
    func synchronize() async {
        guard !running, state != .conflict, let owner, let transport, let read, let apply else { return }
        running = true; repeatPass = false
        let active = generation
        defer {
            if generation == active {
                running = false
                if repeatPass && state != .conflict { requestSync() }
            }
        }
        do {
            let cloud = try await transport.loadCloudBackup(owner: owner)
            try check(active)
            let local = try read().validated(for: owner)
            let localHash = try local.cloudFingerprint()
            let baseline = defaults.string(forKey: baselineKey)
            guard let cloud else {
                // Do not upload an empty first installation, even while offline recovery is pending.
                if local.hasContent { try await upload(local, expected: nil, active: active) }
                else { state = .empty }
                return
            }
            let remote = try cloud.payload.validated(for: owner)
            let remoteHash = try remote.cloudFingerprint()
            if localHash == remoteHash { remember(remoteHash); return }
            if baseline == remoteHash { try await upload(local, expected: cloud.revision, active: active); return }
            if baseline == localHash || (baseline == nil && !local.hasContent) {
                applying = true; defer { applying = false }
                try apply(remote)
                remember(remoteHash)
            } else { conflictCopy = cloud; state = .conflict }
        } catch is CancellationError {
            if generation == active { state = .pending }
        } catch CloudBackupError.conflict {
            if generation == active { state = .pending; repeatPass = true }
        } catch {
            if generation == active { state = .failed(error.localizedDescription) }
        }
    }
    func previousCopies() async throws -> [CloudBackupRecord] {
        guard let owner, let transport else { throw CloudBackupError.unavailable }
        let active = generation
        let result = try await transport.loadCloudHistory(owner: owner)
        try check(active); return result
    }
    func restorePrevious(_ copy: CloudBackupRecord) async throws {
        guard !running, let owner, let transport, let read, let apply else { throw CloudBackupError.unavailable }
        let active = generation; running = true; repeatPass = false; scheduled?.cancel()
        defer { if generation == active { running = false; if repeatPass { requestSync() } } }
        do {
            let restored = try copy.payload.validated(for: owner)
            let local = try read().validated(for: owner), hash = try local.cloudFingerprint()
            defaults.set(try local.encoded(), forKey: "reviewNfcGo.cloud.recovery.local." + owner)
            let current = try await transport.loadCloudBackup(owner: owner)
            try check(active)
            guard try read().cloudFingerprint() == hash else { throw CloudBackupError.conflict }
            if let current { defaults.set(try current.payload.encoded(), forKey: "reviewNfcGo.cloud.recovery.remote." + owner) }
            state = .pending
            let saved = try await transport.saveCloudBackup(restored, expectedRevision: current?.revision)
            try check(active)
            guard try saved.payload.cloudFingerprint() == restored.cloudFingerprint() else { throw CloudBackupError.invalid }
            guard try read().cloudFingerprint() == hash else { conflictCopy = saved; state = .conflict; return }
            applying = true; defer { applying = false }
            try apply(restored); remember(try restored.cloudFingerprint())
        } catch {
            if generation == active { state = .failed(error.localizedDescription) }
            throw error
        }
    }
    private func check(_ active: UUID) throws {
        guard active == generation, !Task.isCancelled else { throw CancellationError() }
    }
    private func remember(_ hash: String) {
        defaults.set(hash, forKey: baselineKey)
        lastSaved = Date(); state = .saved; conflictCopy = nil
    }
    private func upload(_ value: BusinessBackup, expected: Int64?, active: UUID) async throws {
        guard let transport else { throw CancellationError() }
        state = .pending
        let saved = try await transport.saveCloudBackup(value, expectedRevision: expected)
        try check(active)
        guard saved.payload.owner == owner, try saved.payload.cloudFingerprint() == value.cloudFingerprint() else { throw CloudBackupError.invalid }
        remember(try saved.payload.cloudFingerprint())
        if let current = try read?(), try current.cloudFingerprint() != saved.payload.cloudFingerprint() {
            state = .pending; repeatPass = true
        }
    }
    /// Explicit conflict resolution only. Both alternatives are kept in local recovery storage.
    func resolve(useCloud: Bool) async {
        guard !running, let owner, let copy = conflictCopy, let read, let apply else { return }
        let active = generation; running = true; repeatPass = false
        defer { if generation == active { running = false; if repeatPass { requestSync() } } }
        do {
            let local = try read().validated(for: owner)
            defaults.set(try local.encoded(), forKey: "reviewNfcGo.cloud.recovery.local." + owner)
            defaults.set(try copy.payload.encoded(), forKey: "reviewNfcGo.cloud.recovery.remote." + owner)
            if useCloud {
                applying = true; defer { applying = false }
                try apply(copy.payload.validated(for: owner)); remember(try copy.payload.cloudFingerprint())
            } else { try await upload(local, expected: copy.revision, active: active) }
        } catch {
            if generation == active {
                state = .failed(error.localizedDescription); conflictCopy = nil
                // Fetch a fresh revision; never force an update over another device's save.
                repeatPass = true
            }
        }
    }
}
