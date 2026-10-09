import Foundation

enum BackupError: LocalizedError {
    case invalid, wrongAccount, tooLarge
    var errorDescription: String? {
        switch self {
        case .invalid: return "La copia no es válida o pertenece a una versión incompatible."
        case .wrongAccount: return "Inicia sesión con la cuenta que creó esta copia antes de restaurarla."
        case .tooLarge: return "La copia supera el tamaño permitido (25 MB)."
        }
    }
}
struct BusinessBackup: Codable {
    var schema = 1
    var application = "reviewNfcGo"
    var createdAt = Date()
    var owner: String
    var records: [VisitRecord]
    var money: MoneyLedger
    var photo: Data? = nil
    func validated(for email: String?) throws -> BusinessBackup {
        guard owner == email, !owner.isEmpty else { throw BackupError.wrongAccount }
        guard schema == 1, application == "reviewNfcGo", records.count <= 10_000,
              money.products.count <= 10_000, money.transactions.count <= 100_000, money.sales.count <= 100_000,
              Set(records.map(\.id)).count == records.count,
              Set(records.map { $0.place.id }).count == records.count,
              Set(money.products.map(\.id)).count == money.products.count,
              Set(money.transactions.map(\.id)).count == money.transactions.count,
              (photo?.count ?? 0) <= 2_000_000 else { throw BackupError.invalid }
        if let goals = money.weeklyGoals { guard (1...100_000).contains(goals.cards), (1...100_000).contains(goals.visits), (1...1_000_000_000).contains(goals.profitCents) else { throw BackupError.invalid } }
        let quick = money.quickSales ?? []
        guard quick.count <= 100_000, Set(quick.map(\.id)).count == quick.count else { throw BackupError.invalid }
        let products = Set(money.products.map(\.id))
        for sale in quick {
            guard !sale.items.isEmpty, sale.items.count <= 20, Set(sale.items.map(\.productID)).count == sale.items.count, sale.paymentMethod.count <= 100 else { throw BackupError.invalid }
            for item in sale.items {
                guard products.contains(item.productID), (1...100_000).contains(item.quantity), (0...1_000_000_000).contains(item.unitPriceCents), item.title.count <= 1000,
                      item.costCents.map({ (0...100_000_000_000_000).contains($0) }) ?? true else { throw BackupError.invalid }
            }
            guard (1...1_000_000_000).contains(sale.incomeCents), money.transactions.contains(where: { $0.saleID == sale.id && $0.kind == .income && $0.cents == sale.incomeCents }) else { throw BackupError.invalid }
        }
        for record in records {
            guard (record.followUp?.count ?? 0) <= 1000, (record.followUp ?? []).allSatisfy({ $0.text.count <= 100_000 }) else { throw BackupError.invalid }
            guard (-90...90).contains(record.place.latitude), (-180...180).contains(record.place.longitude),
                  !record.place.id.isEmpty, record.place.name.count <= 500, record.notes.count <= 100_000,
                  (0...100_000).contains(record.cardsSold), MoneyLedger.cents(record.earnings) != nil,
                  record.inventoryProductID.map({ products.contains($0) }) ?? true else { throw BackupError.invalid }
        }
        for transaction in money.transactions {
            guard (-1_000_000_000...1_000_000_000).contains(transaction.cents),
                  (-100_000...100_000).contains(transaction.quantity),
                  transaction.productID.map({ products.contains($0) }) ?? true,
                  transaction.title.count <= 1000, transaction.notes.count <= 100_000 else { throw BackupError.invalid }
            guard transaction.costCents.map({ (-100_000_000_000_000...100_000_000_000_000).contains($0) }) ?? true else { throw BackupError.invalid }
            if let origin = transaction.stockOrigin {
                guard origin != .purchase, transaction.kind == .stockAdjustment, transaction.cents == 0,
                      transaction.productID != nil, transaction.quantity > 0 || transaction.originalID != nil else { throw BackupError.invalid }
            }
        }
        for (key, sale) in money.sales {
            guard UUID(uuidString: key) != nil, (0...100_000).contains(sale.cards),
                  (0...1_000_000_000).contains(sale.cents),
                  sale.productID.map({ products.contains($0) }) ?? true,
                  sale.costCents.map({ (0...100_000_000_000_000).contains($0) }) ?? true,
                  sale.preciseCostCents.map({ $0.isFinite && (0...100_000_000_000_000).contains($0) }) ?? true else { throw BackupError.invalid }
        }
        var stock: [UUID: Int] = [:]
        for transaction in money.transactions where [.expense, .refund, .stockAdjustment].contains(transaction.kind) {
            if let id = transaction.productID { stock[id, default: 0] += transaction.quantity }
        }
        for sale in money.sales.values { if let id = sale.productID { stock[id, default: 0] -= sale.cards } }
        for sale in quick where sale.voidedAt == nil { for item in sale.items { stock[item.productID, default: 0] -= item.quantity } }
        for product in money.products {
            guard stock[product.id, default: 0] >= 0, product.name.count <= 500, product.color.count <= 100 else { throw BackupError.invalid }
        }
        // A stale checkpoint would create a second income when the copy is restored.
        for record in records {
            guard let sale = money.sales[record.id.uuidString], sale.cents == MoneyLedger.cents(record.earnings),
                  sale.cards == record.cardsSold, sale.productID == record.inventoryProductID else { throw BackupError.invalid }
        }
        return self
    }
    static func decode(_ data: Data, for email: String?) throws -> BusinessBackup {
        guard data.count <= 25_000_000 else { throw BackupError.tooLarge }
        let decoder = JSONDecoder()
        do { return try decoder.decode(Self.self, from: data).validated(for: email) }
        catch let error as BackupError { throw error }
        catch { throw BackupError.invalid }
    }
    func encoded() throws -> Data {
        // Keep the complete Date value, including fractions, just like on-device storage.
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }
}

