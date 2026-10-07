import Foundation
@main struct BusinessToolsTests {
    static func main() throws {
        var checks = 0
        func check(_ condition: @autoclosure () -> Bool, _ label: String) { precondition(condition(), label); checks += 1 }
        let now = Date(timeIntervalSince1970: 1_800_000_000)
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
        print("Business tools: \(checks) checks passed")
    }
}
