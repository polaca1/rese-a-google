#if os(iOS)
import Foundation
import Combine
import UIKit
import Minimuxer
import SideSign

@MainActor
final class WatchBetaController: ObservableObject {
    @Published private(set) var report = WatchBetaReport()
    @Published private(set) var running = false
    @Published private(set) var watchCount = 0
    @Published var selection = 0 {
        didSet { if selection != oldValue { report.invalidateProfile() } }
    }
    @Published private(set) var appIDs: [ALTAppID] = []
    @Published var selectedAppID = "" {
        didSet { if selectedAppID != oldValue { report.invalidateProfile() } }
    }
    private var identifiers: [String] = []
    private var task: Task<Void, Never>?

    var canPrepareProfile: Bool { !running && identifiers.indices.contains(selection) && report.status(.discovery) == .passed }

    func detect() {
        guard !running else { return }
        report = WatchBetaReport(); identifiers = []; watchCount = 0; selection = 0
        running = true
        task = Task {
            defer { running = false }
            report.set(.connection, .running)
            guard minimuxer.core.isPairingFileLoaded else {
                fail(.connection, .connectionUnavailable); return
            }
            do {
                let found = try await readRegistry()
                try Task.checkCancellation()
                guard WatchBetaValidation.validRegistry(found) else { fail(.discovery, .discoveryFailed); return }
                guard !found.isEmpty else { report.pairedWatchCount = 0; fail(.discovery, .noWatch); return }
                identifiers = found; watchCount = found.count; report.pairedWatchCount = found.count
                report.set(.discovery, .passed)
                let team = try await AuthManager.shared.getAuthenticatedTeam()
                let session = try await AuthManager.shared.getAuthenticatedSession()
                appIDs = try await ALTAppleAPI.shared.fetchAppIDs(for: team, session: session)
                report.freeAccount = team.type == .free
                let runtimeID = Bundle.main.bundleIdentifier ?? ""
                selectedAppID = appIDs.contains(where: { $0.bundleIdentifier == runtimeID }) ? runtimeID : ""
            } catch is CancellationError { fail(.discovery, .cancelled) }
            catch {
                let stage: WatchBetaStage = report.status(.connection) == .passed ? .discovery : .connection
                fail(stage, stage == .connection ? .connectionUnavailable : .discoveryFailed)
            }
        }
    }

    func prepareProfile() {
        guard canPrepareProfile else { return }
        let selected = identifiers[selection]
        report.issue = nil; report.profileDiagnostic = nil; report.set(.profile, .pending); report.set(.account, .running)
        running = true
        task = Task {
            defer { running = false }
            do {
                guard AuthManager.shared.isAuthenticated else { fail(.account, .accountUnavailable); return }
                let team = try await AuthManager.shared.getAuthenticatedTeam()
                let session = try await AuthManager.shared.getAuthenticatedSession()
                try Task.checkCancellation()
                report.freeAccount = team.type == .free
                report.set(.account, .passed)
                let fresh = try await readRegistry()
                report.set(.discovery, .passed)
                try Task.checkCancellation()
                guard fresh.contains(selected) else { fail(.discovery, .watchChanged); identifiers = []; return }
                // Use a portal ID explicitly selected from this account; never guess or create one.
                let bundle = selectedAppID
                guard appIDs.contains(where: { $0.bundleIdentifier == bundle }) else {
                    fail(.profile, .invalidProfile); return
                }
                report.set(.profile, .running)
                let profile = try await ALTAppleAPI.shared.prepareWatchBetaProfile(
                    watchIdentifier: selected, bundleIdentifier: bundle, team: team, session: session)
                try Task.checkCancellation()
                guard WatchBetaValidation.validProfile(platforms: profile.watchBetaPlatforms,
                    bundle: profile.bundleIdentifier, expectedBundle: bundle,
                    team: profile.teamIdentifier, expectedTeam: team.identifier,
                    devices: profile.deviceIDs, selectedWatch: selected,
                    expires: profile.expirationDate, certificateCount: profile.certificates.count) else {
                    fail(.profile, .invalidProfile); return
                }
                // Profile exists only in memory. This is not a signed or installed Watch app.
                report.set(.profile, .passed)
            } catch is CancellationError { fail(.profile, .cancelled) }
            catch let error as WatchBetaProfileFailure {
                if let operation = WatchBetaProfileDiagnostic.Operation(rawValue: error.operation.rawValue),
                   let kind = WatchBetaProfileDiagnostic.Kind(rawValue: error.kind.rawValue) {
                    report.profileDiagnostic = WatchBetaProfileDiagnostic(operation: operation, kind: kind, code: error.code)
                }
                fail(.profile, .profileRequestFailed)
            }
            catch {
                if report.status(.discovery) == .running {
                    fail(.discovery, .discoveryFailed)
                } else {
                    let stage: WatchBetaStage = report.status(.account) == .passed ? .profile : .account
                    fail(stage, stage == .account ? .accountUnavailable : .profileRequestFailed)
                }
            }
        }
    }

