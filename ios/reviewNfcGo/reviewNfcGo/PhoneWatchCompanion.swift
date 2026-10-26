import Foundation
import CryptoKit
import WatchConnectivity

@MainActor final class PhoneWatchCompanion: NSObject, WCSessionDelegate {
    static let shared = PhoneWatchCompanion()
    private weak var store: AppStore?
    func start(store: AppStore) {
        self.store = store
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        if WCSession.default.activationState == .notActivated { WCSession.default.activate() }
        publish(store: store)
    }
    static func snapshot(store: AppStore, now: Date = Date()) -> WatchCompanionSnapshot {
        guard store.hasLoadedRecords, let owner = store.loadedUserEmail else { return WatchCompanionSnapshot(generatedAt: now) }
        var value = WatchCompanionSnapshot(generatedAt: now)
        value.ownerID = SHA256.hash(data: Data(owner.lowercased().utf8)).map { String(format: "%02x", $0) }.joined()
        value.balanceCents = store.money.balanceCents
        value.dayIncomeCents = store.money.transactions.filter { $0.kind.isIncome && Calendar.current.isDate($0.date, inSameDayAs: now) }.reduce(0) { $0 + $1.cents }
        value.cardsSold = store.totalCardsSold
        let ordered = store.records.sorted {
            let a = $0.status != .completed && $0.arrivedAt == nil && $0.reminderDate != nil
            let b = $1.status != .completed && $1.arrivedAt == nil && $1.reminderDate != nil
            if a != b { return a }
            return ($0.reminderDate ?? $0.createdAt) < ($1.reminderDate ?? $1.createdAt)
        }
        value.businesses = ordered.prefix(40).map { record in
            WatchCompanionBusiness(id: record.id, name: String(record.place.name.prefix(160)), address: String(record.place.address.prefix(220)), latitude: record.place.latitude, longitude: record.place.longitude, visitDate: record.reminderDate, completed: record.status == .completed, arrived: record.arrivedAt != nil, incomeCents: store.money.businessIncome(record.id))
        }
        return value
    }
    private func payload() -> [String: Any] {
        guard let store, var valid = try? Self.snapshot(store: store).validated() else { return [:] }
        while let data = try? JSONEncoder().encode(valid), data.count > 55_000, !valid.businesses.isEmpty { valid.businesses.removeLast() }
        guard let data = try? JSONEncoder().encode(valid), data.count <= 60_000 else { return [:] }
        return ["reviewnfcgo.snapshot": data]
    }
    func publish(store: AppStore) {
        self.store = store
        guard WCSession.isSupported(), WCSession.default.activationState == .activated,
              WCSession.default.isPaired, WCSession.default.isWatchAppInstalled else { return }
        let context = payload()
        guard !context.isEmpty else { return }
        try? WCSession.default.updateApplicationContext(context)
    }
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        Task { @MainActor in if let store = self.store { self.publish(store: store) } }
    }
    nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
        Task { @MainActor in if let store = self.store { self.publish(store: store) } }
    }
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}
    nonisolated func sessionDidDeactivate(_ session: WCSession) { session.activate() }
    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        Task { @MainActor in
            guard message["reviewnfcgo.request"] as? String == "snapshot" else { replyHandler([:]); return }
            replyHandler(self.payload())
        }
    }
    #if DEBUG
    static func verify(store: AppStore) {
        let value = snapshot(store: store)
        let data = try? JSONEncoder().encode(value)
        let valid = (try? value.validated()) != nil
        let actualMoney = store.loadedUserEmail == nil ? value.balanceCents == nil : value.balanceCents == store.money.balanceCents
        let privateOwner = store.loadedUserEmail.map { value.ownerID != $0 && value.ownerID?.count == 64 } ?? (value.ownerID == nil)
        let bounded = value.businesses.count <= 40 && (data?.count ?? Int.max) <= 60_000
        let result: [String: Any] = ["passed": valid && actualMoney && privateOwner && bounded, "realBalance": actualMoney, "privateOwner": privateOwner, "boundedPayload": bounded]
        if let output = try? JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys]) {
            try? output.write(to: FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("phone-watch-verification.json"))
        }
    }
    #endif

}
