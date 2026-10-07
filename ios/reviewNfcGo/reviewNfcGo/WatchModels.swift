import Foundation
import CryptoKit

enum WatchIdentity {
    static func token(_ value: String) -> String { SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined() }
}
struct WatchBusiness: Codable, Identifiable, Equatable {
    var id: UUID
    var name: String
    var address: String
    var latitude: Double
    var longitude: Double
    var visitDate: Date?
    var arrivedAt: Date?
    var completed: Bool
    var cardsSold: Int
    var unitEarnings: Double
    var productID: UUID?
    var revision: String
}
struct WatchProduct: Codable, Identifiable, Equatable {
    var id: UUID
    var name: String
    var stock: Int
}
struct WatchReceipt: Codable, Equatable {
    var id: UUID
    var accepted: Bool
    var message: String
}
struct WatchSnapshot: Codable, Equatable {
    var schema = 1
    var generatedAt = Date()
    var owner: String?
    var sessionID: UUID?
    var businesses: [WatchBusiness] = []
    var products: [WatchProduct] = []
    var balanceCents: Int64 = 0
    var dayIncomeCents: Int64 = 0
    var dayExpenseCents: Int64 = 0
    var dayCards = 0
    var receipts: [WatchReceipt] = []
    static let empty = WatchSnapshot(generatedAt: .distantPast)
    func nextVisit(at date: Date) -> WatchBusiness? {
        businesses.filter { !$0.completed && $0.visitDate.map { $0 > date } == true }
            .min { $0.visitDate! < $1.visitDate! }
    }
}
enum WatchActionKind: String, Codable { case arrive, tomorrow, sale, prepareNFC }
struct WatchAction: Codable, Identifiable, Equatable {
    var id = UUID()
    var createdAt = Date()
    var owner: String
    var sessionID: UUID
    var businessID: UUID
    var revision: String
    var kind: WatchActionKind
    var cards = 0
    var unitCents: Int64 = 0
    var productID: UUID? = nil
    func validate(snapshot: WatchSnapshot, now: Date) -> String? {
        guard snapshot.schema == 1, owner == snapshot.owner, sessionID == snapshot.sessionID else { return "La cuenta o los datos han cambiado. Sincroniza de nuevo." }
        guard createdAt <= now.addingTimeInterval(300), now.timeIntervalSince(createdAt) <= 7 * 86400 else { return "La acción ha caducado. Vuelve a intentarlo." }
        guard let business = snapshot.businesses.first(where: { $0.id == businessID }), business.revision == revision else { return "El negocio ha cambiado en el iPhone. Revisa su ficha." }
        if kind == .sale {
            guard (1...100_000).contains(cards), (0...5000).contains(unitCents), business.cardsSold <= 100_000 - cards else { return "Revisa la cantidad y el precio (hasta 50 € por tarjeta)." }
            if let existing = business.productID, productID != existing { return "La venta debe usar el mismo color que las tarjetas ya asignadas al negocio." }
            if let productID {
                let needed = business.productID == productID ? cards : business.cardsSold + cards
                guard let product = snapshot.products.first(where: { $0.id == productID }), product.stock >= needed else { return "No hay suficientes tarjetas de ese color." }
            }
        }
        return nil
    }
}

/// Durable receipts are kept separately from user backups to avoid replaying Watch sales after a restore.
struct WatchActionJournal: Codable {
    var receipts: [String: WatchReceipt] = [:]
    var order: [String]? = nil
    mutating func process(_ action: WatchAction, snapshot: WatchSnapshot, now: Date = Date(), apply: () -> String?) -> WatchReceipt {
        if let receipt = receipts[action.id.uuidString] { return receipt }
        let error = action.validate(snapshot: snapshot, now: now) ?? apply()
        let receipt = WatchReceipt(id: action.id, accepted: error == nil, message: error ?? (action.kind == .prepareNFC ? "Abre el iPhone para escribir la tarjeta desde la ficha preparada." : "Guardado en el iPhone."))
        receipts[action.id.uuidString] = receipt
        order = (order ?? []) + [action.id.uuidString]
        return receipt
    }
}
