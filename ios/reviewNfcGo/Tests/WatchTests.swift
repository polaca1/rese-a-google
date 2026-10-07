import Foundation
@main struct WatchTests {
    static func main() throws {
        var checks = 0
        func check(_ condition: @autoclosure () -> Bool, _ label: String) { precondition(condition(), label); checks += 1 }
        let now = Date(timeIntervalSince1970: 1_800_000_000), id = UUID(), productID = UUID(), sessionID = UUID()
        let owner = WatchIdentity.token("owner@example.org")
        let business = WatchBusiness(id: id, name: "Negocio", address: "Madrid", latitude: 40, longitude: -3, visitDate: now.addingTimeInterval(3600), completed: false, cardsSold: 0, unitEarnings: 10, revision: "r1")
        let snapshot = WatchSnapshot(generatedAt: now, owner: owner, sessionID: sessionID, businesses: [business], products: [WatchProduct(id: productID, name: "Negro", stock: 3)])
        let action = WatchAction(createdAt: now, owner: owner, sessionID: sessionID, businessID: id, revision: business.revision, kind: .sale, cards: 2, unitCents: 1000, productID: productID)
        check(action.validate(snapshot: snapshot, now: now) == nil, "Valid sale")
        var journal = WatchActionJournal(), applied = 0
        let result = journal.process(action, snapshot: snapshot, now: now) { applied += 1; return nil }
        check(result.accepted && applied == 1, "Sale applied")
        let duplicate = journal.process(action, snapshot: snapshot, now: now) { applied += 1; return nil }
        check(duplicate == result && applied == 1, "Message and durable transfer cannot duplicate a sale")
        var persisted = try JSONDecoder().decode(WatchActionJournal.self, from: JSONEncoder().encode(journal))
        _ = persisted.process(action, snapshot: snapshot, now: now) { applied += 1; return nil }
        check(applied == 1, "Receipts survive restart")
        var changed = action; changed.id = UUID(); changed.owner = "other"
        check(changed.validate(snapshot: snapshot, now: now) != nil, "Other account rejected")
        changed = action; changed.sessionID = UUID()
        check(changed.validate(snapshot: snapshot, now: now) != nil, "Restore epoch rejects queued old actions")
        changed = action; changed.revision = "old"
        check(changed.validate(snapshot: snapshot, now: now) != nil, "Stale business revision rejected")
        changed = action; changed.cards = 4
        check(changed.validate(snapshot: snapshot, now: now) != nil, "Overselling rejected")
        changed = action; changed.cards = 0
        check(changed.validate(snapshot: snapshot, now: now) != nil, "Zero quantity rejected")
        changed = action; changed.unitCents = 5001
        check(changed.validate(snapshot: snapshot, now: now) != nil, "Per-card price limit")
        changed = action; changed.createdAt = now.addingTimeInterval(-8 * 86400)
        check(changed.validate(snapshot: snapshot, now: now) != nil, "Expired queued sale rejected")
        changed = action; changed.createdAt = now.addingTimeInterval(400)
        check(changed.validate(snapshot: snapshot, now: now) != nil, "Future timestamp rejected")
        changed = action; changed.id = UUID(); changed.revision = "bad"
        let rejected = journal.process(changed, snapshot: snapshot, now: now) { applied += 1; return nil }
        check(!rejected.accepted && applied == 1, "Rejected action never mutates phone")
        check(snapshot.nextVisit(at: now)?.id == id && snapshot.nextVisit(at: now.addingTimeInterval(3601)) == nil, "Complication selects upcoming visit only")
        let decoded = try JSONDecoder().decode(WatchSnapshot.self, from: JSONEncoder().encode(snapshot))
        check(decoded == snapshot, "Phone and Watch use the same wire format")
        check(owner != "owner@example.org" && owner.count == 64, "Account token does not expose email")
        print("Watch synchronization: \(checks) checks passed")
    }
}
