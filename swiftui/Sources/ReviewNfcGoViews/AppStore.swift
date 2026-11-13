import SwiftUI
import CryptoKit

// MARK: - App data

@MainActor
final class AppStore: ObservableObject {
    static let shared = AppStore()
    @Published var records: [VisitRecord] = []
    @Published private(set) var money = MoneyLedger()
    @Published private(set) var hasLoadedRecords = false
    @Published private(set) var loadedUserEmail: String?
    private var userKey: String?
    @Published private(set) var undoTitle: String?
    private struct UndoState: Codable { var title: String; var records: [VisitRecord]; var money: MoneyLedger; var photo: Data? = nil; var restoresPhoto = false }
    private var undoStates: [UndoState] = []
    private var undoKey: String { "resenago.undo.\(userKey ?? "guest")" }
    var didChange: (() -> Void)?
    var restorePhoto: ((Data?) -> Void)?

    var totalEarnings: Double { Double(money.incomeCents) / 100 }
    var totalCardsSold: Int { money.allCardsSold }
    var pendingReminders: [VisitRecord] {
        records.filter { $0.reminderDate != nil && $0.status != .completed && $0.arrivedAt == nil }
            .sorted { ($0.reminderDate ?? .distantFuture) < ($1.reminderDate ?? .distantFuture) }
    }

    func switchUser(_ email: String?) {
        hasLoadedRecords = false
        userKey = email
        undoStates = UserDefaults.standard.data(forKey: undoKey).flatMap { try? JSONDecoder().decode([UndoState].self, from: $0) } ?? []
        undoTitle = undoStates.last?.title
        load()
        money = UserDefaults.standard.data(forKey: MoneyLedger.storageKey(email)).flatMap { try? JSONDecoder().decode(MoneyLedger.self, from: $0) } ?? MoneyLedger()
        money.synchronize(records)
        persistMoney()
        loadedUserEmail = email
        AlertHistoryStore.shared.switchUser(email, records: records)
        hasLoadedRecords = true
        ReminderCoordinator.replaceRecords(records)
        publishWidgets()
    }

    func addOrUpdatePlace(_ place: PlaceResult) {
        remember("Guardar negocio")
        if let index = records.firstIndex(where: { $0.place.id == place.id }) {
            records[index].place = place
            records[index].createdAt = Date()
        } else {
            records.insert(VisitRecord(place: place), at: 0)
        }
        save()
    }

    func saveReminder(for place: PlaceResult, visitDate: Date, notificationDate: Date, notes: String) -> VisitRecord {
        remember("Cambiar visita")
        var record: VisitRecord
        if let index = records.firstIndex(where: { $0.place.id == place.id }) {
            records[index].place = place
            records[index].arrivedAt = nil
            records[index].status = .pending
            records[index].reminderDate = visitDate
            records[index].notificationDate = notificationDate
            records[index].notes = notes
            record = records[index]
        } else {
            record = VisitRecord(place: place, notes: notes, status: .pending, reminderDate: visitDate, notificationDate: notificationDate)
            records.insert(record, at: 0)
        }
        save()
        return record
    }

    @discardableResult
    func update(_ record: VisitRecord) -> Bool {
        guard let index = records.firstIndex(where: { $0.id == record.id }) else { return false }
        var value = record
        value.normalizeSales()
        if value.reminderDate != records[index].reminderDate { value.arrivedAt = nil }
        guard money.canAssign(value), MoneyLedger.cents(value.earnings) != nil else { return false }
        if value == records[index] { return true }
        value.trackChanges(from: records[index])
        remember("Editar negocio")
        records[index] = value
        save()
        return true
    }

    func delete(at offsets: IndexSet) {
        remember("Eliminar negocio")
        records.remove(atOffsets: offsets)
        save()
    }

