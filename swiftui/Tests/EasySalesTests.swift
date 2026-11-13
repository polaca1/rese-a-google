import Foundation

@main struct EasySalesTests {
    static func main() throws {
        var checks = 0
        func check(_ condition: @autoclosure () -> Bool, _ label: String) { precondition(condition(), label); checks += 1 }
        let card = InventoryProduct(name: "Tarjeta NFC", kind: .nfcCard, color: "Negro")
        let stand = InventoryProduct(name: "Stand", kind: .stand)
        let extra = InventoryProduct(name: "Llavero", kind: .accessory)
        var money = MoneyLedger()
        var record = VisitRecord(place: PlaceResult(id: "place-sale", name: "Cliente", address: "Madrid", latitude: 40, longitude: -3))
        money.synchronize([record])
        try money.addExpense(title: "Tarjetas", amount: 8, quantity: 4, productID: card.id, newProduct: card, date: Date(), merchant: "", method: "", url: "", notes: "")
        try money.addExpense(title: "Stands", amount: 6, quantity: 2, productID: stand.id, newProduct: stand, date: Date(), merchant: "", method: "", url: "", notes: "")
        try money.receiveStock(title: "Llaveros", quantity: 3, productID: extra.id, newProduct: extra, origin: .manufactured, date: Date(), notes: "")
        var draft = EasySaleLine.make(money: money)
        check(draft.filter(\.selected).map(\.id) == [card.id], "NFC card is ready to save without an Add step")
        let initialItems = try EasySaleLine.inputs(draft, money: money)
        check(initialItems.count == 1, "Pending visible product is the actual saved line")
        for i in draft.indices {
            if draft[i].id == card.id { draft[i].price = "12,50"; draft[i].quantity = 2 }
            if draft[i].id == stand.id { draft[i].selected = true; draft[i].price = "99" }
            if draft[i].id == extra.id { draft[i].selected = true; draft[i].price = "4,50" }
        }
        let items = try EasySaleLine.inputs(draft, money: money)
        check(items.first { $0.id == stand.id }?.unitPrice == 0, "Included stand is free despite a previous nonzero price")
        check(items.first { $0.id == extra.id }?.unitPrice == 4.5, "Other products keep their explicit price")
        try money.registerSale(business: &record, items: items, payment: "Bizum")
        check(money.activeQuickSales.last?.incomeCents == 2950, "Sale total matches paid products only")
        check(money.stock(card.id) == 2 && money.stock(stand.id) == 1 && money.stock(extra.id) == 2, "Free stand and paid goods all reduce their stock")
        check(money.activeQuickSales.last?.costCents == 700 && money.activeQuickSales.last?.profitCents == 2250, "Gift production cost remains in profit accounting")
        let backup = BusinessBackup(owner: "sale@example.invalid", records: [record], money: money)
        let restored = try BusinessBackup.decode(backup.encoded(), for: "sale@example.invalid")
        check(restored.money == money, "Gift sale survives validated account backup round trip")
        var separate = [EasySaleLine(productID: stand.id, selected: true, price: "5")]
        let standaloneItems = try EasySaleLine.inputs(separate, money: money)
        check(standaloneItems.first?.unitPrice == 5, "Stand sold alone keeps its entered price")
        separate[0].price = "wrong"
        do { _ = try EasySaleLine.inputs(separate, money: money); preconditionFailure("Invalid price accepted") } catch { checks += 1 }
        separate[0].price = "5"; separate[0].quantity = 2
        let original = money
        do { _ = try EasySaleLine.inputs(separate, money: money); preconditionFailure("Oversold stock accepted") } catch { checks += 1 }
        check(money == original, "Invalid draft never changes money or stock")
        do { _ = try EasySaleLine.inputs([], money: money); preconditionFailure("Empty sale accepted") } catch { checks += 1 }
        let next = EasySaleLine.make(money: money)
        check(next.first { $0.id == card.id }?.price == SaleAmountFormatting.text(for: 12.5), "Next sale suggests the actual last card price")
        var handoff = NFCSaleHandoff(owner: "sale@example.invalid", recordID: record.id)
        let records: Set<UUID> = [record.id]
        check(!handoff.shouldPrompt(owner: handoff.owner, recordIDs: records), "Opening the handoff does not immediately ask for a sale")
        handoff.launched = true
        check(!handoff.shouldPrompt(owner: handoff.owner, recordIDs: records), "Question waits for leaving and returning from writer")
        handoff.leftApp = true
        check(handoff.shouldPrompt(owner: handoff.owner, recordIDs: records), "Successful writer return offers sale")
        check(!handoff.shouldPrompt(owner: "other@example.invalid", recordIDs: records) && !handoff.shouldPrompt(owner: nil, recordIDs: records), "Pending question never crosses accounts or logout")
        check(!handoff.shouldPrompt(owner: handoff.owner, recordIDs: []), "Deleted business never prompts a sale")
        let recovered = try JSONDecoder().decode(NFCSaleHandoff.self, from: JSONEncoder().encode(handoff))
        check(recovered == handoff && recovered.shouldPrompt(owner: handoff.owner, recordIDs: records), "Question survives app termination without claiming a physical write or creating money")
        print("Easy sales and NFC follow-up: \(checks) checks passed")
    }
}
