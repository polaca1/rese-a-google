import Foundation

@main struct WidgetSharedStoreTests {
    static func main() throws {
        var checks = 0
        func check(_ value: Bool, _ message: String) {
            precondition(value, message); checks += 1
        }
        let base = WidgetAppGroupConfiguration.baseGroup
        let signed = base + ".TESTTEAM12"
        func profile(_ groups: [String], xml: Bool = true) throws -> Data {
            let payload = try PropertyListSerialization.data(fromPropertyList: [
                "Entitlements": ["com.apple.security.application-groups": groups]
            ], format: xml ? .xml : .binary, options: 0)
            if !xml { return payload }
            // Tests the XML payload extraction, not CMS signature verification.
            return Data([0x30, 0x82, 0xff, 0x00]) + payload + Data([0x00, 0xff])
        }
        let appIDs = WidgetAppGroupConfiguration.identifiers(metadata: [:], profileData: try profile([signed]))
        let extensionIDs = WidgetAppGroupConfiguration.identifiers(metadata: [:], profileData: try profile([signed]))
        check(appIDs == [signed, base], "SideStore without ALTAppGroups resolves the signed team group")
        check(appIDs == extensionIDs, "App and widget resolve the same group independently")
        check(WidgetAppGroupConfiguration.identifiers(metadata: ["ALTAppGroups": [signed]], profileData: nil) == appIDs,
              "AltStore metadata continues working")
        check(WidgetAppGroupConfiguration.identifiers(metadata: ["ALTAppGroups": [base]], profileData: try profile([signed])).first == signed,
              "Installed profile precedes stale Info.plist metadata")
        check(WidgetAppGroupConfiguration.identifiers(metadata: ["ALTAppGroups": [signed, signed, "group.other"]], profileData: try profile([signed])) == appIDs,
              "Duplicates and unrelated groups are excluded")
        check(WidgetAppGroupConfiguration.identifiers(metadata: [:], profileData: try profile([signed], xml: false)) == appIDs,
              "A plist profile payload can be decoded directly")
        for malformed in [Data(), Data([0xff, 0xfe]), Data("<plist>broken</plist>".utf8), Data("<plist>truncated".utf8), Data(repeating: 0, count: 2_000_001)] {
            check(WidgetAppGroupConfiguration.identifiers(metadata: [:], profileData: malformed) == [base],
                  "Malformed or excessive profile never crashes or invents a group")
        }
        check(WidgetAppGroupConfiguration.identifiers(metadata: [:], profileData: try profile(["group.other", base + "-different"])) == [base],
              "Similar prefixes cannot select an unrelated app's container")
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporary) }
        var requested: [String] = []
        func lookup(_ group: String) -> URL? {
            requested.append(group); return group == signed ? temporary : nil
        }
        let writer = WidgetAppGroupConfiguration.container(identifiers: appIDs, lookup: lookup)
        let reader = WidgetAppGroupConfiguration.container(identifiers: extensionIDs, lookup: lookup)
        check(writer == temporary && reader == writer && requested == [signed, signed],
              "The profile-only app writer and widget reader access the same authorized location")
        let now = Date()
        var snapshot = WidgetSnapshot(isSignedIn: true, updatedAt: now, pending: [], operations: [], totalEarnings: 55, totalCards: 4)
        snapshot.moneyBalance = 30; snapshot.moneyExpenses = 25
        snapshot.moneyOperations = [WidgetMoneyOperation(id: UUID(), name: "Venta de prueba", amount: 55, date: now, businessID: nil),
                                    WidgetMoneyOperation(id: UUID(), name: "Compra de prueba", amount: -25, date: now, businessID: nil)]
        var reloads = 0
        check(WidgetSharedStore.publish(snapshot, to: writer, reload: { reloads += 1 }), "Publishing succeeds through the signed container")
        let received = WidgetSharedStore.load(from: reader)
        check(received.balance == 30 && received.totalEarnings == 55 && received.expenses == 25 && received.totalCards == 4,
              "App 30 EUR / income 55 / expenses 25 reaches the widget unchanged")
        check(received.moneyOperations == snapshot.moneyOperations && reloads == 1, "Transactions survive and reload follows the write")
        snapshot.moneyBalance = 45
        check(WidgetSharedStore.publish(snapshot, to: writer, reload: { reloads += 1 }) && WidgetSharedStore.load(from: reader).balance == 45,
              "A later change replaces the snapshot and refreshes the timeline")
        check(reloads == 2, "One reload per successful publication")
        check(WidgetSharedStore.publish(.empty, to: writer, reload: {}) && !WidgetSharedStore.load(from: reader).isSignedIn
              && WidgetSharedStore.load(from: reader).moneyOperations == nil, "Logout clears financial data from the shared snapshot")
        var zero = WidgetSnapshot(isSignedIn: true, updatedAt: now, pending: [], operations: [], totalEarnings: 0, totalCards: 0)
        zero.moneyBalance = 0
        check(WidgetSharedStore.publish(zero, to: writer, reload: {}) && WidgetSharedStore.load(from: reader).isAvailable != false
              && WidgetSharedStore.load(from: reader).isSignedIn, "A genuinely empty signed-in account may display zero")
        check(WidgetSharedStore.load(from: nil).isAvailable == false, "Missing group is unavailable, not a fake zero balance")
        check(WidgetSharedStore.load(from: temporary.appendingPathComponent("missing")).isAvailable == false,
              "Missing snapshot asks to open the app")
        try Data("not json".utf8).write(to: temporary.appendingPathComponent("widget-snapshot.json"))
        check(WidgetSharedStore.load(from: reader).isAvailable == false, "Corrupt shared data is unavailable")
        check(!WidgetSharedStore.publish(snapshot, to: nil, reload: { reloads += 1 }) && reloads == 2,
              "A failed publication does not announce a reload")
        let oldData = try JSONEncoder().encode(snapshot)
        check(try JSONDecoder().decode(WidgetSnapshot.self, from: oldData).isAvailable == nil,
              "Snapshots without the new availability field remain compatible")
        print("Widget shared storage and SideStore signing: \(checks) checks passed")
    }
}
