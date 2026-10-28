#if os(iOS)
import Foundation
import Combine
import CoreData
import UIKit
import Minimuxer
import SideSign
import SemanticVersion

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
        didSet {
            if selectedAppID != oldValue {
                report.invalidateProfile()
                UserDefaults.standard.set(selectedAppID, forKey: "watchSelectedPortalID")
            }
        }
    }
    private var identifiers: [String] = []
    private var task: Task<Void, Never>?

    var canPrepareProfile: Bool { !running && identifiers.indices.contains(selection) && report.status(.discovery) == .passed && !appIDs.isEmpty }

    func detect() {
        guard !running else { return }
        report = WatchBetaReport(); appIDs = []; identifiers = []; watchCount = 0; selection = 0
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
                let embedded = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision")
                    .flatMap { try? Data(contentsOf: $0) }
                    .flatMap { try? ALTProvisioningProfile(data: $0) }
                appIDs = appIDs.filter { !$0.bundleIdentifier.contains("*") && !$0.bundleIdentifier.isEmpty }
                selectedAppID = WatchBetaValidation.preferredPortalID(available: appIDs.map(\.bundleIdentifier),
                    saved: UserDefaults.standard.string(forKey: "watchSelectedPortalID"), runtime: runtimeID,
                    profileBundle: embedded?.bundleIdentifier, profileTeam: embedded?.teamIdentifier,
                    sessionTeam: team.identifier) ?? ""
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
        report.invalidateProfile(); report.set(.account, .running)
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
                let checks = profile.watchBetaChecks(expectedBundle: bundle, expectedTeam: team.identifier, watch: selected)
                report.profileChecks = checks
                guard checks.valid else { fail(.profile, .invalidProfile); return }
                // Profile exists only in memory. This is not a signed or installed Watch app.
                report.set(.profile, .passed)
                WatchPackageCoordinator.shared.runPending()
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
                let checks = profile.watchBetaChecks(expectedBundle: bundle, expectedTeam: team.identifier, watch: selected)
                report.profileChecks = checks
                guard checks.valid else { fail(.profile, .invalidProfile); return }
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
    @Published fileprivate(set) var nativeOpened = false
    @Published private(set) var profileChecks: WatchBetaProfileChecks?
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
        WatchLaunchBridge.shared.start()
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
                let checks = profile.watchBetaChecks(expectedBundle: id, expectedTeam: team.identifier, watch: watch)
                guard checks.valid else { throw WatchBetaInvalidProfile(checks: checks) }
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
        guard !working, AuthManager.shared.isAuthenticated, UIApplication.shared.applicationState == .active else { return }
        working = true
        Task {
            defer { working = false; BetaUpdateCoordinator.shared.check() }
            for _ in 0..<10 where AppManager.shared.isActivelyManagingAnyApp {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
            guard !AppManager.shared.isActivelyManagingAnyApp else { return }
            profileChecks = nil
            do { try await bootstrapIfNeeded() }
            catch let error as WatchBetaInvalidProfile {
                profileChecks = error.checks
                message = error.checks.message
            }
            catch let error as WatchBetaProfileFailure {
                if let operation = WatchBetaProfileDiagnostic.Operation(rawValue: error.operation.rawValue),
                   let kind = WatchBetaProfileDiagnostic.Kind(rawValue: error.kind.rawValue) {
                    message = WatchBetaProfileDiagnostic(operation: operation, kind: kind, code: error.code).message
                }
            }
            catch { message = "SideStore Watch queda pendiente: Apple debe aceptar un perfil válido del App ID seleccionado." }
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
                    let team = try await AuthManager.shared.getAuthenticatedTeam()
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
                                let checks = profile.watchBetaChecks(expectedBundle: id, expectedTeam: team.identifier, watch: watch)
                                guard checks.valid else { throw WatchBetaInvalidProfile(checks: checks) }
                                try await minimuxer.core.installWatchBundle(at: app, watchIdentifier: watch)
                            }
                        })
                    if job.hostBundle == Bundle.main.bundleIdentifier {
                        UserDefaults.standard.set(job.hostBuild, forKey: "watchBootstrapCompletedBuild")
                    }
                    try FileManager.default.removeItem(at: directory)
                    message = "watchOS ha confirmado la instalación."
                } catch let error as WatchBetaInvalidProfile {
                    profileChecks = error.checks
                    message = error.checks.message
                    break
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

#if os(iOS)
@MainActor
final class BetaUpdateCoordinator {
    static let shared = BetaUpdateCoordinator()
    private var running = false
    private var lastCheck = Date.distantPast
    private let sources: Set<String> = [
        "https://raw.githubusercontent.com/polaca1/rese-a-google/refs/heads/sidestore-watch-source/source-compatible.json",
        "https://raw.githubusercontent.com/polaca1/rese-a-google/refs/heads/sidestore-watch-source/source.json"
    ]
    private func trustedListing() -> StoreApp? {
        let context = DatabaseManager.shared.viewContext
        for address in sources.sorted() {
            guard let url = URL(string: address), let id = try? Source.sourceID(from: url),
                  let source = Source.first(satisfying: NSPredicate(format: "%K == %@", #keyPath(Source.identifier), id), in: context) else { continue }
            if let app = source.apps.first(where: { $0.bundleIdentifier == StoreApp.altstoreAppID }) { return app }
        }
        return nil
    }

    func check() {
        guard !running, UIApplication.shared.applicationState == .active,
              !AppManager.shared.isActivelyManagingAnyApp,
              AuthManager.shared.isAuthenticated,
              Date().timeIntervalSince(lastCheck) > 300,
              UserDefaults.standard.object(forKey: "watchBetaAutomaticUpdates") as? Bool != false else { return }
        let context = DatabaseManager.shared.viewContext
        guard InstalledApp.fetchAltStore(in: context) != nil, trustedListing() != nil else { return }
        running = true; lastCheck = Date()
        AppManager.shared.updateAllSources { result in
            Task { @MainActor in
                guard case .success = result,
                      UIApplication.shared.applicationState == .active,
                      !AppManager.shared.isActivelyManagingAnyApp,
                      AuthManager.shared.isAuthenticated,
                      let current = InstalledApp.fetchAltStore(in: context),
                      let listing = self.trustedListing(),
                      let source = listing._source?.sourceURL.absoluteString, self.sources.contains(source),
                      let latest = listing.latestSupportedVersion,
                      WatchBetaValidation.trustedBetaSource(source, download: latest.downloadURL.absoluteString) else {
                    self.running = false; return
                }
                let currentBuild = Int(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "") ?? 0
                let actualVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
                guard let installedSemantic = SemanticVersion(actualVersion),
                      let offeredSemantic = SemanticVersion(latest.version) else { self.running = false; return }
                let newerBuild = WatchBetaValidation.newerBuild(currentVersion: actualVersion, currentBuild: String(currentBuild),
                    version: latest.version, build: latest.buildVersion)
                guard offeredSemantic > installedSemantic || newerBuild,
                      let window = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene })
                        .flatMap({ $0.windows }).first(where: { $0.isKeyWindow }),
                      var controller = window.rootViewController else { self.running = false; return }
                while true {
                    if let presented = controller.presentedViewController { controller = presented; continue }
                    if let navigation = controller as? UINavigationController, let top = navigation.topViewController { controller = top; continue }
                    if let tab = controller as? UITabBarController, let selected = tab.selectedViewController { controller = selected; continue }
                    break
                }
                guard !(controller is UIAlertController),
                      !String(describing: type(of: controller)).contains("WatchBeta") else { self.running = false; return }
                // Updating an existing installation may retain the official-source relationship.
                // This binary belongs to this variant and the user explicitly added this trusted feed.
                let previous = current.storeApp
                current.storeApp = listing
                do { try context.save() }
                catch { current.storeApp = previous; self.running = false; return }
                AppManager.shared.update(current, to: latest, presentingViewController: controller) { _ in
                    Task { @MainActor in self.running = false }
                }
            }
        }
    }
}
#endif

#if os(iOS)
extension WatchPackageCoordinator {
    private func bootstrapIfNeeded() async throws {
        guard AuthManager.shared.isAuthenticated,
              let payload = Bundle.main.url(forResource: "WatchBootstrap", withExtension: "ipa"),
              let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String,
              UserDefaults.standard.string(forKey: "watchBootstrapCompletedBuild") != build else { return }
        let ownID = Bundle.main.bundleIdentifier ?? ""
        if directories().contains(where: {
            guard let job = read($0) else { return false }
            return job.hostBundle == ownID && job.hostBuild == build
        }) { return }
        let team = try await AuthManager.shared.getAuthenticatedTeam()
        let session = try await AuthManager.shared.getAuthenticatedSession()
        let apps = try await ALTAppleAPI.shared.fetchAppIDs(for: team, session: session)
        var identifier = UserDefaults.standard.string(forKey: "watchSelectedPortalID") ?? ""
        if identifier.isEmpty, let url = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"),
           let profile = try? ALTProvisioningProfile(data: Data(contentsOf: url)),
           profile.teamIdentifier == team.identifier { identifier = profile.bundleIdentifier }
        guard !identifier.isEmpty, !identifier.contains("*"), apps.contains(where: { $0.bundleIdentifier == identifier }),
              let certificate = CertificateManager.shared.activeCertificate else {
            message = "Selecciona un App ID existente en Watch beta y comprueba su perfil. No se creará ninguno nuevo."
            return
        }
        let fm = FileManager.default
        let temporary = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: temporary, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: temporary) }
        let extracted = try WatchBetaImport.unpack(payload, into: temporary)
        let host = temporary.appendingPathComponent("Host.app")
        let watch = host.appendingPathComponent("Watch/SideStoreWatch.app")
        try fm.createDirectory(at: watch.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fm.copyItem(at: extracted, to: watch)
        let plist = watch.appendingPathComponent("Info.plist")
        var info = try PropertyListSerialization.propertyList(from: Data(contentsOf: plist), format: nil) as! [String: Any]
        info["CFBundleIdentifier"] = identifier
        info["WKCompanionAppBundleIdentifier"] = ownID
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0).write(to: plist)
        let hostInfo: [String: Any] = [
            "CFBundleIdentifier": ownID, "CFBundleVersion": build,
            "CFBundleShortVersionString": Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        ]
        try PropertyListSerialization.data(fromPropertyList: hostInfo, format: .xml, options: 0)
            .write(to: host.appendingPathComponent("Info.plist"))
        try await prepare(host: host, team: team, certificate: certificate.certificate)
    }
}
#endif

