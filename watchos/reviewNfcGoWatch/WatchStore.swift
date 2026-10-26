import SwiftUI
import WatchConnectivity

@MainActor final class WatchStore: NSObject, ObservableObject, WCSessionDelegate {
    @Published private(set) var snapshot = WatchCompanionSnapshot()
    @Published private(set) var message = "Abre reviewNfcGo en el iPhone para recibir tus datos."
    private let cache = "reviewnfcgo.watch.snapshot"
    override init() {
        super.init()
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--verification-watch") { return }
        #endif
        if let data = UserDefaults.standard.data(forKey: cache), let value = try? WatchCompanionSnapshot.decode(data) { snapshot = value }
        if WCSession.isSupported() { WCSession.default.delegate = self; WCSession.default.activate() }
    }
    func refresh() {
        guard WCSession.isSupported(), WCSession.default.activationState == .activated else { return }
        receive(WCSession.default.receivedApplicationContext)
        guard WCSession.default.isReachable else { message = "Los datos se actualizarán al conectar con el iPhone."; return }
        WCSession.default.sendMessage(["reviewnfcgo.request": "snapshot"], replyHandler: { value in
            Task { @MainActor in self.receive(value) }
        }, errorHandler: { _ in Task { @MainActor in self.message = "Conecta el iPhone para actualizar los datos." } })
    }
    private func receive(_ context: [String: Any]) {
        guard let data = context["reviewnfcgo.snapshot"] as? Data, let value = try? WatchCompanionSnapshot.decode(data) else { return }
        snapshot = value; UserDefaults.standard.set(data, forKey: cache)
        message = value.isAvailable ? "" : "Inicia sesión en reviewNfcGo desde el iPhone."
    }
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        Task { @MainActor in self.refresh() }
    }
    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        Task { @MainActor in self.receive(applicationContext) }
    }
    #if DEBUG
    func verify() {
        let now = Date()
        let business = WatchCompanionBusiness(id: UUID(uuidString: "88888888-1111-2222-3333-444444444444")!, name: "Café del Centro", address: "Calle Mayor, Madrid", latitude: 40.4168, longitude: -3.7038, visitDate: now.addingTimeInterval(3600), completed: false, arrived: false, incomeCents: 1500)
        let value = WatchCompanionSnapshot(generatedAt: now, ownerID: String(repeating: "a", count: 64), balanceCents: 3000, dayIncomeCents: 5500, cardsSold: 2, businesses: [business])
        let data = try! JSONEncoder().encode(value); receive(["reviewnfcgo.snapshot": data])
        let exact = snapshot == value
        let before = snapshot; receive(["reviewnfcgo.snapshot": Data("invalid".utf8)]); let preserved = before == snapshot
        receive(["reviewnfcgo.snapshot": try! JSONEncoder().encode(WatchCompanionSnapshot())]); let cleared = !snapshot.isAvailable && snapshot.businesses.isEmpty && snapshot.balanceCents == nil
        receive(["reviewnfcgo.snapshot": data])
        let result: [String: Any] = ["passed": exact && preserved && cleared, "snapshotExact": exact, "badDataPreservesLast": preserved, "logoutClearsData": cleared]
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("watch-verification.json")
        try? JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys]).write(to: url)
    }
    #endif
}
