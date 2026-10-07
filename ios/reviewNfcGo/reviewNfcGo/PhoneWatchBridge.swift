import SwiftUI
import WatchConnectivity

@MainActor final class PhoneWatchBridge: NSObject, ObservableObject, WCSessionDelegate {
    static let shared = PhoneWatchBridge()
    @Published private(set) var status = "El Watch necesita la app complementaria instalada y firmada."
    private weak var store: AppStore?
    private var journal = WatchActionJournal()
    private var owner: String?
    private var sessionID: UUID?
    private var journalKey: String { "resenago.watch.receipts." + (owner ?? "guest") }
    func attach(_ store: AppStore) {
        self.store = store
        store.didChange = { [weak self] in self?.publish() }
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        if WCSession.default.activationState == .notActivated { WCSession.default.activate() }
        publish()
    }
    private func loadAccount() {
        let newOwner = store?.loadedUserEmail.map(WatchIdentity.token)
        guard newOwner != owner || sessionID == nil else { return }
        owner = newOwner
        guard let owner else { sessionID = nil; journal = WatchActionJournal(); return }
        let key = "resenago.watch.session." + owner
        sessionID = UserDefaults.standard.string(forKey: key).flatMap(UUID.init(uuidString:)) ?? UUID()
        UserDefaults.standard.set(sessionID!.uuidString, forKey: key)
        journal = UserDefaults.standard.data(forKey: journalKey).flatMap { try? JSONDecoder().decode(WatchActionJournal.self, from: $0) } ?? WatchActionJournal()
    }
    func snapshot(now: Date = Date()) -> WatchSnapshot {
        loadAccount()
        guard let store, owner != nil else { return WatchSnapshot(generatedAt: now) }
        var value = WatchSnapshot(generatedAt: now, owner: owner, sessionID: sessionID)
        let ordered = store.records.sorted {
            if ($0.status == .completed) != ($1.status == .completed) { return $0.status != .completed }
            return ($0.reminderDate ?? .distantFuture) < ($1.reminderDate ?? .distantFuture)
        }
        value.businesses = ordered.prefix(40).map { record in
            let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
            let revision = (try? encoder.encode(record)).map { WatchIdentity.token($0.base64EncodedString()) } ?? ""
            return WatchBusiness(id: record.id, name: String(record.place.name.prefix(160)), address: String(record.place.address.prefix(220)),
                latitude: record.place.latitude, longitude: record.place.longitude, visitDate: record.reminderDate, arrivedAt: record.arrivedAt,
                completed: record.status == .completed, cardsSold: record.cardsSold, unitEarnings: record.earningsPerCard,
                productID: record.inventoryProductID, revision: revision)
        }
        value.products = store.money.products.filter { $0.kind == .nfcCard }.prefix(50).map { WatchProduct(id: $0.id, name: String($0.displayName.prefix(160)), stock: store.money.stock($0.id)) }
        value.balanceCents = store.money.balanceCents
        let today = store.money.transactions.filter { Calendar.current.isDate($0.date, inSameDayAs: now) }
        value.dayIncomeCents = today.filter { $0.kind.isIncome }.reduce(0) { $0 + $1.cents }
        value.dayExpenseCents = -today.filter { [.expense, .refund].contains($0.kind) }.reduce(0) { $0 + $1.cents }
        value.dayCards = today.filter { $0.kind.isIncome }.reduce(0) { $0 + $1.quantity }
        return value
    }
    func publish() {
        guard WCSession.isSupported(), WCSession.default.activationState == .activated else { return }
        loadAccount()
        status = !WCSession.default.isPaired ? "No hay un Apple Watch enlazado." : !WCSession.default.isWatchAppInstalled ? "Instala la app complementaria en tu Apple Watch." : WCSession.default.isReachable ? "Apple Watch conectado." : "Se sincronizará cuando el Watch y el iPhone estén disponibles."
        var value = snapshot()
        value.receipts = (journal.order ?? []).suffix(100).compactMap { journal.receipts[$0] }
        let encoder = JSONEncoder()
        while let data = try? encoder.encode(value), data.count > 55_000, !value.businesses.isEmpty { value.businesses.removeLast() }
        guard let data = try? encoder.encode(value), data.count <= 60_000 else { return }
        try? WCSession.default.updateApplicationContext(["snapshot": data])
    }
    #if DEBUG
    func verificationReceive(_ action: WatchAction) -> WatchReceipt? {
        guard let data = try? JSONEncoder().encode(action), let receipt = receive(["action": data])["receipt"] as? Data else { return nil }
        return try? JSONDecoder().decode(WatchReceipt.self, from: receipt)
    }
    #endif
    private func receive(_ message: [String: Any]) -> [String: Any] {
        loadAccount()
        guard let data = message["action"] as? Data, data.count < 8192,
              let action = try? JSONDecoder().decode(WatchAction.self, from: data), let store, owner != nil else { return [:] }
        var currentJournal = journal
        let receipt = currentJournal.process(action, snapshot: snapshot()) { [weak self] in
            guard let self else { return "Abre la app en el iPhone." }
            return self.apply(action, store: store)
        }
        journal = currentJournal
        if let data = try? JSONEncoder().encode(journal) { UserDefaults.standard.set(data, forKey: journalKey) }
        publish()
        return (try? JSONEncoder().encode(receipt)).map { ["receipt": $0] } ?? [:]
    }
    func openPreparedBusiness() {
        loadAccount()
        guard UIApplication.shared.applicationState == .active,
              let value = UserDefaults.standard.dictionary(forKey: "resenago.watch.preparedNFC") as? [String: String] else { return }
        guard value["owner"] == owner, let id = value["business"].flatMap(UUID.init(uuidString:)), store?.records.contains(where: { $0.id == id }) == true else {
            UserDefaults.standard.removeObject(forKey: "resenago.watch.preparedNFC"); return
        }
        PortalRouter.shared.open(recordID: id)
        UserDefaults.standard.removeObject(forKey: "resenago.watch.preparedNFC")
    }
    func invalidatePendingActions() {
        loadAccount()
        guard let owner else { return }
        sessionID = UUID()
        UserDefaults.standard.set(sessionID!.uuidString, forKey: "resenago.watch.session." + owner)
        publish()
    }
    private func apply(_ action: WatchAction, store: AppStore) -> String? {
        guard var record = store.records.first(where: { $0.id == action.businessID }) else { return "El negocio ya no está guardado." }
        switch action.kind {
        case .arrive: record.arrivedAt = Date()
        case .tomorrow:
            guard let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date()) else { return "No se pudo calcular la visita." }
            let time = record.reminderDate ?? Date()
            let parts = Calendar.current.dateComponents([.hour, .minute], from: time)
            let date = Calendar.current.date(bySettingHour: parts.hour ?? 9, minute: parts.minute ?? 0, second: 0, of: tomorrow) ?? tomorrow
            record.reminderDate = date; record.notificationDate = max(Date().addingTimeInterval(60), date.addingTimeInterval(-3600))
            record.arrivedAt = nil; record.status = .pending
        case .sale:
            record.cardsSold += action.cards
            record.earnings += Double(action.unitCents * Int64(action.cards)) / 100
            record.unitEarnings = nil // Preserve the exact total when selling additional cards at a different price.
            record.inventoryProductID = action.productID; record.status = .completed
            record.reminderDate = nil; record.notificationDate = nil
        case .prepareNFC:
            // NFC sessions require a foreground user action on the iPhone.
            UserDefaults.standard.set(["owner": action.owner, "business": record.id.uuidString], forKey: "resenago.watch.preparedNFC")
            openPreparedBusiness()
            return nil
        }
        return store.update(record) ? nil : "Revisa las tarjetas y el importe en el iPhone."
    }
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        Task { @MainActor in self.publish() }
    }
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}
    nonisolated func sessionDidDeactivate(_ session: WCSession) { session.activate() }
    nonisolated func sessionWatchStateDidChange(_ session: WCSession) { Task { @MainActor in self.publish() } }
    nonisolated func sessionReachabilityDidChange(_ session: WCSession) { Task { @MainActor in self.publish() } }
    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        Task { @MainActor in
            if message["refresh"] != nil {
                self.publish()
                var value = self.snapshot()
                value.receipts = (message["pending"] as? [String] ?? []).prefix(100).compactMap { self.journal.receipts[$0] }
                let data = try? JSONEncoder().encode(value)
                replyHandler(data.map { ["snapshot": $0] } ?? [:])
            } else { replyHandler(self.receive(message)) }
        }
    }
    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) { Task { @MainActor in _ = self.receive(userInfo) } }
}
struct WatchStatusView: View {
    @ObservedObject private var bridge = PhoneWatchBridge.shared
    var body: some View {
        List {
            Section {
                Label(bridge.status, systemImage: "applewatch")
                Button("Sincronizar ahora") { bridge.publish() }
            }
            Section("En tu muñeca") {
                Label("Próxima visita y cuenta atrás", systemImage: "timer")
                Label("He llegado, volver mañana y registrar ventas", systemImage: "checkmark.circle")
                Label("Indicaciones y resumen del día", systemImage: "map")
                Label("Widget y complicación de próximas visitas", systemImage: "clock")
            }
            Section {
                Text("Los cambios pendientes se envían cuando los dispositivos pueden comunicarse. Abre ambas apps para sincronizar después de iniciar sesión o restaurar una copia.")
                Text("La app de watchOS se instala desde Xcode o mediante distribución de Apple; añadir la fuente de SideStore no instala la app del reloj.")
            }.font(.footnote).foregroundStyle(.secondary)
        }.navigationTitle("Apple Watch").navigationBarTitleDisplayMode(.inline)
    }
}