struct RouteStop: Identifiable {
    var id: UUID { record.id }
    var record: VisitRecord
    var distanceMeters: Double?
}
enum DailyRoute {
    static func distance(_ a: PlaceResult, _ b: PlaceResult) -> Double {
        let radians = Double.pi / 180
        let lat = (b.latitude - a.latitude) * radians, lon = (b.longitude - a.longitude) * radians
        let h = pow(sin(lat / 2), 2) + cos(a.latitude * radians) * cos(b.latitude * radians) * pow(sin(lon / 2), 2)
        return 6_371_000 * 2 * asin(sqrt(min(1, max(0, h))))
    }
    /// Appointment times are fixed; proximity only orders the flexible, unscheduled stops.
    static func stops(records: [VisitRecord], day: Date, origin: PlaceResult? = nil, calendar: Calendar = .current) -> [RouteStop] {
        let appointments = records.filter { $0.status != .completed && $0.arrivedAt == nil && $0.reminderDate.map { calendar.isDate($0, inSameDayAs: day) } == true }
            .sorted { ($0.reminderDate!, $0.place.name) < ($1.reminderDate!, $1.place.name) }
        var flexible = records.filter { $0.status != .completed && $0.arrivedAt == nil && $0.reminderDate == nil }
        var ordered = appointments, position = appointments.last?.place ?? origin
        while !flexible.isEmpty {
            let next = flexible.indices.min { a, b in
                guard let position else { return flexible[a].place.name < flexible[b].place.name }
                return distance(position, flexible[a].place) < distance(position, flexible[b].place)
            }!
            let record = flexible.remove(at: next); ordered.append(record); position = record.place
        }
        position = origin
        return ordered.map { record in
            let stop = RouteStop(record: record, distanceMeters: position.map { distance($0, record.place) })
            position = record.place; return stop
        }
    }
}