    private func readRegistry() async throws -> [String] {
        try await WatchBetaLocalSession.run(
            turnOff: { _ = await CellularRefreshManager.shared.turnOffDataIfNeeded() },
            turnOn: { _ = await CellularRefreshManager.shared.turnOnDataIfNeeded(addOnDelay: 2.0) },
            operation: {
                try await ensureMinimuxerReady()
                try Task.checkCancellation()
                self.report.set(.connection, .passed)
                self.report.set(.discovery, .running)
                return try await minimuxer.core.fetchPairedWatchIdentifiers()
            })
    }

    @Published private(set) var importedName: String?
    @Published private(set) var installMessage: String?
    private var importDirectory: URL?
    private var importedBundle: URL?

    func importIPA(_ url: URL) {
        guard !running else { return }
        running = true
        task = Task {
            defer { running = false }
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            clearImport()
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            do {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                let app = try await Task.detached { try WatchBetaImport.unpack(url, into: directory) }.value
                try Task.checkCancellation()
                importDirectory = directory; importedBundle = app
                let info = NSDictionary(contentsOf: app.appendingPathComponent("Info.plist"))
                importedName = info?["CFBundleDisplayName"] as? String ?? app.deletingPathExtension().lastPathComponent
                installMessage = "App preparada. Instalar solicita un perfil para su App ID existente y utiliza tu certificado actual."
                report.set(.installation, .pending); report.physicalInstallationVerified = false
            } catch {
                try? FileManager.default.removeItem(at: directory)
                installMessage = "Elige un IPA que contenga una sola app de watchOS sin extensiones. Archivos no válidos o demasiado grandes se rechazan."
            }
        }
    }

