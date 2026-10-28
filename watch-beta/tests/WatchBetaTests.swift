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
        check("portal ID follows embedded signature, not unchanged Info.plist", WatchBetaValidation.preferredPortalID(
            available: ["signed.id"], saved: nil, runtime: "runtime.id",
            profileBundle: "signed.id", profileTeam: "TEAM", sessionTeam: "TEAM") == "signed.id")
        check("no random ID fallback", WatchBetaValidation.preferredPortalID(available: ["other.id"],
            saved: nil, runtime: "runtime.id", profileBundle: nil, profileTeam: nil, sessionTeam: "TEAM") == nil)
        check("other account profile rejected", WatchBetaValidation.preferredPortalID(available: ["signed.id"],
            saved: nil, runtime: "runtime.id", profileBundle: "signed.id", profileTeam: "OTHER", sessionTeam: "TEAM") == nil)
        check("explicit saved portal choice respected", WatchBetaValidation.preferredPortalID(available: ["saved.id", "signed.id"],
            saved: "saved.id", runtime: "signed.id", profileBundle: "signed.id", profileTeam: "TEAM", sessionTeam: "TEAM") == "saved.id")
        check("wildcard cannot become a Watch bundle ID", WatchBetaValidation.preferredPortalID(available: ["*"],
            saved: "*", runtime: "*", profileBundle: "*", profileTeam: "TEAM", sessionTeam: "TEAM") == nil)
        check("newer same-version build offered", WatchBetaValidation.newerBuild(currentVersion: "0.7.0", currentBuild: "708", version: "0.7.0", build: "709"))
        check("build downgrade rejected", !WatchBetaValidation.newerBuild(currentVersion: "0.7.0", currentBuild: "709", version: "0.7.0", build: "708"))
        check("equal build not reinstalled", !WatchBetaValidation.newerBuild(currentVersion: "0.7.0", currentBuild: "709", version: "0.7.0", build: "709"))
        check("cross-version build comparison rejected", !WatchBetaValidation.newerBuild(currentVersion: "8.0", currentBuild: "1", version: "0.7.0", build: "900"))
        check("untrusted release cannot self-update", !WatchBetaValidation.trustedBetaSource(
            "https://raw.githubusercontent.com/polaca1/rese-a-google/refs/heads/sidestore-watch-source/source.json",
            download: "https://github.com/other/repo/releases/download/sidestore-watch-beta-709/a.ipa"))
        let now = Date(timeIntervalSince1970: 1000)
        func valid(platforms: [String] = ["watchOS"], bundle: String = "test.watch", team: String = "TEAM",
                   devices: [String] = ["WATCH-ID"], expires: Date = Date(timeIntervalSince1970: 2000), certs: Int = 1) -> Bool {
            WatchBetaValidation.validProfile(platforms: platforms, bundle: bundle, expectedBundle: "test.watch",
                team: team, expectedTeam: "TEAM", devices: devices, selectedWatch: "WATCH-ID",
                expires: expires, certificateCount: certs, now: now)
        }
        check("matching Watch profile", valid())
        check("iOS family profile including selected Watch accepted", valid(platforms: ["iOS"]))
        check("modern shared iOS family accepted", valid(platforms: ["iOS", "xrOS", "visionOS"]))
        check("iOS phone-only profile rejected", !valid(platforms: ["iOS"], devices: ["PHONE-ID"]))
        check("iOS family does not bypass exact bundle", !valid(platforms: ["iOS"], bundle: "other.watch"))
        check("iOS family does not bypass team", !valid(platforms: ["iOS"], team: "OTHER"))
        check("iOS family does not bypass expiry", !valid(platforms: ["iOS"], expires: now))
        check("iOS family does not bypass certificate", !valid(platforms: ["iOS"], certs: 0))
        check("tvOS profile rejected", !valid(platforms: ["tvOS"]))
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
        var regression = WatchBetaReport()
        check("before registry failure belongs to connection", regression.detectionFailureStage == .connection)
        regression.set(.connection, .passed)
        check("registry failure belongs to discovery", regression.detectionFailureStage == .discovery)
        regression.set(.discovery, .passed); regression.pairedWatchCount = 1
        regression.set(.account, .running)
        check("account failure after Watch discovery not mislabeled", regression.detectionFailureStage == .account)
        regression.set(regression.detectionFailureStage, .failed)
        check("detected Watch preserved after account failure", regression.status(.discovery) == .passed && regression.pairedWatchCount == 1)
        let suite = "WatchBetaTests." + UUID().uuidString
        let settings = UserDefaults(suiteName: suite)!
        defer { settings.removePersistentDomain(forName: suite) }
        settings.set(true, forKey: "useOnDeviceAnisette")
        settings.set("https://previous.example", forKey: "menuAnisetteURL")
        WatchBetaAnisettePreset.apply(to: settings)
        check("update migrates previous on-device mode", !settings.bool(forKey: "useOnDeviceAnisette"))
        check("update selects requested server", settings.string(forKey: "menuAnisetteURL") == "https://mac-ani.jkcoxson.com")
        check("server activation scheduled once", settings.bool(forKey: WatchBetaAnisettePreset.pendingKey))
        settings.set(true, forKey: "useOnDeviceAnisette")
        settings.set("https://chosen.example", forKey: "menuAnisetteURL")
        settings.set(false, forKey: WatchBetaAnisettePreset.pendingKey)
        WatchBetaAnisettePreset.apply(to: settings)
        check("subsequent user mode choice preserved", settings.bool(forKey: "useOnDeviceAnisette"))
        check("subsequent user server choice preserved", settings.string(forKey: "menuAnisetteURL") == "https://chosen.example")
        check("preset is not reapplied on every launch", !settings.bool(forKey: WatchBetaAnisettePreset.pendingKey))
        var report = WatchBetaReport()
        report.set(.discovery, .passed); report.pairedWatchCount = 1; report.freeAccount = true
        report.issue = .profileRequestFailed; report.set(.profile, .failed)
        let decoded = try JSONDecoder().decode(WatchBetaReport.self, from: Data(report.export().utf8))
        check("report round trip", decoded == report)
        check("profile failure never claims install", !decoded.physicalInstallationVerified && decoded.status(.installation) == .pending)
        check("no fake renewal", !decoded.renewalVerified && decoded.status(.renewal) == .pending)
        let object = try JSONSerialization.jsonObject(with: Data(report.export().utf8)) as! [String: Any]
        check("report fields whitelisted", Set(object.keys).isSubset(of: ["schema", "beta", "statuses", "pairedWatchCount", "freeAccount", "issue", "profileDiagnostic", "accountDiagnostic", "profileChecks", "automaticProfileChecks", "physicalInstallationVerified", "renewalVerified"]))
        report.profileDiagnostic = WatchBetaProfileDiagnostic(operation: .registerDevice, kind: .appleAPI, code: 1234)
        let detailed = try JSONDecoder().decode(WatchBetaReport.self, from: Data(report.export().utf8))
        check("preserves exact operation and numeric code", detailed.profileDiagnostic == report.profileDiagnostic)
        check("diagnostic contains no raw message field", !report.export().contains("rawMessage"))
        let diagnosticObject = try JSONSerialization.jsonObject(with: Data(report.export().utf8)) as! [String: Any]
        let fields = diagnosticObject["profileDiagnostic"] as! [String: Any]
        check("diagnostic fields whitelisted", Set(fields.keys) == ["operation", "kind", "code"])
        check("explains missing existing ID", WatchBetaProfileDiagnostic(operation: .listAppIDs, kind: .existingAppIDMissing, code: nil).message.contains("No se ha creado otro"))
        check("numeric code visible", report.profileDiagnostic!.message.contains("1234"))
        let rejected = WatchBetaValidation.profileChecks(platforms: ["iOS", "PRIVATE-PLATFORM"],
            bundle: "test.watch", expectedBundle: "test.watch", team: "TEAM", expectedTeam: "TEAM",
            devices: ["PHONE-ID"], selectedWatch: "WATCH-ID", expires: now, certificateCount: 0, now: now)
        check("diagnostic distinguishes missing Watch", !rejected.containsWatch && rejected.bundleMatches && rejected.teamMatches)
        check("diagnostic distinguishes expiry and missing certificate", !rejected.notExpired && !rejected.hasCertificate)
        check("iOS family categorized without requiring watchOS label", rejected.platformCompatible)
        check("missing Watch explained", rejected.message.contains("no incluye este Watch"))
        report.profileChecks = rejected; report.automaticProfileChecks = rejected
        let validationJSON = report.export()
        check("raw platform values never exported", !validationJSON.contains("PRIVATE-PLATFORM"))
        check("comparison input IDs never exported", !validationJSON.contains("WATCH-ID") && !validationJSON.contains("PHONE-ID")
            && !validationJSON.contains("test.watch") && !validationJSON.contains("TEAM"))
        let validationDecoded = try JSONDecoder().decode(WatchBetaReport.self, from: Data(validationJSON.utf8))
        check("manual and automatic validation survive export", validationDecoded.profileChecks == rejected && validationDecoded.automaticProfileChecks == rejected)
        let validationObject = try JSONSerialization.jsonObject(with: Data(validationJSON.utf8)) as! [String: Any]
        let validationFields = validationObject["profileChecks"] as! [String: Any]
        check("validation fields whitelisted", Set(validationFields.keys) == ["platforms", "bundleMatches", "teamMatches", "containsWatch", "notExpired", "hasCertificate"])
        report.accountDiagnostic = WatchBetaProfileDiagnostic(operation: .fetchAnisette, kind: .anisette, code: -80046)
        let accountDecoded = try JSONDecoder().decode(WatchBetaReport.self, from: Data(report.export().utf8))
        check("account diagnostic identifies Anisette instead of Watch discovery", accountDecoded.accountDiagnostic == report.accountDiagnostic)
        report.set(.profile, .passed); report.invalidateProfile()
        check("changing Watch clears diagnostic", report.profileDiagnostic == nil)
        check("changing Watch clears old validation", report.profileChecks == nil && report.automaticProfileChecks == nil)
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