#if os(iOS)
@preconcurrency import WatchConnectivity
@MainActor
final class WatchLaunchBridge: NSObject, WCSessionDelegate {
    static let shared = WatchLaunchBridge()
    func start() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {}
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}
    nonisolated func sessionDidDeactivate(_ session: WCSession) { session.activate() }
    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any],
        replyHandler: @escaping ([String: Any]) -> Void) {
        guard message["sideStoreWatchLaunch"] as? Bool == true else { replyHandler(["accepted": false]); return }
        let probe = message["localService"] as? String ?? ""
        replyHandler(["accepted": true])
        Task { @MainActor in WatchPackageCoordinator.shared.confirmLaunch(probe: probe) }
    }
}
extension WatchPackageCoordinator {
    func confirmLaunch(probe: String) {
        nativeOpened = true
        let allowed = ["Puerto accesible", "No accesible", "Sin respuesta", "Comprobando…"]
        message = "SideStore se ha abierto en el Watch." + (allowed.contains(probe) ? " Servicio local: \(probe)." : "")
    }
}
#endif

#if os(iOS)
private extension ALTProvisioningProfile {
    func watchBetaChecks(expectedBundle: String, expectedTeam: String, watch: String) -> WatchBetaProfileChecks {
        WatchBetaValidation.profileChecks(platforms: watchBetaPlatforms, bundle: bundleIdentifier,
            expectedBundle: expectedBundle, team: teamIdentifier, expectedTeam: expectedTeam,
            devices: deviceIDs, selectedWatch: watch, expires: expirationDate, certificateCount: certificates.count)
    }
}
#endif
