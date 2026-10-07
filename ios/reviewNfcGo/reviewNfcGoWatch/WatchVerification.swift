#if DEBUG
import Foundation
@MainActor enum WatchVerification {
    static let businessID = UUID(uuidString: "E686DAE0-73ED-4A82-B1D9-A2062F2EACB4")!
    static func run(store: WatchStore) {
        let output = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("watch-verification.json")
        var checks: [String] = []
        func check(_ value: Bool, _ name: String) throws {
            guard value else { throw NSError(domain: "WatchVerification", code: 1, userInfo: [NSLocalizedDescriptionKey: name]) }
            checks.append(name)
        }
        do {
            let owner = WatchIdentity.token("watch@example.invalid"), session = UUID()
            let productID = UUID()
            let business = WatchBusiness(id: businessID, name: "Café de la Plaza", address: "Plaza Mayor, Madrid", latitude: 40.415, longitude: -3.707,
                visitDate: Date().addingTimeInterval(5400), completed: false, cardsSold: 0, unitEarnings: 10, revision: "watch-v5")
            let snapshot = WatchSnapshot(generatedAt: Date(), owner: owner, sessionID: session, businesses: [business],
                products: [WatchProduct(id: productID, name: "Tarjetas NFC · Azul", stock: 10)], balanceCents: -1200, dayIncomeCents: 6000, dayExpenseCents: 7200, dayCards: 6)
            store.verificationAccept(snapshot)
            try check(store.snapshot.nextVisit(at: Date())?.id == businessID, "Próxima visita disponible")
            try check(store.enqueue(.sale, business: business, cards: 2, unitCents: 1000, productID: productID), "Venta sin conexión queda en cola")
            try check(store.isPending(businessID), "Acción pendiente visible")
            try check(!store.enqueue(.arrive, business: business), "No envía dos cambios concurrentes del mismo negocio")
            let id = store.pending[0].id
            let persisted = UserDefaults.standard.data(forKey: "watch.pending")!
            try check(try JSONDecoder().decode([WatchAction].self, from: persisted).contains { $0.id == id }, "Cola persiste para un arranque posterior")
            store.verificationReceipt(WatchReceipt(id: id, accepted: true, message: "Venta guardada."))
            try check(store.pending.isEmpty, "Confirmación retira cambio de la cola")
            try check(WatchSharedStore.load().nextVisit(at: Date())?.id == businessID, "Complicación lee datos del contenedor compartido")
            _ = store.enqueue(.arrive, business: business)
            var signedOut = WatchSnapshot(generatedAt: Date().addingTimeInterval(1))
            store.verificationAccept(signedOut)
            try check(store.pending.isEmpty && store.snapshot.owner == nil && !store.errors.isEmpty, "Cambio de cuenta invalida cola y limpia complicación")
            try check(WatchSharedStore.load().owner == nil, "Sin datos personales en complicación tras cerrar sesión")
            signedOut = snapshot; signedOut.generatedAt = Date().addingTimeInterval(2)
            store.verificationAccept(signedOut); store.clearErrors()
            try JSONSerialization.data(withJSONObject: ["passed": true, "checks": checks], options: .prettyPrinted).write(to: output)
        } catch { try? JSONSerialization.data(withJSONObject: ["passed": false, "checks": checks, "error": error.localizedDescription], options: .prettyPrinted).write(to: output) }
    }
}
#endif