    func installImportedApp() {
        guard canPrepareProfile, let app = importedBundle, watchCount == 1 else { return }
        let selected = identifiers[selection]
        report.invalidateProfile(); report.set(.installation, .pending)
        running = true
        task = Task {
            defer { running = false }
            do {
                guard let certificate = CertificateManager.shared.activeCertificate else {
                    installMessage = "Inicia sesión y renueva SideStore primero para disponer de tu certificado de firma."; return
                }
                let team = try await AuthManager.shared.getAuthenticatedTeam()
                let session = try await AuthManager.shared.getAuthenticatedSession()
                let info = NSDictionary(contentsOf: app.appendingPathComponent("Info.plist"))
                guard let bundle = info?["CFBundleIdentifier"] as? String else { throw WatchBetaImportError.invalidArchive }
                report.set(.profile, .running)
                let profile = try await ALTAppleAPI.shared.prepareWatchBetaProfile(watchIdentifier: selected,
                    bundleIdentifier: bundle, team: team, session: session)
                guard WatchBetaValidation.validProfile(platforms: profile.watchBetaPlatforms, bundle: profile.bundleIdentifier,
                    expectedBundle: bundle, team: profile.teamIdentifier, expectedTeam: team.identifier,
                    devices: profile.deviceIDs, selectedWatch: selected, expires: profile.expirationDate,
                    certificateCount: profile.certificates.count) else { fail(.profile, .invalidProfile); return }
                report.set(.profile, .passed)
                installMessage = "Firmando la app…"
                try Task.checkCancellation()
                try await ALTSigner(team: team, certificate: certificate.certificate).signApp(at: app, provisioningProfiles: [profile])
                try Task.checkCancellation()
                report.set(.installation, .running); installMessage = "Enviando al Watch. Mantén el reloj desbloqueado y cerca."
                try await WatchBetaLocalSession.run(
                    turnOff: { _ = await CellularRefreshManager.shared.turnOffDataIfNeeded() },
                    turnOn: { _ = await CellularRefreshManager.shared.turnOnDataIfNeeded(addOnDelay: 2.0) },
                    operation: {
                        try await ensureMinimuxerReady()
                        try await minimuxer.core.installWatchBundle(at: app, watchIdentifier: selected)
                    })
                report.set(.installation, .passed)
                installMessage = "watchOS ha confirmado la instalación. Comprueba que la app abre en el reloj. La renovación autónoma todavía no está implementada."
            } catch let error as WatchBetaProfileFailure {
                if let operation = WatchBetaProfileDiagnostic.Operation(rawValue: error.operation.rawValue),
                   let kind = WatchBetaProfileDiagnostic.Kind(rawValue: error.kind.rawValue) {
                    report.profileDiagnostic = WatchBetaProfileDiagnostic(operation: operation, kind: kind, code: error.code)
                }
                fail(.profile, .profileRequestFailed)
                installMessage = "No se ha enviado la app: Apple no entregó el perfil. El IPA debe usar un App ID ya registrado en tu cuenta."
            } catch is CancellationError { fail(.installation, .cancelled) }
            catch {
                fail(.installation, .installationFailed)
                installMessage = "No se completó la firma o instalación. Esta beta requiere emparejamiento TCP, un único Watch enlazado y un perfil de watchOS válido."
            }
        }
    }

    private func clearImport() {
        if let importDirectory { try? FileManager.default.removeItem(at: importDirectory) }
        importDirectory = nil; importedBundle = nil; importedName = nil; installMessage = nil
    }

    func cancel() { task?.cancel() }
    private func fail(_ stage: WatchBetaStage, _ issue: WatchBetaIssue) {
        report.set(stage, .failed); report.issue = issue
        for pending in WatchBetaStage.allCases where report.status(pending) == .running { report.set(pending, .pending) }
    }
}
#endif

#if os(iOS)
import Foundation
import SideSign

enum WatchBetaImportError: Error { case invalidArchive, noSingleWatchApp, unsupportedExtensions }

/// Untrusted IPA extraction is restricted before writing anything outside a new temp dir.
enum WatchBetaImport {
    static func unpack(_ ipa: URL, into directory: URL) throws -> URL {
        let archive = try Archive.Reader.open(at: ipa)
        let entries = try archive.entries()
        guard !entries.isEmpty, entries.count <= 20000 else { throw WatchBetaImportError.invalidArchive }
        var total: Int64 = 0
        var names = Set<String>()
        for entry in entries {
            let path = entry.filename
            guard WatchBetaValidation.safeArchiveEntry(name: path, size: entry.uncompressedSize,
                      attributes: entry.externalAttributes), names.insert(path).inserted else {
                throw WatchBetaImportError.invalidArchive
            }
            total += entry.uncompressedSize
            guard total <= 300_000_000 else { throw WatchBetaImportError.invalidArchive }
        }
        let fm = FileManager.default
        try fm.unzipArchive(at: ipa, to: directory)
        guard let enumerator = fm.enumerator(at: directory, includingPropertiesForKeys: nil) else { throw WatchBetaImportError.invalidArchive }
        var watches: [URL] = []
        for case let item as URL in enumerator where item.pathExtension == "app" {
            let infoURL = item.appendingPathComponent("Info.plist")
            guard let info = NSDictionary(contentsOf: infoURL) as? [String: Any] else { continue }
            if (info["CFBundleSupportedPlatforms"] as? [String])?.contains("WatchOS") == true {
                watches.append(item)
            }
        }
        guard watches.count == 1 else { throw WatchBetaImportError.noSingleWatchApp }
        // Each extension needs its own existing ID/profile; never silently sign with the host profile.
        let nested = fm.enumerator(at: watches[0], includingPropertiesForKeys: nil)
        while let item = nested?.nextObject() as? URL {
            if ["appex", "app"].contains(item.pathExtension) { throw WatchBetaImportError.unsupportedExtensions }
        }
        return watches[0]
    }
}
#endif

