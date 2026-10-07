import Foundation

enum ProductKind: String, Codable, CaseIterable, Identifiable {
    case nfcCard, stand, accessory, custom
    var id: String { rawValue }
    var title: String {
        switch self { case .nfcCard: return "Tarjetas NFC"; case .stand: return "Stands"; case .accessory: return "Accesorios"; case .custom: return "Producto personalizado" }
    }
    var icon: String { self == .nfcCard ? "creditcard" : self == .stand ? "rectangle.on.rectangle" : "shippingbox" }
}
struct InventoryProduct: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    var kind: ProductKind
    var color = ""
    var purchaseURL = ""
    var imageURL = ""
    var displayName: String { color.isEmpty ? name : "\(name) · \(color)" }
}
enum MoneyKind: String, Codable {
    case income, incomeAdjustment, expense, refund, stockAdjustment
    var title: String {
        switch self { case .income: return "Ingreso"; case .incomeAdjustment: return "Ajuste de ingreso"; case .expense: return "Gasto"; case .refund: return "Devolución / anulación"; case .stockAdjustment: return "Ajuste de inventario" }
    }
    var isIncome: Bool { self == .income || self == .incomeAdjustment }
}
struct MoneyTransaction: Identifiable, Codable, Equatable {
    var id = UUID()
    var date: Date
    var kind: MoneyKind
    var title: String
    /// Signed cents: receipts positive, expenses negative. Never computed with floating point.
    var cents: Int64
    var businessID: UUID? = nil
    var productID: UUID? = nil
    var quantity = 0
    var merchant = ""
    var paymentMethod = ""
    var purchaseURL = ""
    var notes = ""
    var originalID: UUID? = nil
    var amount: Double { Double(cents) / 100 }
}
struct SaleCheckpoint: Codable, Equatable {
    var cents: Int64
    var cards: Int
    var productID: UUID?
    /// Cost captured when the sale is saved. Nil means the purchase cost is unknown.
    var costCents: Int64? = nil
    var preciseCostCents: Double? = nil
}
enum MoneyError: LocalizedError {
    case invalidAmount, invalidQuantity, insufficientStock, invalidProduct, alreadyReversed
    var errorDescription: String? {
        switch self {
        case .invalidAmount: return "Introduce un importe válido entre 0,01 € y 10.000.000 €."
        case .invalidQuantity: return "Introduce una cantidad entre 1 y 100.000 unidades."
        case .insufficientStock: return "No hay suficientes unidades de ese producto. Registra la compra o revisa las tarjetas asignadas."
        case .invalidProduct: return "Añade el nombre del producto y el color de las tarjetas NFC."
        case .alreadyReversed: return "Este gasto ya tiene una devolución registrada."
        }
    }
}
struct MoneyLedger: Codable, Equatable {
    var products: [InventoryProduct] = []
    var transactions: [MoneyTransaction] = []
    var sales: [String: SaleCheckpoint] = [:]
    static func cents(_ amount: Double) -> Int64? {
        guard amount.isFinite, abs(amount) <= 10_000_000 else { return nil }
        return Int64((amount * 100).rounded())
    }
    var incomeCents: Int64 { transactions.filter { $0.kind.isIncome }.reduce(0) { $0 + $1.cents } }
    var expenseCents: Int64 { -transactions.filter { $0.kind == .expense || $0.kind == .refund }.reduce(0) { $0 + $1.cents } }
    var balanceCents: Int64 { transactions.reduce(0) { $0 + $1.cents } }
    var history: [MoneyTransaction] { transactions.sorted { $0.date > $1.date } }
    func purchased(_ id: UUID) -> Int { transactions.filter { $0.productID == id && ($0.kind == .expense || $0.kind == .refund) }.reduce(0) { $0 + $1.quantity } }
    func sold(_ id: UUID) -> Int { sales.values.filter { $0.productID == id }.reduce(0) { $0 + $1.cards } }
    func stock(_ id: UUID) -> Int {
        transactions.filter { $0.productID == id && [.expense, .refund, .stockAdjustment].contains($0.kind) }.reduce(0) { $0 + $1.quantity } - sold(id)
    }
    func spent(_ id: UUID) -> Double { -Double(transactions.filter { $0.productID == id && [.expense, .refund].contains($0.kind) }.reduce(Int64(0)) { $0 + $1.cents }) / 100 }
    func averageCostCents(_ productID: UUID) -> Double? {
        let quantity = purchased(productID)
        guard quantity > 0 else { return nil }
        let cost = -transactions.filter { $0.productID == productID && [.expense, .refund].contains($0.kind) }.reduce(Int64(0)) { $0 + $1.cents }
        guard cost >= 0 else { return nil }
        return Double(cost) / Double(quantity)
    }
    func isReversed(_ id: UUID) -> Bool {
        // An undo can cancel a refund. Evaluate compensating descendants from newest to oldest.
        var active: [UUID: Bool] = [:]
        var cancelled = Set<UUID>()
        for item in transactions.reversed() {
            let value = !cancelled.contains(item.id)
            active[item.id] = value
            if value, let original = item.originalID { cancelled.insert(original) }
        }
        return transactions.contains { $0.kind == .refund && $0.originalID == id && active[$0.id] == true }
    }
    func canAssign(_ record: VisitRecord) -> Bool {
        guard let id = record.inventoryProductID else { return true }
        guard products.contains(where: { $0.id == id && $0.kind == .nfcCard }) else { return false }
        let old = sales[record.id.uuidString]
        return record.cardsSold <= stock(id) + (old?.productID == id ? old!.cards : 0)
    }
    /// A checkpoint makes migration/reopening idempotent and records only the change when a sale is edited.
    /// Deleted business checkpoints remain: removing a business does not undo a completed sale.
    mutating func synchronize(_ records: [VisitRecord], now: Date = Date()) {
        for record in records {
            let key = record.id.uuidString
            let previous = sales[key]
            let amount = Self.cents(record.earnings) ?? previous?.cents ?? 0
            let difference = amount - (previous?.cents ?? 0)
            let stockChanged = previous != nil && (previous!.cards != record.cardsSold || previous!.productID != record.inventoryProductID)
            if difference != 0 || stockChanged {
                transactions.append(MoneyTransaction(date: previous == nil ? record.createdAt : now,
                    kind: previous == nil || (previous!.cents == 0 && difference > 0) ? .income : .incomeAdjustment, title: record.place.name,
                    cents: difference, businessID: record.id, productID: record.inventoryProductID,
                    quantity: record.cardsSold - (previous?.cards ?? 0),
                    notes: difference == 0 ? "Cambio de inventario: \(record.cardsSold) tarjetas vendidas. El importe del negocio no cambia." : previous == nil ? record.place.address : "Corrección de venta: \(SaleAmountFormatting.text(for: Double(previous!.cents) / 100)) € → \(SaleAmountFormatting.text(for: Double(amount) / 100)) €"))
            }
            let preciseCost: Double?
            if record.cardsSold == 0 { preciseCost = 0 }
            else if let id = record.inventoryProductID, let currentUnit = averageCostCents(id) {
                if let previous, previous.productID == id, let oldCost = previous.costCents {
                    let basis = previous.preciseCostCents ?? Double(oldCost)
                    if record.cardsSold >= previous.cards { preciseCost = basis + Double(record.cardsSold - previous.cards) * currentUnit }
                    else { preciseCost = previous.cards > 0 ? basis * Double(record.cardsSold) / Double(previous.cards) : 0 }
                } else { preciseCost = Double(record.cardsSold) * currentUnit }
            } else { preciseCost = nil }
            let cost = preciseCost.map { Int64($0.rounded()) }
            sales[key] = SaleCheckpoint(cents: amount, cards: record.cardsSold, productID: record.inventoryProductID, costCents: cost, preciseCostCents: preciseCost)
        }
    }
    mutating func addExpense(title: String, amount: Double, quantity: Int, productID: UUID?, newProduct: InventoryProduct? = nil,
                             date: Date, merchant: String, method: String, url: String, notes: String) throws {
        guard let value = Self.cents(amount), value > 0 else { throw MoneyError.invalidAmount }
        guard productID == nil || (1...100_000).contains(quantity) else { throw MoneyError.invalidQuantity }
        if let product = newProduct {
            guard product.id == productID, !product.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  product.kind != .nfcCard || !product.color.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw MoneyError.invalidProduct }
        } else if let id = productID, !products.contains(where: { $0.id == id }) { throw MoneyError.invalidProduct }
        if let newProduct { products.append(newProduct) }
        transactions.append(MoneyTransaction(date: date, kind: .expense, title: title, cents: -value,
            productID: productID, quantity: productID == nil ? 0 : quantity, merchant: merchant, paymentMethod: method,
            purchaseURL: url, notes: notes))
    }
    mutating func reverseExpense(_ id: UUID, now: Date = Date()) throws {
        guard let expense = transactions.first(where: { $0.id == id && $0.kind == .expense }), !isReversed(id) else { throw MoneyError.alreadyReversed }
        if let productID = expense.productID, stock(productID) < expense.quantity { throw MoneyError.insufficientStock }
        transactions.append(MoneyTransaction(date: now, kind: .refund, title: expense.title, cents: -expense.cents,
            productID: expense.productID, quantity: -expense.quantity, merchant: expense.merchant, paymentMethod: expense.paymentMethod,
            purchaseURL: expense.purchaseURL, notes: "Anulación del gasto del \(expense.date.formatted(date: .abbreviated, time: .shortened)). El movimiento original se conserva.", originalID: expense.id))
    }
    mutating func adjustStock(_ id: UUID, quantity: Int, reason: String, now: Date = Date()) throws {
        guard let product = products.first(where: { $0.id == id }) else { throw MoneyError.invalidProduct }
        guard quantity != 0, abs(quantity) <= 100_000, stock(id) + quantity >= 0 else { throw MoneyError.insufficientStock }
        transactions.append(MoneyTransaction(date: now, kind: .stockAdjustment, title: product.displayName,
            cents: 0, productID: id, quantity: quantity, notes: reason))
    }
    static func storageKey(_ email: String?) -> String { "resenago.money.\(email ?? "guest")" }
}
