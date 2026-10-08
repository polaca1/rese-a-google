import Foundation
import Combine
import CryptoKit

enum DesktopError: LocalizedError {
    case invalidProfile, invalidBusiness, invalidDate, missingBusiness, damagedStore, noUndo
    var errorDescription: String? {
        switch self {
        case .invalidProfile: return "Introduce el correo de tu cuenta de iPhone para poder intercambiar copias."
        case .invalidBusiness: return "Añade un nombre y unas coordenadas válidas al negocio."
        case .invalidDate: return "La visita debe ser futura y el aviso no puede ser posterior a ella."
        case .missingBusiness: return "La ficha de este negocio ya no está disponible. El movimiento se conserva en el historial."
        case .damagedStore: return "No se han podido leer tus datos. El archivo original se conserva; puedes recuperar una copia desde Archivo."
        case .noUndo: return "No hay cambios que deshacer."
        }
    }
}

/// The same validated domain and backup format as iPhone, committed as one atomic file.
/// UI state changes only after writing succeeds, so a disk error never silently loses money.
@MainActor final class MacStore: ObservableObject {
    @Published private(set) var backup: BusinessBackup?
    @Published var errorMessage: String?
    @Published private(set) var undoTitle: String?
    @Published private(set) var damaged = false
    private struct UndoState { let title: String; let backup: BusinessBackup }
    private var undoStates: [UndoState] = []
    var didChange: (() -> Void)?
    let fileURL: URL
    var recoveryURL: URL { fileURL.deletingLastPathComponent().appendingPathComponent("Antes-de-importar.json") }
    var owner: String? { backup?.owner }
    var records: [VisitRecord] { backup?.records ?? [] }
    var money: MoneyLedger { backup?.money ?? MoneyLedger() }
    var upcoming: [VisitRecord] {
        records.filter { $0.status != .completed && $0.arrivedAt == nil && $0.reminderDate != nil }
            .sorted { $0.reminderDate! < $1.reminderDate! }
    }
    var soldCards: Int { money.sales.values.reduce(0) { $0 + $1.cards } }

