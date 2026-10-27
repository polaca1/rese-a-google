import Foundation

@main struct WatchBetaTests {
    static func main() throws {
        var count = 0
        func check(_ name: String, _ result: Bool) { precondition(result, name); count += 1; print("PASS: \(name)") }
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
        check("report fields whitelisted", Set(object.keys).isSubset(of: ["schema", "beta", "statuses", "pairedWatchCount", "freeAccount", "issue", "physicalInstallationVerified", "renewalVerified"]))
        report.set(.profile, .passed); report.invalidateProfile()
        check("changing Watch invalidates previous profile", report.status(.profile) == .pending && report.issue == nil)
        print("Watch beta: \(count) checks passed")
    }
}