    private func storageKey() -> String {
        "resenago.records.\(userKey ?? "guest")"
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: storageKey()),
              let decoded = try? JSONDecoder().decode([VisitRecord].self, from: data) else {
            records = []
            return
        }
        records = decoded
    }

    private func save() {
        if let data = try? JSONEncoder().encode(records) {
            UserDefaults.standard.set(data, forKey: storageKey())
        }
        money.synchronize(records)
        persistMoney()
        AlertHistoryStore.shared.updateRecords(records)
        ReminderCoordinator.replaceRecords(records)
        publishWidgets()
    }

    private func persistMoney() {
        if let data = try? JSONEncoder().encode(money) { UserDefaults.standard.set(data, forKey: MoneyLedger.storageKey(userKey)) }
    }
    func addExpense(title: String, amount: Double, quantity: Int, productID: UUID?, newProduct: InventoryProduct?, date: Date,
                    merchant: String, method: String, url: String, notes: String, replacing: UUID? = nil) throws {
        var updated = money
        // Insert replacement first so correcting the price of already-sold stock does not require returning it.
        try updated.addExpense(title: title, amount: amount, quantity: quantity, productID: productID, newProduct: newProduct,
            date: date, merchant: merchant, method: method, url: url, notes: replacing == nil ? notes : "Corrección de gasto. " + notes)
        if let replacing { try updated.reverseExpense(replacing) }
        if let id = productID, let index = updated.products.firstIndex(where: { $0.id == id }), !url.isEmpty {
            updated.products[index].purchaseURL = url
        }
        remember("Cambiar dinero o inventario")
        money = updated; persistMoney(); publishWidgets()
    }
    func reverseExpense(_ id: UUID) throws {
        var updated = money; try updated.reverseExpense(id)
        remember("Cambiar dinero o inventario")
        money = updated; persistMoney(); publishWidgets()
    }
    func receiveStock(title: String, quantity: Int, productID: UUID, newProduct: InventoryProduct?, origin: InventoryAcquisition, date: Date, notes: String) throws {
        var updated = money
        try updated.receiveStock(title: title, quantity: quantity, productID: productID, newProduct: newProduct, origin: origin, date: date, notes: notes)
        remember("Añadir existencias sin coste")
        money = updated; persistMoney(); publishWidgets()
    }
    func adjustStock(_ id: UUID, quantity: Int, reason: String) throws {
        var updated = money; try updated.adjustStock(id, quantity: quantity, reason: reason)
        remember("Cambiar dinero o inventario")
        money = updated; persistMoney(); publishWidgets()
    }
    private func remember(_ title: String, photo: Data? = nil, restoresPhoto: Bool = false) {
        guard hasLoadedRecords, userKey != nil else { return }
        undoStates.append(UndoState(title: title, records: records, money: money, photo: photo, restoresPhoto: restoresPhoto))
        undoStates = Array(undoStates.suffix(12))
        persistUndo()
    }
    private func persistUndo() {
        undoTitle = undoStates.last?.title
        if let data = try? JSONEncoder().encode(undoStates) { UserDefaults.standard.set(data, forKey: undoKey) }
    }
    func undoLastChange() {
        guard let state = undoStates.popLast(), userKey != nil else { return }
        records = state.records
        if state.restoresPhoto { money = state.money }
        else { money.undo(to: state.money, records: records) }
        if state.restoresPhoto { restorePhoto?(state.photo) }
        persistUndo(); save()
    }
    func backup(photo: Data? = nil) throws -> BusinessBackup {
        guard let userKey else { throw BackupError.wrongAccount }
        return BusinessBackup(owner: userKey, records: records, money: money, photo: photo)
    }
    func restore(_ backup: BusinessBackup, previousPhoto: Data? = nil) throws {
        let value = try backup.validated(for: userKey)
        // Keep a recovery copy even across app launches before replacing any data.
        let original = try self.backup(photo: previousPhoto).encoded()
        UserDefaults.standard.set(original, forKey: "resenago.preRestore.\(userKey ?? "guest")")
        remember("Restaurar copia", photo: previousPhoto, restoresPhoto: true)
        records = value.records; money = value.money
        save()
    }
    func registerQuickSale(recordID: UUID, items: [QuickSaleInput], payment: String) throws {
        guard let index = records.firstIndex(where: { $0.id == recordID }) else { throw BackupError.invalid }
        var next = money; var record = records[index]
        try next.registerSale(business: &record, items: items, payment: payment)
        remember("Registrar venta rápida"); money = next; records[index] = record; save()
    }
    func updateTracking(recordID: UUID, stage: ContactStage, note: String, visited: Bool) throws {
        guard var record = records.first(where: { $0.id == recordID }) else { throw BackupError.invalid }
        record.trackingStage = stage
        var events = record.followUp ?? []
        if !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { events.append(FollowUpEvent(text: note)) }
        if visited { record.arrivedAt = Date(); events.append(FollowUpEvent(text: "Visita realizada", isVisit: true)) }
        record.followUp = Array(events.suffix(1000))
        guard update(record) else { throw MoneyError.insufficientStock }
    }
    func setWeeklyGoals(_ value: WeeklyGoals) throws {
        guard (1...100_000).contains(value.cards), (1...100_000).contains(value.visits), (1...1_000_000_000).contains(value.profitCents) else { throw MoneyError.invalidAmount }
        remember("Cambiar objetivos"); money.weeklyGoals = value; persistMoney(); publishWidgets()
    }
    func saveQuote(_ quote: BusinessQuote) throws {
        guard records.contains(where: { $0.id == quote.businessID }) else { throw BackupError.invalid }
        var next = money; try next.saveQuote(quote)
        remember("Guardar presupuesto"); money = next; persistMoney(); publishWidgets()
    }
    func convertQuote(_ id: UUID, payment: String) throws {
        guard let quote = money.quotations?.first(where: { $0.id == id }), let i = records.firstIndex(where: { $0.id == quote.businessID }) else { throw BackupError.invalid }
        var next = money; var record = records[i]
        try next.convertQuote(id, business: &record, payment: payment)
        remember("Convertir presupuesto en venta"); money = next; records[i] = record; save()
    }
    func setMinimumStock(_ id: UUID, quantity: Int) throws {
        guard (0...100_000).contains(quantity), let i = money.products.firstIndex(where: { $0.id == id }) else { throw MoneyError.invalidProduct }
        remember("Cambiar stock mínimo"); money.products[i].minimumStock = quantity; persistMoney(); publishWidgets()
    }
    func saveClient(_ record: VisitRecord) throws {
        guard update(record) else { throw MoneyError.insufficientStock }
    }
    func recoveryBackup() throws -> BusinessBackup? {
        guard let data = UserDefaults.standard.data(forKey: "resenago.preRestore.\(userKey ?? "guest")") else { return nil }
        return try BusinessBackup.decode(data, for: userKey)
    }
    func refreshWidgets() {
        guard hasLoadedRecords else { return }
        publishWidgets(notifyChange: false)
    }
    private func publishWidgets(notifyChange: Bool = true) {
        if notifyChange { didChange?() }
        StockNotifications.refresh(money: money, owner: userKey)

        var snapshot = WidgetSnapshot(records: records, isSignedIn: userKey != nil)
        if userKey != nil {
            snapshot.moneyBalance = Double(money.balanceCents) / 100
            snapshot.moneyExpenses = Double(money.expenseCents) / 100
            snapshot.totalEarnings = totalEarnings
            snapshot.totalCards = totalCardsSold
            snapshot.moneyOperations = money.history.filter { $0.cents != 0 }.prefix(10).map {
                WidgetMoneyOperation(id: $0.id, name: $0.title, amount: $0.amount, date: $0.date,
                    businessID: $0.businessID.flatMap { id in records.contains(where: { $0.id == id }) ? id : nil })
            }
        }
        WidgetSharedStore.publish(snapshot)
        PhoneWatchCompanion.shared.publish(store: self)
    }
}