    init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("reviewNfcGo", isDirectory: true).appendingPathComponent("Workspace.json")
        guard FileManager.default.fileExists(atPath: self.fileURL.path) else { return }
        do {
            let data = try Data(contentsOf: self.fileURL)
            backup = try Self.readBackup(data)
        } catch { damaged = true; errorMessage = DesktopError.damagedStore.localizedDescription }
    }
    static func readBackup(_ data: Data) throws -> BusinessBackup {
        guard data.count <= 25_000_000 else { throw BackupError.tooLarge }
        let header = try JSONDecoder().decode(BusinessBackup.self, from: data)
        return try BusinessBackup.decode(data, for: header.owner)
    }
    func createWorkspace(email: String) throws {
        let owner = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard owner.contains("@"), owner.count <= 254, backup == nil, !damaged else { throw DesktopError.invalidProfile }
        try write(BusinessBackup(owner: owner, records: [], money: MoneyLedger()))
    }
    func deactivateAccount() throws {
        guard let backup else { return }
        let hash = SHA256.hash(data: Data(backup.owner.utf8)).map { String(format: "%02x", $0) }.joined()
        let cached = fileURL.deletingLastPathComponent().appendingPathComponent("Account-" + hash + ".json")
        try backup.encoded().write(to: cached, options: .atomic)
        self.backup = nil; undoStates = []; undoTitle = nil
    }
    func activateAccount(_ email: String) throws {
        guard !damaged else { throw DesktopError.damagedStore }
        guard owner != email else { return }
        func cache(_ owner: String) -> URL {
            let hash = SHA256.hash(data: Data(owner.utf8)).map { String(format: "%02x", $0) }.joined()
            return fileURL.deletingLastPathComponent().appendingPathComponent("Account-" + hash + ".json")
        }
        if let backup { try backup.encoded().write(to: cache(backup.owner), options: .atomic) }
        let target = cache(email)
        let value = FileManager.default.fileExists(atPath: target.path)
            ? try BusinessBackup.decode(Data(contentsOf: target), for: email)
            : BusinessBackup(owner: email, records: [], money: MoneyLedger())
        try write(value); undoStates = []; undoTitle = nil
    }
    private func write(_ value: BusinessBackup) throws {
        let valid = try value.validated(for: value.owner)
        let data = try valid.encoded()
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: fileURL, options: .atomic)
        backup = valid; damaged = false; didChange?()
    }
    private func commit(_ next: BusinessBackup, title: String) throws {
        guard let previous = backup else { throw DesktopError.invalidProfile }
        var value = next; value.createdAt = Date()
        try write(value)
        undoStates.append(UndoState(title: title, backup: previous))
        undoStates = Array(undoStates.suffix(12)); undoTitle = title
    }
    func save(_ record: VisitRecord) throws {
        guard var value = backup else { throw DesktopError.invalidProfile }
        var record = record
        guard !record.place.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              (-90...90).contains(record.place.latitude), (-180...180).contains(record.place.longitude) else { throw DesktopError.invalidBusiness }
        record.normalizeSales()
        guard value.money.canAssign(record) else { throw MoneyError.insufficientStock }
        let old = value.records.first { $0.id == record.id }
        if record.reminderDate != old?.reminderDate || record.notificationDate != old?.notificationDate {
            if let visit = record.reminderDate {
                guard visit > Date(), (record.notificationDate ?? visit) > Date(), (record.notificationDate ?? visit) <= visit else { throw DesktopError.invalidDate }
                record.arrivedAt = nil
            }
        }
        if let index = value.records.firstIndex(where: { $0.id == record.id }) { value.records[index] = record }
        else {
            guard !value.records.contains(where: { $0.place.id == record.place.id }) else { throw DesktopError.invalidBusiness }
            value.records.insert(record, at: 0)
        }
        value.money.synchronize(value.records)
        try commit(value, title: old == nil ? "Añadir negocio" : "Editar negocio")
    }
    func arrive(_ id: UUID) throws {
        guard var record = records.first(where: { $0.id == id }) else { throw DesktopError.missingBusiness }
        record.arrivedAt = Date(); try save(record)
    }
    func tomorrow(_ id: UUID) throws {
        guard var record = records.first(where: { $0.id == id }) else { throw DesktopError.missingBusiness }
        let date = Calendar.current.date(byAdding: .day, value: 1, to: Date())!
        record.status = .pending; record.arrivedAt = nil; record.reminderDate = date
        record.notificationDate = date.addingTimeInterval(-1800); try save(record)
    }
    func delete(_ id: UUID) throws {
        guard var value = backup else { throw DesktopError.invalidProfile }
        value.records.removeAll { $0.id == id }
        // Historical income and sold inventory deliberately survive deletion of a business.
        try commit(value, title: "Eliminar negocio")
    }
    func addExpense(title: String, amount: Double, quantity: Int, productID: UUID?, newProduct: InventoryProduct?, date: Date,
                    merchant: String, method: String, url: String, notes: String) throws {
        guard var value = backup else { throw DesktopError.invalidProfile }
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw MoneyError.invalidProduct }
        try value.money.addExpense(title: title, amount: amount, quantity: quantity, productID: productID, newProduct: newProduct,
                                   date: date, merchant: merchant, method: method, url: url, notes: notes)
        if let id = productID, let index = value.money.products.firstIndex(where: { $0.id == id }), !url.isEmpty {
            value.money.products[index].purchaseURL = url
        }
        try commit(value, title: "Registrar gasto")
    }
    func reverseExpense(_ id: UUID) throws {
        guard var value = backup else { throw DesktopError.invalidProfile }
        try value.money.reverseExpense(id); try commit(value, title: "Devolver gasto")
    }
    func receiveStock(title: String, quantity: Int, productID: UUID, newProduct: InventoryProduct?, origin: InventoryAcquisition, date: Date, notes: String) throws {
        guard var value = backup else { throw DesktopError.invalidProfile }
        try value.money.receiveStock(title: title, quantity: quantity, productID: productID, newProduct: newProduct, origin: origin, date: date, notes: notes)
        try commit(value, title: "Añadir existencias sin coste")
    }
    func adjustStock(_ id: UUID, quantity: Int, reason: String) throws {
        guard var value = backup else { throw DesktopError.invalidProfile }
        guard !reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw MoneyError.invalidProduct }
        try value.money.adjustStock(id, quantity: quantity, reason: reason); try commit(value, title: "Ajustar existencias")
    }
    func undo() throws {
        guard let last = undoStates.last, var value = backup else { throw DesktopError.noUndo }
        value.records = last.backup.records
        value.money.undo(to: last.backup.money, records: value.records)
        value.createdAt = Date()
        try write(value); undoStates.removeLast(); undoTitle = undoStates.last?.title
    }
    func importBackup(_ next: BusinessBackup) throws {
        let next = try next.validated(for: next.owner)
        // Preserve the actual previous bytes, including a damaged file, before replacement.
        if FileManager.default.fileExists(atPath: fileURL.path) {
            let previous = try Data(contentsOf: fileURL)
            try previous.write(to: recoveryURL, options: .atomic)
        }
        try write(next); undoStates.removeAll(); undoTitle = nil
    }
    func exportData() throws -> Data {
        guard let backup else { throw DesktopError.invalidProfile }
        return try backup.encoded()
    }
    func run(_ action: () throws -> Void) { do { try action() } catch { errorMessage = error.localizedDescription } }
}