extension MoneyLedger {
    func profitCents(_ businessID: UUID) -> Int64? {
        guard let sale = sales[businessID.uuidString], let cost = sale.costCents else { return nil }
        return sale.cents - cost
    }
    var lowStockProducts: [InventoryProduct] { products.filter { $0.kind == .nfcCard && stock($0.id) <= 5 } }
    /// Restore the state while retaining a compensating movement for every undone operation.
    mutating func undo(to previous: MoneyLedger, records: [VisitRecord], now: Date = Date()) {
        weeklyGoals = previous.weeklyGoals
        let oldQuickIDs = Set((previous.quickSales ?? []).map(\.id))
        var quick = quickSales ?? []
        for index in quick.indices where !oldQuickIDs.contains(quick[index].id) && quick[index].voidedAt == nil {
            let sale = quick[index]; quick[index].voidedAt = now
            transactions.append(MoneyTransaction(date: now, kind: .incomeAdjustment, title: "Venta rápida deshecha", cents: -sale.incomeCents,
                businessID: sale.businessID, quantity: -sale.items.filter(\.isCard).reduce(0) { $0 + $1.quantity }, paymentMethod: sale.paymentMethod,
                notes: "Se conserva la venta original.", saleID: sale.id, costCents: sale.costCents.map { -$0 }))
        }
        quickSales = quick.isEmpty ? nil : quick
        let previousIDs = Set(previous.transactions.map(\.id))
        let added = transactions.filter { !previousIDs.contains($0.id) }
        for item in added where !item.kind.isIncome {
            let reversedKind: MoneyKind = item.kind == .stockAdjustment ? .stockAdjustment : item.kind == .refund ? .expense : .refund
            transactions.append(MoneyTransaction(date: now, kind: reversedKind, title: item.title, cents: -item.cents,
                productID: item.productID, quantity: -item.quantity, merchant: item.merchant, paymentMethod: item.paymentMethod,
                purchaseURL: item.purchaseURL, notes: "Cambio deshecho. El movimiento original se conserva.", originalID: item.id, stockOrigin: item.stockOrigin))
        }
        // Retain new product definitions because the original movements still reference them.
        for product in previous.products {
            if let i = products.firstIndex(where: { $0.id == product.id }) { products[i] = product }
            else { products.append(product) }
        }
        // Reintroduce a deleted record checkpoint, then synchronize to generate income corrections.
        for (key, checkpoint) in previous.sales where sales[key] == nil { sales[key] = checkpoint }
        for key in Array(sales.keys) where previous.sales[key] == nil && !records.contains(where: { $0.id.uuidString == key }) {
            if let sale = sales[key], sale.cents != 0 {
                transactions.append(MoneyTransaction(date: now, kind: .incomeAdjustment, title: "Venta deshecha", cents: -sale.cents,
                    businessID: UUID(uuidString: key), productID: sale.productID, quantity: -sale.cards, notes: "Cambio deshecho. El ingreso original se conserva."))
            }
            sales[key] = SaleCheckpoint(cents: 0, cards: 0, productID: nil, costCents: 0)
        }
        synchronize(records, now: now)
        for record in records {
            if let old = previous.sales[record.id.uuidString] {
                sales[record.id.uuidString]?.costCents = old.costCents
                sales[record.id.uuidString]?.preciseCostCents = old.preciseCostCents
            }
        }
    }
}

