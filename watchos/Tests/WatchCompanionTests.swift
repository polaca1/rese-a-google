import Foundation
@main struct WatchCompanionTests {
    static func main() throws {
        var checks = 0
        func check(_ value: @autoclosure () -> Bool, _ label: String) { precondition(value(), label); checks += 1 }
        let empty = WatchCompanionSnapshot()
        check(!empty.isAvailable && empty.balanceCents == nil && empty.nextVisit == nil, "No account does not invent a zero balance")
        let now = Date()
        let item = WatchCompanionBusiness(id: UUID(), name: "Café & Bar", address: "Madrid", latitude: 40.4, longitude: -3.7, visitDate: now, completed: false, arrived: false, incomeCents: 1500)
        let value = WatchCompanionSnapshot(generatedAt: now, ownerID: String(repeating: "b", count: 64), balanceCents: -500, dayIncomeCents: 1500, cardsSold: 1, businesses: [item])
        let restored = try WatchCompanionSnapshot.decode(JSONEncoder().encode(value))
        check(restored == value && restored.isAvailable && restored.balanceCents == -500, "Exact real account data and negative balance survive transfer")
        check(value.nextVisit?.id == item.id, "Next pending visit is available")
        let maps = URLComponents(url: item.mapsURL!, resolvingAgainstBaseURL: false)!
        check(maps.host == "maps.apple.com" && maps.queryItems?.first(where: { $0.name == "q" })?.value == item.name, "Directions preserve business name and coordinates")
        var bad = value; bad.businesses.append(item)
        do { _ = try bad.validated(); preconditionFailure("Duplicate accepted") } catch { checks += 1 }
        bad = value; bad.businesses[0].latitude = 100
        do { _ = try bad.validated(); preconditionFailure("Bad location accepted") } catch { checks += 1 }
        bad = value; bad.ownerID = nil
        do { _ = try bad.validated(); preconditionFailure("Data without owner accepted") } catch { checks += 1 }
        bad = value; bad.ownerID = "email@example.invalid"
        do { _ = try bad.validated(); preconditionFailure("Email accepted as anonymous account token") } catch { checks += 1 }
        bad = value; bad.balanceCents = Int64.min
        do { _ = try bad.validated(); preconditionFailure("Overflow accepted") } catch { checks += 1 }
        bad = value; bad.schema = 99
        do { _ = try bad.validated(); preconditionFailure("Unknown schema accepted") } catch { checks += 1 }
        do { _ = try WatchCompanionSnapshot.decode(Data(repeating: 0, count: 60_001)); preconditionFailure("Huge context accepted") } catch { checks += 1 }
        var finished = value; finished.businesses[0].arrived = true
        check(finished.nextVisit == nil, "Arrival stops showing the visit as pending")
        let exported = try JSONEncoder().encode(value)
        check(!String(data: exported, encoding: .utf8)!.contains("example.invalid"), "No login credentials or raw account email travel to Watch")
        print("Watch companion snapshot: \(checks) checks passed")
    }
}