struct CashDay: Identifiable {
    let date: Date
    let income: Int64
    let expenses: Int64
    var id: Date { date }
}
enum DesktopAnalytics {
    static func days(_ money: MoneyLedger, endingAt now: Date = Date(), count: Int = 14, calendar: Calendar = .current) -> [CashDay] {
        let today = calendar.startOfDay(for: now)
        return (0..<count).reversed().map { offset in
            let day = calendar.date(byAdding: .day, value: -offset, to: today)!
            let transactions = money.transactions.filter { calendar.isDate($0.date, inSameDayAs: day) }
            return CashDay(date: day, income: transactions.filter { $0.kind.isIncome }.reduce(0) { $0 + $1.cents },
                           expenses: -transactions.filter { [.expense, .refund].contains($0.kind) }.reduce(0) { $0 + $1.cents })
        }
    }
    static func csv(_ money: MoneyLedger) -> Data {
        func quoted(_ value: String, protect: Bool = true) -> String {
            // Neutralize spreadsheet formula injection in user-controlled fields.
            let safe = protect && ["=", "+", "-", "@", "\t", "\r"].contains(value.first.map(String.init) ?? "") ? "'" + value : value
            return "\"" + safe.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        let formatter = ISO8601DateFormatter()
        let header = "Fecha;Tipo;Concepto;Importe EUR;Unidades;Negocio ID;Proveedor;Pago;Enlace;Notas"
        let lines = money.history.map { item in
            [formatter.string(from: item.date), item.typeTitle, item.title,
             String(format: "%.2f", locale: Locale(identifier: "en_US_POSIX"), item.amount), String(item.quantity),
             item.businessID?.uuidString ?? "", item.merchant, item.paymentMethod, item.purchaseURL, item.notes].enumerated().map { quoted($0.element, protect: ![3, 4].contains($0.offset)) }.joined(separator: ";")
        }
        return Data(("\u{FEFF}" + ([header] + lines).joined(separator: "\r\n")).utf8)
    }
}

// Financial reports use integer cents and half-open date ranges, as the ledger does.
struct FinanceTotals {
    let income: Int64
    let expenses: Int64
    var result: Int64 { income - expenses }
    init(_ transactions: [MoneyTransaction]) {
        income = transactions.filter { $0.kind.isIncome }.reduce(0) { $0 + $1.cents }
        expenses = -transactions.filter { [.expense, .refund].contains($0.kind) }.reduce(0) { $0 + $1.cents }
    }
}
struct FinancePoint: Identifiable {
    let date: Date
    let income: Int64
    let expenses: Int64
    let balance: Int64
    var id: Date { date }
}
struct FinanceCategory: Identifiable {
    let title: String
    let cents: Int64
    var id: String { title }
}
struct FinanceBusiness: Identifiable {
    let id: UUID
    let title: String
    let cents: Int64
    let cards: Int
    let lastTransactionID: UUID
}
struct FinanceReport {
    let interval: DateInterval
    let previousInterval: DateInterval
    let totals: FinanceTotals
    let previousTotals: FinanceTotals
    let transactions: [MoneyTransaction]
    let points: [FinancePoint]
    let categories: [FinanceCategory]
    let businesses: [FinanceBusiness]
    let granularity: Calendar.Component
    let cards: Int
    let openingBalance: Int64
    var closingBalance: Int64 { openingBalance + totals.result }
    var label: String {
        let last = interval.end.addingTimeInterval(-1)
        return interval.start.formatted(date: .abbreviated, time: .omitted) + " – " + last.formatted(date: .abbreviated, time: .omitted)
    }
    var positiveCategories: [FinanceCategory] { categories.filter { $0.cents > 0 } }
    var csv: Data { var ledger = MoneyLedger(); ledger.transactions = transactions; return DesktopAnalytics.csv(ledger) }
    init(money: MoneyLedger, records: [VisitRecord], start: Date, end: Date, calendar: Calendar = .current) {
        let first = calendar.startOfDay(for: start)
        let last = max(first, calendar.startOfDay(for: end))
        let exclusive = calendar.date(byAdding: .day, value: 1, to: last)!
        let window = DateInterval(start: first, end: exclusive)
        interval = window
        let days = max(1, calendar.dateComponents([.day], from: first, to: exclusive).day ?? 1)
        let previousWindow = DateInterval(start: calendar.date(byAdding: .day, value: -days, to: first)!, end: first)
        previousInterval = previousWindow
        func includes(_ item: MoneyTransaction, _ range: DateInterval) -> Bool { item.date >= range.start && item.date < range.end }
        transactions = money.history.filter { includes($0, window) }
        totals = FinanceTotals(transactions)
        previousTotals = FinanceTotals(money.transactions.filter { includes($0, previousWindow) })
        openingBalance = money.transactions.filter { $0.date < first }.reduce(0) { $0 + $1.cents }
        cards = transactions.filter { $0.kind.isIncome }.reduce(0) { $0 + $1.quantity }
        let bucketSize: Calendar.Component = days > 1095 ? .year : days > 90 ? .month : .day
        granularity = bucketSize
        let grouped = Dictionary(grouping: transactions) { calendar.dateInterval(of: bucketSize, for: $0.date)!.start }
        var date = calendar.dateInterval(of: bucketSize, for: first)!.start
        var running = openingBalance
        var result: [FinancePoint] = []
        while date < exclusive {
            let bucket = FinanceTotals(grouped[date] ?? [])
            running += bucket.result
            result.append(FinancePoint(date: date, income: bucket.income, expenses: bucket.expenses, balance: running))
            date = calendar.date(byAdding: granularity, value: 1, to: date)!
        }
        points = result
        let products = Dictionary(uniqueKeysWithValues: money.products.map { ($0.id, $0.kind.title) })
        let expenses = Dictionary(grouping: transactions.filter { [.expense, .refund].contains($0.kind) }) { item in
            item.productID.flatMap { products[$0] } ?? "Otros gastos"
        }
        categories = expenses.map { FinanceCategory(title: $0.key, cents: -$0.value.reduce(0) { $0 + $1.cents }) }
            .sorted { $0.cents == $1.cents ? $0.title < $1.title : $0.cents > $1.cents }
        let names = Dictionary(uniqueKeysWithValues: records.map { ($0.id, $0.place.name) })
        let sales = Dictionary(grouping: transactions.filter { $0.kind.isIncome && $0.businessID != nil }) { $0.businessID! }
        businesses = sales.map { id, items in
            FinanceBusiness(id: id, title: names[id] ?? items[0].title,
                            cents: items.reduce(0) { $0 + $1.cents }, cards: items.reduce(0) { $0 + $1.quantity }, lastTransactionID: items[0].id)
        }.sorted { $0.cents == $1.cents ? $0.title < $1.title : $0.cents > $1.cents }
    }
}