extension MoneyLedger {
    var activeQuickSales: [QuickSale] { (quickSales ?? []).filter { $0.voidedAt == nil } }
    var allCardsSold: Int { sales.values.reduce(0) { $0 + $1.cards } + activeQuickSales.flatMap(\.items).filter(\.isCard).reduce(0) { $0 + $1.quantity } }
    func businessIncome(_ id: UUID) -> Int64 { (sales[id.uuidString]?.cents ?? 0) + activeQuickSales.filter { $0.businessID == id }.reduce(0) { $0 + $1.incomeCents } }
    func businessCards(_ id: UUID) -> Int { (sales[id.uuidString]?.cards ?? 0) + activeQuickSales.filter { $0.businessID == id }.flatMap(\.items).filter(\.isCard).reduce(0) { $0 + $1.quantity } }
    func businessProfit(_ id: UUID) -> Int64? {
        let extra = activeQuickSales.filter { $0.businessID == id }
        guard extra.allSatisfy({ $0.profitCents != nil }) else { return nil }
        let legacy = sales[id.uuidString]
        guard legacy == nil || legacy?.cards == 0 || legacy?.costCents != nil else { return nil }
        return (legacy?.cents ?? 0) - (legacy?.costCents ?? 0) + extra.reduce(0) { $0 + ($1.profitCents ?? 0) }
    }
    mutating func registerSale(business: inout VisitRecord, items: [QuickSaleInput], payment: String, now: Date = Date()) throws {
        guard !items.isEmpty, items.count <= 20, Set(items.map(\.productID)).count == items.count,
              !payment.isEmpty, payment.count <= 100 else { throw MoneyError.invalidProduct }
        var lines: [QuickSaleLine] = []
        for item in items {
            guard let product = products.first(where: { $0.id == item.productID }) else { throw MoneyError.invalidProduct }
            guard (1...100_000).contains(item.quantity), item.quantity <= stock(item.productID) else { throw MoneyError.insufficientStock }
            guard let cents = Self.cents(item.unitPrice), cents >= 0, cents * Int64(item.quantity) <= 1_000_000_000 else { throw MoneyError.invalidAmount }
            let cost = averageCostCents(product.id).map { Int64(($0 * Double(item.quantity)).rounded()) }
            lines.append(QuickSaleLine(productID: product.id, title: product.displayName, isCard: product.kind == .nfcCard, quantity: item.quantity, unitPriceCents: cents, costCents: cost))
        }
        let sale = QuickSale(businessID: business.id, date: now, items: lines, paymentMethod: payment)
        guard lines.filter(\.isCard).reduce(0, { $0 + $1.quantity }) <= 100_000, sale.incomeCents > 0, sale.incomeCents <= 1_000_000_000 else { throw MoneyError.invalidAmount }
        quickSales = (quickSales ?? []) + [sale]
        transactions.append(MoneyTransaction(date: now, kind: .income, title: business.place.name, cents: sale.incomeCents,
            businessID: business.id, quantity: lines.filter(\.isCard).reduce(0) { $0 + $1.quantity }, paymentMethod: payment,
            notes: lines.map { "\($0.quantity) × \($0.title)" }.joined(separator: ", "), saleID: sale.id, costCents: sale.costCents))
        business.hasQuickSales = true; business.status = .completed
        business.followUp = Array(((business.followUp ?? []) + [FollowUpEvent(date: now, text: "Venta: " + SaleAmountFormatting.text(for: Double(sale.incomeCents) / 100) + " € · " + payment)]).suffix(1000))
        synchronize([business], now: now)
    }
}
struct WeeklyProgress {
    let days: [(date: Date, income: Int64, profit: Int64)]
    let cards: Int
    let visits: Int
    let profit: Int64
    let unknownCosts: Bool
    init(records: [VisitRecord], money: MoneyLedger, date: Date = Date(), calendar: Calendar = .current) {
        let week = calendar.dateInterval(of: .weekOfYear, for: date)!
        let income = money.transactions.filter { $0.kind.isIncome && $0.date >= week.start && $0.date < week.end }
        cards = max(0, income.reduce(0) { $0 + $1.quantity })
        visits = records.filter { record in
            (record.arrivedAt.map { $0 >= week.start && $0 < week.end } ?? false) ||
                (record.followUp ?? []).contains { $0.isVisit && $0.date >= week.start && $0.date < week.end }
        }.count
        unknownCosts = income.contains { $0.costCents == nil }
        days = (0..<7).map { offset in
            let start = calendar.date(byAdding: .day, value: offset, to: week.start)!
            let end = calendar.date(byAdding: .day, value: 1, to: start)!
            let entries = income.filter { $0.date >= start && $0.date < end }
            return (start, entries.reduce(0) { $0 + $1.cents }, entries.filter { $0.costCents != nil }.reduce(0) { $0 + $1.cents - ($1.costCents ?? 0) })
        }
        profit = days.reduce(0) { $0 + $1.profit }
    }
}
extension DailyRoute {
    static func mapURL(stops: [RouteStop], walking: Bool = true) -> URL? {
        guard let last = stops.last, stops.count <= 4 else { return nil }
        func coordinates(_ stop: RouteStop) -> String { "\(stop.record.place.latitude),\(stop.record.place.longitude)" }
        var url = URLComponents(string: "https://www.google.com/maps/dir/")!
        url.queryItems = [URLQueryItem(name: "api", value: "1"), URLQueryItem(name: "destination", value: coordinates(last)),
                          URLQueryItem(name: "travelmode", value: walking ? "walking" : "driving")]
        if stops.count > 1 { url.queryItems!.append(URLQueryItem(name: "waypoints", value: stops.dropLast().map(coordinates).joined(separator: "|"))) }
        return url.url
    }
}
