import Foundation
@main struct BusinessToolsTests {
    static func main() throws {
        var checks = 0
        func check(_ condition: @autoclosure () -> Bool, _ label: String) { precondition(condition(), label); checks += 1 }
        let now = Date(timeIntervalSince1970: 1_800_000_000.125)
        let place = PlaceResult(id: "a", name: "A", address: "Madrid", latitude: 40, longitude: -3)
        let card = InventoryProduct(name: "Tarjeta", kind: .nfcCard, color: "Negro")
        var money = MoneyLedger()
        var record = VisitRecord(place: place, createdAt: now)
        money.synchronize([record], now: now)
        let empty = money
        try money.addExpense(title: "Tarjetas", amount: 50, quantity: 10, productID: card.id, newProduct: card, date: now, merchant: "Tienda", method: "Tarjeta", url: "https://example.org", notes: "")
        check(money.lowStockProducts.isEmpty, "Adequate stock")
        let purchased = money
        record.cardsSold = 6; record.earnings = 120; record.unitEarnings = 20; record.inventoryProductID = card.id
        money.synchronize([record], now: now)
        check(money.profitCents(record.id) == 9000 && money.sales[record.id.uuidString]?.costCents == 3000, "Sale subtracts cost of cards sold")
        check(money.lowStockProducts.map(\.id) == [card.id], "Low stock at five or fewer")
        let sold = money
        try money.addExpense(title: "New batch", amount: 100, quantity: 10, productID: card.id, date: now, merchant: "", method: "", url: "", notes: "")
        money.synchronize([record], now: now)
        check(money.profitCents(record.id) == 9000, "Later purchases do not change historical profit")
        record.cardsSold = 8; record.earnings = 160
        money.synchronize([record], now: now)
        check(money.sales[record.id.uuidString]?.costCents == 4500, "Additional cards use current average cost")
        record.cardsSold = 4; record.earnings = 80
        money.synchronize([record], now: now)
        check(money.sales[record.id.uuidString]?.costCents == 2250, "Reduced sale returns proportional card cost")
        var undo = purchased
        undo.undo(to: empty, records: [VisitRecord(id: record.id, place: place, createdAt: now)], now: now)
        check(undo.balanceCents == 0 && undo.stock(card.id) == 0 && undo.transactions.count == 2, "Undo purchase preserves audit and restores balance and stock")
        var saleUndo = sold
        saleUndo.undo(to: purchased, records: [VisitRecord(id: record.id, place: place, createdAt: now)], now: now)
        check(saleUndo.balanceCents == -5000 && saleUndo.stock(card.id) == 10 && saleUndo.incomeCents == 0, "Undo sale restores stock and appends income correction")
        let beforeNoOp = money.transactions.count
        money.synchronize([record], now: now)
        check(money.transactions.count == beforeNoOp, "Profit accounting is idempotent")
        let backup = BusinessBackup(createdAt: now, owner: "a@example.org", records: [record], money: money)
        let restored = try BusinessBackup.decode(backup.encoded(), for: backup.owner)
        check(restored.records == backup.records && restored.money == money, "Complete validated backup round trip")
        do { _ = try BusinessBackup.decode(backup.encoded(), for: "other@example.org"); preconditionFailure("Other account accepted") } catch { check(error is BackupError, "Account isolation") }
        var corrupt = backup; corrupt.records.append(record)
        do { _ = try corrupt.validated(for: backup.owner); preconditionFailure("Duplicate accepted") } catch { checks += 1 }
        corrupt = backup; corrupt.money.sales.removeAll()
        do { _ = try corrupt.validated(for: backup.owner); preconditionFailure("Stale checkpoint accepted") } catch { checks += 1 }
        corrupt = backup; corrupt.schema = 2
        do { _ = try corrupt.validated(for: backup.owner); preconditionFailure("Future schema accepted") } catch { checks += 1 }
        corrupt = backup; corrupt.money.transactions[0].cents = Int64.max
        do { _ = try corrupt.validated(for: backup.owner); preconditionFailure("Overflow accepted") } catch { checks += 1 }
        corrupt = backup; corrupt.records[0].place = PlaceResult(id: "a", name: "A", address: "Madrid", latitude: 200, longitude: -3)
        do { _ = try corrupt.validated(for: backup.owner); preconditionFailure("Bad coordinate accepted") } catch { checks += 1 }
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: "Europe/Madrid")!
        var early = VisitRecord(place: place, createdAt: now, reminderDate: now.addingTimeInterval(100))
        early.place = PlaceResult(id: "early", name: "A", address: "", latitude: 40, longitude: -3)
        var late = early; late.id = UUID(); late.place = PlaceResult(id: "late", name: "A", address: "", latitude: 40, longitude: -3); late.reminderDate = now.addingTimeInterval(1000)
        var near = VisitRecord(place: PlaceResult(id: "near", name: "Z", address: "", latitude: 40.001, longitude: -3), createdAt: now)
        var far = near; far.id = UUID(); far.place = PlaceResult(id: "far", name: "B", address: "", latitude: 41, longitude: -3)
        let route = DailyRoute.stops(records: [far, late, near, early], day: now, origin: place, calendar: calendar)
        check(route.map(\.id) == [early.id, late.id, near.id, far.id], "Appointment times precede flexible nearby visits")
        near.status = .completed
        check(!DailyRoute.stops(records: [near], day: now).contains(where: { $0.id == near.id }), "Completed visits excluded")
        check(DailyRoute.distance(place, place) == 0 && DailyRoute.distance(place, far.place) > 100_000, "Geographic distance")
        let nextDay = calendar.date(byAdding: .day, value: 1, to: now)!
        check(DailyRoute.stops(records: [early], day: nextDay, calendar: calendar).isEmpty, "Date filtering honors local calendar")
        var refundUndo = purchased
        let purchaseID = refundUndo.transactions.first!.id
        try refundUndo.reverseExpense(purchaseID, now: now)
        check(refundUndo.isReversed(purchaseID), "Refund marks original reversed")
        refundUndo.undo(to: purchased, records: [VisitRecord(id: record.id, place: place, createdAt: now)], now: now)
        check(!refundUndo.isReversed(purchaseID) && refundUndo.balanceCents == purchased.balanceCents, "Undo refund restores original purchase status")
        let cheapCard = InventoryProduct(name: "Tarjeta", kind: .nfcCard, color: "Blanco")
        var cheap = MoneyLedger()
        try cheap.addExpense(title: "Lote", amount: 4.50, quantity: 16, productID: cheapCard.id, newProduct: cheapCard, date: now, merchant: "", method: "", url: "", notes: "")
        var bulk = VisitRecord(place: place, createdAt: now, earnings: 60, cardsSold: 6, inventoryProductID: cheapCard.id)
        cheap.synchronize([bulk], now: now)
        bulk.cardsSold = 16; bulk.earnings = 160
        cheap.synchronize([bulk], now: now)
        check(cheap.sales[bulk.id.uuidString]?.costCents == 450, "Bulk purchase cost retains fractions of a cent across partial sales")
        var quick = purchased
        var customer = VisitRecord(place: place, createdAt: now)
        quick.synchronize([customer], now: now)
        let stand = InventoryProduct(name: "Stand", kind: .stand)
        try quick.addExpense(title: "Stands", amount: 12, quantity: 4, productID: stand.id, newProduct: stand, date: now, merchant: "", method: "", url: "", notes: "")
        let beforeQuick = quick, beforeCustomer = customer
        let items = [QuickSaleInput(productID: card.id, quantity: 2, unitPrice: 15), QuickSaleInput(productID: stand.id, quantity: 1, unitPrice: 8)]
        try quick.registerSale(business: &customer, items: items, payment: "Bizum", now: now)
        check(quick.businessIncome(customer.id) == 3800 && quick.businessProfit(customer.id) == 2500, "Mixed card and stand sale preserves gross, cost and profit")
        check(quick.stock(card.id) == 8 && quick.stock(stand.id) == 3 && quick.allCardsSold == 2, "Sale consumes both products without inventing a legacy card")
        let quickCount = quick.transactions.count
        quick.synchronize([customer], now: now)
        check(quick.transactions.count == quickCount && customer.cardsSold == 0, "Repeated sync never duplicates quick sale income")
        let quickBackup = BusinessBackup(owner: backup.owner, records: [customer], money: quick)
        let quickDecoded = try BusinessBackup.decode(quickBackup.encoded(), for: backup.owner)
        check(quickDecoded.money == quick && quickDecoded.records == [customer], "Quick sale backups round trip without legacy normalization")
        let valid = quick
        do { try quick.registerSale(business: &customer, items: [QuickSaleInput(productID: stand.id, quantity: 100, unitPrice: 8)], payment: "Tarjeta"); preconditionFailure("Oversell accepted") } catch { checks += 1 }
        check(quick == valid, "Rejected sale leaves money and stock untouched")
        do { try quick.registerSale(business: &customer, items: [items[0], items[0]], payment: "Tarjeta"); preconditionFailure("Duplicate products accepted") } catch { checks += 1 }
        check(quick == valid, "Duplicate line cannot overdraw inventory")
        var quickUndo = quick
        quickUndo.undo(to: beforeQuick, records: [beforeCustomer], now: now)
        check(quickUndo.incomeCents == beforeQuick.incomeCents && quickUndo.stock(card.id) == 10 && quickUndo.stock(stand.id) == 4, "Undo mixed sale reverses receipts and returns inventory")
        check(quickUndo.quickSales?.first?.voidedAt != nil && quickUndo.transactions.count > quick.transactions.count, "Undo keeps sale audit and compensation")
        _ = try BusinessBackup(owner: backup.owner, records: [beforeCustomer], money: quickUndo).validated(for: backup.owner)
        try quick.addExpense(title: "More stands", amount: 100, quantity: 2, productID: stand.id, date: now, merchant: "", method: "", url: "", notes: "")
        check(quick.businessProfit(customer.id) == 2500, "New expensive stands do not alter historical margin")
        customer.followUp = [FollowUpEvent(date: now, text: "Visita", isVisit: true), FollowUpEvent(date: now, text: "Segunda visita", isVisit: true)]
        customer.arrivedAt = now
        let progress = WeeklyProgress(records: [customer], money: quick, date: now, calendar: calendar)
        check(progress.cards == 2 && progress.visits == 1 && progress.profit == 2500 && !progress.unknownCosts, "Weekly totals use sale costs and distinct visited businesses")
        let laterWeek = calendar.date(byAdding: .day, value: 7, to: now)!
        check(WeeklyProgress(records: [customer], money: quick, date: laterWeek, calendar: calendar).visits == 0, "Weekly visits stay inside the chosen week")
        let url = DailyRoute.mapURL(stops: route)!
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems!
        check(query.first { $0.name == "destination" }?.value == "41.0,-3.0" && query.first { $0.name == "waypoints" }?.value?.split(separator: "|").count == 3, "Directions preserve ordered stops")
        check(DailyRoute.mapURL(stops: route + route) == nil && DailyRoute.mapURL(stops: []) == nil, "Routes reject empty or unsupported oversized segments")
        var prospect = beforeCustomer
        prospect.trackingStage = .interested; prospect.notes = "Prefiere el viernes"; prospect.trackChanges(from: beforeCustomer, now: now)
        check(prospect.followUp?.count == 2 && prospect.trackingStage == .interested, "Stage and notes append dated history")
        let roundTrip = try JSONDecoder().decode(VisitRecord.self, from: JSONEncoder().encode(prospect))
        check(roundTrip == prospect, "Follow-up survives serialization")
        print("Business tools: \(checks) checks passed")
    }
}