#if os(iOS)
/// Persist signed Watch components before installing the phone host. A self-update
/// can terminate this process; only an acknowledged host install activates its jobs.
@MainActor
final class WatchPackageCoordinator: ObservableObject {
    static let shared = WatchPackageCoordinator()
    @Published private(set) var message: String?
    private var working = false
    private var observer: NSObjectProtocol?
    private struct Job: Codable {
        var hostBundle: String
        var hostVersion: String
        var hostBuild: String
        var ready: Bool
        var apps: [String]
    }
    private var root: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AutomaticWatchJobs", isDirectory: true)
    }

    func start() {
        guard observer == nil else { return }
        observer = NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification,
            object: nil, queue: .main) { _ in Task { @MainActor in self.runPending() } }
        runPending()
    }

    func prepare(host: URL, team: ALTTeam, certificate: ALTCertificate) async throws {
        let fm = FileManager.default
        let directory = host.appendingPathComponent("Watch", isDirectory: true)
        guard fm.fileExists(atPath: directory.path) else { return }
        let apps = try fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "app" }
        guard !apps.isEmpty else { return }
        guard apps.count <= 8 else { throw WatchBetaImportError.invalidArchive }
        let session = try await AuthManager.shared.getAuthenticatedSession()
        // Network restoration is mandatory before contacting Apple.
        let watches = try await WatchBetaLocalSession.run(
            turnOff: { _ = await CellularRefreshManager.shared.turnOffDataIfNeeded() },
            turnOn: { _ = await CellularRefreshManager.shared.turnOnDataIfNeeded(addOnDelay: 2) },
            operation: {
                try await ensureMinimuxerReady()
                return try await minimuxer.core.fetchPairedWatchIdentifiers()
            })
        guard watches.count == 1, let watch = watches.first else {
            throw WatchBetaImportError.noSingleWatchApp
        }
        for app in apps {
            let info = NSDictionary(contentsOf: app.appendingPathComponent("Info.plist"))
            guard (info?["CFBundleSupportedPlatforms"] as? [String])?.contains("WatchOS") == true else {
                throw WatchBetaImportError.invalidArchive
            }
            var targets = [app]
            if let nested = fm.enumerator(at: app, includingPropertiesForKeys: nil) {
                for case let target as URL in nested where target.pathExtension == "appex" { targets.append(target) }
            }
            guard targets.count <= 32 else { throw WatchBetaImportError.unsupportedExtensions }
            var profiles: [ALTProvisioningProfile] = []
            for target in targets {
                guard let id = NSDictionary(contentsOf: target.appendingPathComponent("Info.plist"))?["CFBundleIdentifier"] as? String else {
                    throw WatchBetaImportError.invalidArchive
                }
                let profile = try await ALTAppleAPI.shared.prepareWatchBetaProfile(watchIdentifier: watch,
                    bundleIdentifier: id, team: team, session: session)
                guard WatchBetaValidation.validProfile(platforms: profile.watchBetaPlatforms, bundle: profile.bundleIdentifier,
                    expectedBundle: id, team: profile.teamIdentifier, expectedTeam: team.identifier,
                    devices: profile.deviceIDs, selectedWatch: watch, expires: profile.expirationDate,
                    certificateCount: profile.certificates.count) else { throw WatchBetaImportError.invalidArchive }
                profiles.append(profile)
            }
            try await ALTSigner(team: team, certificate: certificate).signApp(at: app, provisioningProfiles: profiles)
        }
        guard let info = NSDictionary(contentsOf: host.appendingPathComponent("Info.plist")),
              let id = info["CFBundleIdentifier"] as? String,
              let version = info["CFBundleShortVersionString"] as? String,
              let build = info["CFBundleVersion"] as? String else { throw WatchBetaImportError.invalidArchive }
        let destination = root.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: destination, withIntermediateDirectories: true)
        do {
            var names: [String] = []
            for (index, app) in apps.enumerated() {
                let name = "\(index).app"
                try fm.copyItem(at: app, to: destination.appendingPathComponent(name))
                names.append(name)
            }
            let job = Job(hostBundle: id, hostVersion: version, hostBuild: build, ready: false, apps: names)
            try JSONEncoder().encode(job).write(to: destination.appendingPathComponent("job.json"), options: .atomic)
        } catch {
            try? fm.removeItem(at: destination)
            throw error
        }
    }

    func hostInstalled(bundle: String, version: String, build: String) {
        for directory in directories() {
            guard var job = read(directory), job.hostBundle == bundle,
                  job.hostVersion == version, job.hostBuild == build else { continue }
            job.ready = true
            try? JSONEncoder().encode(job).write(to: directory.appendingPathComponent("job.json"), options: .atomic)
        }
    }

    private func directories() -> [URL] {
        (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
    }
    private func read(_ directory: URL) -> Job? {
        guard let data = try? Data(contentsOf: directory.appendingPathComponent("job.json")) else { return nil }
        return try? JSONDecoder().decode(Job.self, from: data)
    }

    func runPending() {
        guard !working, UIApplication.shared.applicationState == .active else { return }
        working = true
        Task {
            defer { working = false }
            for directory in directories() {
                guard var job = read(directory) else { continue }
                // A SideStore self-update may have killed the old process before hostInstalled.
                if !job.ready, job.hostBundle == Bundle.main.bundleIdentifier,
                   job.hostVersion == Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
                   job.hostBuild == Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String {
                    job.ready = true
                }
                guard job.ready else { continue }
                do {
                    message = "Instalando el componente de Apple Watch…"
                    try await WatchBetaLocalSession.run(
                        turnOff: { _ = await CellularRefreshManager.shared.turnOffDataIfNeeded() },
                        turnOn: { _ = await CellularRefreshManager.shared.turnOnDataIfNeeded(addOnDelay: 2) },
                        operation: {
                            try await ensureMinimuxerReady()
                            let watches = try await minimuxer.core.fetchPairedWatchIdentifiers()
                            guard watches.count == 1, let watch = watches.first else { throw WatchBetaImportError.noSingleWatchApp }
                            for name in job.apps {
                                guard !name.contains("/"), name.hasSuffix(".app") else { throw WatchBetaImportError.invalidArchive }
                                let app = directory.appendingPathComponent(name)
                                let info = NSDictionary(contentsOf: app.appendingPathComponent("Info.plist"))
                                guard let id = info?["CFBundleIdentifier"] as? String else { throw WatchBetaImportError.invalidArchive }
                                let profile = try ALTProvisioningProfile(data: Data(contentsOf: app.appendingPathComponent("embedded.mobileprovision")))
                                guard WatchBetaValidation.validProfile(platforms: profile.watchBetaPlatforms, bundle: profile.bundleIdentifier,
                                    expectedBundle: id, team: profile.teamIdentifier, expectedTeam: profile.teamIdentifier,
                                    devices: profile.deviceIDs, selectedWatch: watch, expires: profile.expirationDate,
                                    certificateCount: profile.certificates.count) else { throw WatchBetaImportError.invalidArchive }
                                try await minimuxer.core.installWatchBundle(at: app, watchIdentifier: watch)
                            }
                        })
                    try FileManager.default.removeItem(at: directory)
                    message = "watchOS ha confirmado la instalación."
                } catch {
                    message = "La instalación del Watch queda pendiente. Comprueba el perfil, el emparejamiento TCP y que el reloj está desbloqueado y cerca."
                    // Keep the signed package for the next foreground opportunity.
                    break
                }
            }
        }
    }
}
#endif
