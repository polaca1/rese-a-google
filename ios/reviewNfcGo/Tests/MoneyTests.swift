import Foundation
@main struct MoneyTests {
    static func main() throws {
        var checks = 0
        func check(_ value: @autoclosure () -> Bool, _ title: String) { precondition(value(), title); checks += 1 }
        let place = PlaceResult(id: "shop", name: "Negocio", address: "Madrid", latitude: 40, longitude: -3)
        var record = VisitRecord(place: place, earnings: 60, cardsSold: 3, unitEarnings: 20)
        var ledger = MoneyLedger()
        ledger.synchronize([record]); check(ledger.balanceCents == 6000 && ledger.transactions.count == 1, "Migrate income once")
        ledger.synchronize([record]); check(ledger.transactions.count == 1, "Reopening does not duplicate income")
        let black = InventoryProduct(name: "Tarjeta NFC", kind: .nfcCard, color: "Negro", purchaseURL: "https://example.org/black")
        let white = InventoryProduct(name: "Tarjeta NFC", kind: .nfcCard, color: "Blanco")
        try ledger.addExpense(title: black.displayName, amount: 100, quantity: 10, productID: black.id, newProduct: black, date: Date(), merchant: "Proveedor", method: "Tarjeta", url: black.purchaseURL, notes: "Lote negro")
        check(ledger.balanceCents == -4000 && ledger.stock(black.id) == 10, "Negative balance and purchased stock")
        try ledger.addExpense(title: white.displayName, amount: 20, quantity: 5, productID: white.id, newProduct: white, date: Date(), merchant: "Tienda", method: "Efectivo", url: "", notes: "")
        check(ledger.stock(black.id) == 10 && ledger.stock(white.id) == 5, "Colors do not share stock")
        record.inventoryProductID = black.id
        check(ledger.canAssign(record), "Assign stock to sale")
        ledger.synchronize([record])
        check(ledger.stock(black.id) == 7 && ledger.sold(black.id) == 3 && ledger.transactions.count == 4 && ledger.transactions.last?.cents == 0, "Assigning a color does not add income")
        record.cardsSold = 5; record.earnings = 100
        check(ledger.canAssign(record), "Old units are available when editing")
        ledger.synchronize([record])
        check(ledger.balanceCents == -2000 && ledger.stock(black.id) == 5, "Only difference in earnings is added")
        check(ledger.transactions.last?.cents == 4000 && ledger.transactions.last?.kind == .incomeAdjustment, "Detailed adjustment retained")
        record.cardsSold = 11; check(!ledger.canAssign(record), "Cannot oversell assigned color")
        record.cardsSold = 5; record.inventoryProductID = white.id; ledger.synchronize([record])
        check(ledger.stock(black.id) == 10 && ledger.stock(white.id) == 0, "Reassign color atomically")
        ledger.synchronize([]); check(ledger.incomeCents == 10000 && ledger.stock(white.id) == 0, "Deleting business preserves earned money and sold stock")
        let purchase = ledger.transactions.first { $0.productID == black.id && $0.kind == .expense }!
        try ledger.reverseExpense(purchase.id)
        check(ledger.balanceCents == 8000 && ledger.stock(black.id) == 0 && ledger.purchased(black.id) == 0, "Refund restores balance and removes units from purchased count")
        let saved = ledger
        do { try ledger.reverseExpense(purchase.id); preconditionFailure("Duplicate refund accepted") } catch { check(ledger == saved, "Duplicate refund rejected without changes") }
        let soldPurchase = ledger.transactions.first { $0.productID == white.id && $0.kind == .expense }!
        do { try ledger.reverseExpense(soldPurchase.id); preconditionFailure("Refund sold stock accepted") } catch { check(ledger == saved, "Sold purchases cannot be returned") }
        try ledger.adjustStock(black.id, quantity: 4, reason: "Existencias anteriores")
        check(ledger.stock(black.id) == 4 && ledger.balanceCents == 8000, "Manual stock does not alter balance")
        try ledger.adjustStock(black.id, quantity: -1, reason: "Rotura")
        check(ledger.stock(black.id) == 3 && ledger.transactions.last?.notes == "Rotura", "Stock adjustments retain reasons")
        let encoded = try JSONEncoder().encode(ledger)
        let decoded = try JSONDecoder().decode(MoneyLedger.self, from: encoded)
        check(decoded == ledger, "Complete ledger round trips")
        check(MoneyLedger.storageKey("a") != MoneyLedger.storageKey("b"), "Per account storage")
        check(MoneyLedger.cents(.infinity) == nil && MoneyLedger.cents(.nan) == nil && MoneyLedger.cents(10_000_001) == nil, "Reject unsafe values")
        check(MoneyLedger.cents(0.29) == 29 && MoneyLedger.cents(12.345) == 1235, "Exact cent rounding")
        check(purchase.purchaseURL == black.purchaseURL && purchase.merchant == "Proveedor" && purchase.paymentMethod == "Tarjeta", "Detailed purchase and reorder URL")
        let before = ledger
        do { try ledger.addExpense(title: "Bad", amount: -1, quantity: 1, productID: nil, date: Date(), merchant: "", method: "", url: "", notes: ""); preconditionFailure() } catch { check(ledger == before, "Invalid expenses leave ledger untouched") }
        var reduced = record; reduced.cardsSold = 1; reduced.earnings = 20
        ledger.synchronize([reduced]); check(ledger.incomeCents == 2000 && ledger.stock(white.id) == 4, "Reduced sales reconcile amount and cards")
        let plain = try JSONSerialization.jsonObject(with: JSONEncoder().encode(VisitRecord(place: place))) as! [String: Any]
        check(plain["inventoryProductID"] == nil, "Legacy unassigned sales remain supported")
        print("Money ledger: \(checks) checks passed")
    }
}
