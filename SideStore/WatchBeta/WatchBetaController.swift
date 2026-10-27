#if os(iOS)
import Foundation
import Combine
import Minimuxer
import SideSign

@MainActor
final class WatchBetaController: ObservableObject {
    @Published private(set) var report = WatchBetaReport()
    @Published private(set) var running = false
    @Published private(set) var watchCount = 0
    @Published var selection = 0
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
            switch await minimuxer.core.isReady(withNetworkCheck: true, withDDIMountCheck: false) {
            case .success(let ready):
                guard ready else { fail(.connection, .connectionUnavailable); return }
            case .failure: fail(.connection, .connectionUnavailable); return
            }
            guard !Task.isCancelled else { fail(.connection, .cancelled); return }
            report.set(.connection, .passed); report.set(.discovery, .running)
            do {
                let found = try await minimuxer.core.fetchPairedWatchIdentifiers()
                try Task.checkCancellation()
                guard WatchBetaValidation.validRegistry(found) else { fail(.discovery, .discoveryFailed); return }
                guard !found.isEmpty else { report.pairedWatchCount = 0; fail(.discovery, .noWatch); return }
                identifiers = found; watchCount = found.count; report.pairedWatchCount = found.count
                report.set(.discovery, .passed)
            } catch is CancellationError { fail(.discovery, .cancelled) }
            catch { fail(.discovery, .discoveryFailed) }
        }
    }

    func prepareProfile() {
        guard canPrepareProfile else { return }
        let selected = identifiers[selection]
        report.issue = nil; report.set(.profile, .pending); report.set(.account, .running)
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
                let fresh = try await minimuxer.core.fetchPairedWatchIdentifiers()
                try Task.checkCancellation()
                guard fresh.contains(selected) else { fail(.discovery, .watchChanged); identifiers = []; return }
                // Stable per-team ID makes repeated explicit tests idempotent at the App ID level.
                let bundle = "com.polaca1.watchbetaprobe." + team.identifier.lowercased() + ".watch"
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
            catch {
                let stage: WatchBetaStage = report.status(.account) == .passed ? .profile : .account
                fail(stage, stage == .account ? .accountUnavailable : .profileRequestFailed)
            }
        }
    }

    func cancel() { task?.cancel() }
    private func fail(_ stage: WatchBetaStage, _ issue: WatchBetaIssue) {
        report.set(stage, .failed); report.issue = issue
        for pending in WatchBetaStage.allCases where report.status(pending) == .running { report.set(pending, .pending) }
    }
}
#endif
