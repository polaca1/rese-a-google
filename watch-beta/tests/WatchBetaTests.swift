import Foundation

@main struct WatchBetaTests {
    @MainActor static func main() async throws {
        var count = 0
        func check(_ name: String, _ result: Bool) { precondition(result, name); count += 1; print("PASS: \(name)") }
        check("archive traversal rejected", !WatchBetaValidation.safeArchiveEntry(name: "Payload/../../secret", size: 1, attributes: 0))
        check("absolute archive paths rejected", !WatchBetaValidation.safeArchiveEntry(name: "/secret", size: 1, attributes: 0))
        check("archive symlink rejected", !WatchBetaValidation.safeArchiveEntry(name: "Payload/link", size: 1, attributes: 0o120777 << 16))
        check("archive large entry rejected", !WatchBetaValidation.safeArchiveEntry(name: "Payload/app", size: 100_000_001, attributes: 0))
        check("normal app resource accepted", WatchBetaValidation.safeArchiveEntry(name: "Payload/Watch.app/main", size: 1024, attributes: 0o100755 << 16))
        let now = Date(timeIntervalSince1970: 1000)
        func valid(platforms: [String] = ["watchOS"], bundle: String = "test.watch", team: String = "TEAM",
                   devices: [String] = ["WATCH-ID"], expires: Date = Date(timeIntervalSince1970: 2000), certs: Int = 1) -> Bool {
            WatchBetaValidation.validProfile(platforms: platforms, bundle: bundle, expectedBundle: "test.watch",
                team: team, expectedTeam: "TEAM", devices: devices, selectedWatch: "WATCH-ID",
                expires: expires, certificateCount: certs, now: now)
        }
        check("matching Watch profile", valid())
        check("iPhone profile rejected", !valid(platforms: ["iOS"]))
        check("missing platform rejected", !valid(platforms: []))
        check("wrong bundle rejected", !valid(bundle: "other.watch"))
        check("wrong team rejected", !valid(team: "OTHER"))
        check("wrong Watch rejected", !valid(devices: ["OTHER"]))
        check("expired rejected", !valid(expires: now))
        check("unsigned profile rejected", !valid(certs: 0))
        check("empty registry allowed", WatchBetaValidation.validRegistry([]))
        check("duplicate registry rejected", !WatchBetaValidation.validRegistry(["A", "A"]))
        check("invalid identifier rejected", !WatchBetaValidation.validRegistry(["A\nSECRET"]))
        check("oversized registry rejected", !WatchBetaValidation.validRegistry((0...32).map(String.init)))
        check("oversized identifier rejected", !WatchBetaValidation.validRegistry([String(repeating: "A", count: 129)]))
        var report = WatchBetaReport()
        report.set(.discovery, .passed); report.pairedWatchCount = 1; report.freeAccount = true
        report.issue = .profileRequestFailed; report.set(.profile, .failed)
        let decoded = try JSONDecoder().decode(WatchBetaReport.self, from: Data(report.export().utf8))
        check("report round trip", decoded == report)
        check("profile failure never claims install", !decoded.physicalInstallationVerified && decoded.status(.installation) == .pending)
        check("no fake renewal", !decoded.renewalVerified && decoded.status(.renewal) == .pending)
        let object = try JSONSerialization.jsonObject(with: Data(report.export().utf8)) as! [String: Any]
        check("report fields whitelisted", Set(object.keys).isSubset(of: ["schema", "beta", "statuses", "pairedWatchCount", "freeAccount", "issue", "profileDiagnostic", "physicalInstallationVerified", "renewalVerified"]))
        report.profileDiagnostic = WatchBetaProfileDiagnostic(operation: .registerDevice, kind: .appleAPI, code: 1234)
        let detailed = try JSONDecoder().decode(WatchBetaReport.self, from: Data(report.export().utf8))
        check("preserves exact operation and numeric code", detailed.profileDiagnostic == report.profileDiagnostic)
        check("diagnostic contains no raw message field", !report.export().contains("rawMessage"))
        let diagnosticObject = try JSONSerialization.jsonObject(with: Data(report.export().utf8)) as! [String: Any]
        let fields = diagnosticObject["profileDiagnostic"] as! [String: Any]
        check("diagnostic fields whitelisted", Set(fields.keys) == ["operation", "kind", "code"])
        check("explains missing existing ID", WatchBetaProfileDiagnostic(operation: .listAppIDs, kind: .existingAppIDMissing, code: nil).message.contains("No se ha creado otro"))
        check("numeric code visible", report.profileDiagnostic!.message.contains("1234"))
        report.set(.profile, .passed); report.invalidateProfile()
        check("changing Watch clears diagnostic", report.profileDiagnostic == nil)
        check("changing Watch invalidates previous profile", report.status(.profile) == .pending && report.issue == nil)
        var events: [String] = []
        let value = try await WatchBetaLocalSession.run(turnOff: { events.append("off") }, turnOn: { events.append("on") }, operation: { events.append("operation"); return 42 })
        check("preserves result after network restoration", value == 42)
        check("restores data after success", events == ["off", "operation", "on"])
        events = []
        struct ExpectedFailure: Error {}
        do {
            let _: Int = try await WatchBetaLocalSession.run(turnOff: { events.append("off") }, turnOn: { events.append("on") }, operation: { events.append("operation"); throw ExpectedFailure() })
            preconditionFailure("Expected operation failure")
        } catch is ExpectedFailure {}
        check("restores data after failure", events == ["off", "operation", "on"])
        events = []
        let cancelled = Task { @MainActor in
            try await WatchBetaLocalSession.run(turnOff: { events.append("off") }, turnOn: { events.append("on") }, operation: { events.append("operation"); return 1 })
        }
        cancelled.cancel()
        do { _ = try await cancelled.value; preconditionFailure("Expected cancellation") } catch is CancellationError {}
        check("restores data on cancellation without running operation", events == ["off", "on"])
        print("Watch beta: \(count) checks passed")
    }
}
