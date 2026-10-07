import SwiftUI
import WatchConnectivity
import WatchKit

@MainActor final class WatchStore: NSObject, ObservableObject, WCSessionDelegate {
    @Published private(set) var snapshot = WatchSnapshot.empty
    @Published private(set) var pending: [WatchAction] = []
    @Published private(set) var message = "Abre reviewNfcGo en el iPhone para sincronizar."
    @Published private(set) var errors: [WatchReceipt] = []
    private var sent = Set<UUID>()
    private var delivered = Set<UUID>()
    private var transfers: [UUID: WCSessionUserInfoTransfer] = [:]
    override init() {
        super.init()
        snapshot = UserDefaults.standard.data(forKey: "watch.snapshot").flatMap { try? JSONDecoder().decode(WatchSnapshot.self, from: $0) } ?? .empty
        pending = UserDefaults.standard.data(forKey: "watch.pending").flatMap { try? JSONDecoder().decode([WatchAction].self, from: $0) } ?? []
        errors = UserDefaults.standard.data(forKey: "watch.errors").flatMap { try? JSONDecoder().decode([WatchReceipt].self, from: $0) } ?? []
        delivered = Set((UserDefaults.standard.stringArray(forKey: "watch.delivered") ?? []).compactMap(UUID.init(uuidString:)))
        WatchSharedStore.save(snapshot)
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--verification-watch") { return }
        #endif
        if WCSession.isSupported() { WCSession.default.delegate = self; WCSession.default.activate() }
    }
    func isPending(_ businessID: UUID) -> Bool { pending.contains { $0.businessID == businessID } }
    @discardableResult func enqueue(_ kind: WatchActionKind, business: WatchBusiness, cards: Int = 0, unitCents: Int64 = 0, productID: UUID? = nil) -> Bool {
        guard let owner = snapshot.owner, let sessionID = snapshot.sessionID, !isPending(business.id) else { message = "Espera a que se sincronice el cambio anterior."; return false }
        let action = WatchAction(owner: owner, sessionID: sessionID, businessID: business.id, revision: business.revision, kind: kind, cards: cards, unitCents: unitCents, productID: productID)
        if let error = action.validate(snapshot: snapshot, now: Date()) { message = error; return false }
        pending.append(action); persist(); message = "Pendiente de confirmar en el iPhone."; flush()
        WKInterfaceDevice.current().play(.click)
        return true
    }
    func refresh() {
        guard WCSession.default.activationState == .activated else { return }
        accept(WCSession.default.receivedApplicationContext)
        guard WCSession.default.isReachable else { message = "Sin conexión. Los cambios pendientes se enviarán cuando sea posible."; flush(); return }
        WCSession.default.sendMessage(["refresh": true, "pending": pending.map { $0.id.uuidString }], replyHandler: { result in Task { @MainActor in self.accept(result); self.flush() } }, errorHandler: { _ in Task { @MainActor in self.message = "Abre la app del iPhone para sincronizar." } })
    }
    func flush() {
        guard WCSession.default.activationState == .activated else { return }
        let outstanding = WCSession.default.outstandingUserInfoTransfers
        for action in pending {
            guard let data = try? JSONEncoder().encode(action) else { continue }
            if !outstanding.contains(where: { ($0.userInfo["action"] as? Data).flatMap { try? JSONDecoder().decode(WatchAction.self, from: $0) }?.id == action.id }), transfers[action.id] == nil, !delivered.contains(action.id) {
                transfers[action.id] = WCSession.default.transferUserInfo(["action": data])
            }
            if WCSession.default.isReachable, !sent.contains(action.id) {
                sent.insert(action.id)
                WCSession.default.sendMessage(["action": data], replyHandler: { result in
                    Task { @MainActor in self.sent.remove(action.id); self.accept(result); self.refresh() }
                }, errorHandler: { _ in Task { @MainActor in self.sent.remove(action.id); self.message = "Cambio guardado en el Watch; pendiente de enviar." } })
            }
        }
    }
    func clearErrors() { errors = []; persist() }
    private func persist() {
        UserDefaults.standard.set(delivered.map(\.uuidString), forKey: "watch.delivered")
        if let data = try? JSONEncoder().encode(snapshot) { UserDefaults.standard.set(data, forKey: "watch.snapshot") }
        if let data = try? JSONEncoder().encode(pending) { UserDefaults.standard.set(data, forKey: "watch.pending") }
        if let data = try? JSONEncoder().encode(errors) { UserDefaults.standard.set(data, forKey: "watch.errors") }
    }
    private func receipt(_ value: WatchReceipt) {
        guard pending.contains(where: { $0.id == value.id }) else { return }
        pending.removeAll { $0.id == value.id }
        transfers.removeValue(forKey: value.id)?.cancel()
        sent.remove(value.id)
        delivered.remove(value.id)
        message = value.message
        if !value.accepted { errors.append(value); errors = Array(errors.suffix(20)); WKInterfaceDevice.current().play(.failure) }
        else { WKInterfaceDevice.current().play(.success) }
    }
    private func accept(_ message: [String: Any]) {
        if let data = message["snapshot"] as? Data, data.count <= 65_000,
           let value = try? JSONDecoder().decode(WatchSnapshot.self, from: data), value.schema == 1, value.generatedAt >= snapshot.generatedAt {
            if value.owner != snapshot.owner || value.sessionID != snapshot.sessionID {
                for action in pending {
                    receipt(WatchReceipt(id: action.id, accepted: false, message: "Los datos de la cuenta han cambiado. El cambio pendiente no se aplicó."))
                }
            }
            snapshot = value
            for receipt in value.receipts { self.receipt(receipt) }
            WatchSharedStore.save(value)
            if value.owner == nil { self.message = "Inicia sesión en reviewNfcGo en el iPhone." }
            else if pending.isEmpty { self.message = errors.last?.message ?? "Datos sincronizados." }
        }
        if let data = message["receipt"] as? Data, let value = try? JSONDecoder().decode(WatchReceipt.self, from: data) { receipt(value) }
        persist()
    }
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        Task { @MainActor in self.accept(session.receivedApplicationContext); self.refresh() }
    }
    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) { Task { @MainActor in self.accept(applicationContext); self.flush() } }
    nonisolated func sessionReachabilityDidChange(_ session: WCSession) { Task { @MainActor in self.refresh() } }
    nonisolated func session(_ session: WCSession, didFinish userInfoTransfer: WCSessionUserInfoTransfer, error: Error?) {
        Task { @MainActor in
            if let data = userInfoTransfer.userInfo["action"] as? Data, let action = try? JSONDecoder().decode(WatchAction.self, from: data) { self.transfers.removeValue(forKey: action.id)
                if error == nil { self.delivered.insert(action.id) }
                self.persist()
            }
            if error == nil { self.refresh() }
            else { self.message = "Cambio pendiente. Pulsa Sincronizar para volver a intentarlo." }
        }
    }
    #if DEBUG
    func verificationAccept(_ snapshot: WatchSnapshot) {
        if let data = try? JSONEncoder().encode(snapshot) { accept(["snapshot": data]) }
    }
    func verificationReceipt(_ value: WatchReceipt) { receipt(value); persist() }
    #endif
}
