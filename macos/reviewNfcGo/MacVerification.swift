#if DEBUG
import SwiftUI
import AppKit

@MainActor enum MacVerification {
    static func run(store: MacStore, navigation: MacNavigation, output: URL) async {
        var checks: [String] = []
        do {
            try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
            func check(_ value: Bool, _ label: String) throws {
                guard value else { throw NSError(domain: "DesktopVerification", code: 1, userInfo: [NSLocalizedDescriptionKey: label]) }
                checks.append(label)
            }
            let owner = "pablo@example.invalid"
            try store.createWorkspace(email: owner)
            let card = InventoryProduct(name: "Tarjeta NFC", kind: .nfcCard, color: "Azul")
            try store.addExpense(title: card.displayName, amount: 30, quantity: 10, productID: card.id, newProduct: card,
                                 date: Date().addingTimeInterval(-86400), merchant: "Proveedor", method: "Tarjeta", url: "https://example.org/tarjetas", notes: "Compra inicial")
            try check(store.money.balanceCents == -3000 && store.money.stock(card.id) == 10, "Compra con saldo negativo y stock")
            let place = PlaceResult(id: "verification-cafe", name: "Café de la Plaza", address: "Plaza Mayor, Badajoz", latitude: 38.878, longitude: -6.971)
            var record = VisitRecord(place: place, earnings: 40, cardsSold: 4, unitEarnings: 10, inventoryProductID: card.id, status: .completed)
            try store.save(record)
            try check(store.money.balanceCents == 1000 && store.money.stock(card.id) == 6 && store.money.profitCents(record.id) == 2800, "Venta, saldo y beneficio")
            let count = store.money.transactions.count; try store.save(record)
            try check(store.money.transactions.count == count, "Guardar sin cambios no duplica ingresos")
            record.cardsSold = 6; try store.save(record)
            try check(store.money.balanceCents == 3000 && store.money.lowStockProducts.count == 1, "Editar venta calcula diferencia y stock bajo")
            try store.undo()
            try check(store.money.balanceCents == 1000 && store.money.stock(card.id) == 6 && store.money.transactions.count > count, "Deshacer conserva movimientos compensatorios")
            let snapshot = try MacStore.readBackup(store.exportData())
            let reloaded = MacStore(fileURL: store.fileURL)
            try check(reloaded.money == store.money && reloaded.records == store.records, "Persistencia conjunta de negocios y dinero")
            try store.delete(record.id)
            try check(store.money.balanceCents == 1000 && store.money.stock(card.id) == 6 && store.records.isEmpty, "Borrar ficha conserva ingreso y tarjetas")
            try store.importBackup(snapshot)
            try check(store.money.transactions.count == snapshot.money.transactions.count && store.records == snapshot.records, "Importar copia no duplica ventas")
            try check(try MacStore.readBackup(Data(contentsOf: store.recoveryURL)).records.isEmpty, "Copia anterior a importación disponible")
            var bad = snapshot; bad.records[0].inventoryProductID = UUID()
            let bytes = try Data(contentsOf: store.fileURL)
            do { try store.importBackup(bad); throw DesktopError.invalidBusiness } catch is BackupError {}
            try check(try Data(contentsOf: store.fileURL) == bytes, "Copia inválida no modifica el archivo")
            var stockExceeded = record; stockExceeded.cardsSold = 100
            do { try store.save(stockExceeded); throw DesktopError.invalidBusiness } catch MoneyError.insufficientStock {}
            try check(store.money.stock(card.id) == 6, "Venta sin stock rechazada")
            let failedStore = MacStore(fileURL: store.fileURL.appendingPathComponent("imposible.json"))
            do { try failedStore.createWorkspace(email: owner); throw DesktopError.invalidBusiness } catch {}
            try check(failedStore.owner == nil, "Error de escritura no crea estado falso")
            let date = Date().addingTimeInterval(3600.123)
            let future = VisitRecord(place: PlaceResult(id: "local-panaderia", name: "Panadería San Juan", address: "Calle San Juan, Badajoz", latitude: 38.879, longitude: -6.967),
                                     notes: "Preguntar por el encargado", status: .pending, reminderDate: date, notificationDate: date.addingTimeInterval(-1800))
            try store.save(future)
            let encoded = try store.exportData()
            try check(try BusinessBackup.decode(encoded, for: owner).records.first(where: { $0.id == future.id })?.reminderDate == date, "Formato de copia compatible con iPhone y fechas exactas")
            try store.arrive(future.id)
            try check(!store.upcoming.contains(where: { $0.id == future.id }), "Llegada retira visita pendiente")
            try store.tomorrow(future.id)
            try check(Calendar.current.isDateInTomorrow(store.records.first(where: { $0.id == future.id })!.reminderDate!), "Volver mañana")
            navigation.openBusiness(future.id, store: store)
            try check(navigation.section == .businesses && navigation.selectedBusiness == future.id, "Navegación a ficha real")
            let csv = String(data: DesktopAnalytics.csv(store.money), encoding: .utf8)!
            try check(csv.contains("Concepto") && csv.contains("Café de la Plaza") && csv.contains("30.00"), "Exportación CSV con operaciones")
            try check(DesktopAnalytics.days(store.money).count == 14, "Gráfico de catorce días")

            let made = InventoryProduct(name: "Stand fabricado", kind: .stand)
            let beforeFree = store.money.balanceCents
            try store.receiveStock(title: made.name, quantity: 2, productID: made.id, newProduct: made, origin: .manufactured, date: Date(), notes: "Lote propio")
            try check(store.money.balanceCents == beforeFree && store.money.stock(made.id) == 2 && store.money.averageCostCents(made.id) == 0, "Fabricado a cero euros sin alterar saldo")
            _ = try MacStore.readBackup(store.exportData())
            try store.undo()
            try check(store.money.stock(made.id) == 0 && store.money.purchased(made.id) == 0, "Deshacer entrada sin coste conserva historial")
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(identifier: "Europe/Madrid")!
            let day = calendar.date(from: DateComponents(year: 2026, month: 3, day: 28))!
            let next = calendar.date(byAdding: .day, value: 1, to: day)!
            let cutoff = calendar.date(byAdding: .day, value: 2, to: day)!
            let ledgerBusiness = UUID()
            var analytical = MoneyLedger()
            analytical.products = [card]
            analytical.transactions = [
                MoneyTransaction(date: day.addingTimeInterval(-3600), kind: .income, title: "Anterior", cents: 800),
                MoneyTransaction(date: day, kind: .income, title: "Negocio histórico", cents: 10000, businessID: ledgerBusiness, quantity: 5),
                MoneyTransaction(date: next, kind: .incomeAdjustment, title: "Negocio histórico", cents: -2000, businessID: ledgerBusiness, quantity: -1),
                MoneyTransaction(date: day, kind: .expense, title: "Tarjetas", cents: -4000, productID: card.id),
                MoneyTransaction(date: next, kind: .refund, title: "Tarjetas", cents: 1000, productID: card.id),
                MoneyTransaction(date: cutoff, kind: .income, title: "Fuera", cents: 90000)]
            let financial = FinanceReport(money: analytical, records: [], start: day, end: next, calendar: calendar)
            try check(financial.totals.income == 8000 && financial.totals.expenses == 3000 && financial.totals.result == 5000, "Análisis incorpora devoluciones y correcciones sin duplicar ingresos")
            try check(financial.transactions.count == 4 && financial.previousTotals.income == 800, "Periodos incluyen el inicio y excluyen el final exacto")
            try check(financial.points.count == 2 && financial.openingBalance == 800 && financial.closingBalance == 5800 && financial.points.last?.balance == 5800, "Saldo acumulado parte del saldo anterior y resiste cambio de hora")
            try check(financial.categories.first?.cents == 3000 && financial.businesses.first?.cents == 8000 && financial.businesses.first?.cards == 4, "Categorías y negocios conservan ajustes y fichas eliminadas")
            let exported = String(data: financial.csv, encoding: .utf8)!
            try check(!exported.contains("Fuera") && exported.contains("Negocio histórico"), "CSV contiene solo las operaciones del periodo")
            let pdf = MacFinanceExport.pdf(financial, owner: owner)
            try check(pdf.starts(with: Data("%PDF".utf8)) && pdf.count > 1000, "Informe PDF nativo con datos reales y gráfica vectorial")
            try pdf.write(to: output.appendingPathComponent("informe-verificado.pdf"))
            let emptyReport = FinanceReport(money: MoneyLedger(), records: [], start: day, end: next, calendar: calendar)
            try check(emptyReport.totals.result == 0 && emptyReport.categories.isEmpty && emptyReport.businesses.isEmpty && emptyReport.points.count == 2, "Análisis vacío sin datos simulados ni divisiones por cero")
            let yearReport = FinanceReport(money: analytical, records: [], start: calendar.date(byAdding: .year, value: -1, to: day)!, end: next, calendar: calendar)
            try check(yearReport.granularity == .month && yearReport.points.count <= 14 && yearReport.points.last?.balance == 5800, "Periodos largos agrupan meses sin perder el saldo")
            // Screenshots always use an isolated workspace. Normal launches never seed sample data.
            var sample = try MacStore.readBackup(store.exportData())
            sample.records.append(VisitRecord(place: PlaceResult(id: "local-papeleria", name: "Papelería Central", address: "Av. de Europa, Badajoz", latitude: 38.882, longitude: -6.966),
                                              notes: "Mostrar el stand de sobremesa", status: .pending, reminderDate: Date().addingTimeInterval(7200), notificationDate: Date().addingTimeInterval(5400)))
            let stand = InventoryProduct(name: "Stand de sobremesa", kind: .stand)
            try sample.money.addExpense(title: stand.name, amount: 15, quantity: 3, productID: stand.id, newProduct: stand, date: Date(), merchant: "Proveedor", method: "Tarjeta", url: "https://example.org/stand", notes: "")
            sample.money.synchronize(sample.records); try store.importBackup(sample)
            navigation.selectedBusiness = record.id
            for section in MacSection.allCases {
                navigation.section = section
                try await Task.sleep(for: .milliseconds(1000))
                try capture(name: "mac-" + section.id, output: output)
            }
            NSApp.appearance = NSAppearance(named: .darkAqua)
            navigation.section = .dashboard; try await Task.sleep(for: .milliseconds(800)); try capture(name: "mac-dark", output: output)
            NSApp.appearance = NSAppearance(named: .aqua)
            navigation.sheet = .business(future.id); try await Task.sleep(for: .milliseconds(800)); try capture(name: "mac-editor", output: output)
            navigation.sheet = nil
            try report(passed: true, checks: checks, error: nil, output: output)
        } catch { try? report(passed: false, checks: checks, error: error.localizedDescription, output: output) }
        NSApp.terminate(nil)
    }
    private static func capture(name: String, output: URL) throws {
        guard let window = NSApp.windows.first(where: { $0.isVisible && $0.contentView != nil }), let view = (window.attachedSheet ?? window).contentView,
              let representation = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { throw DesktopError.invalidBusiness }
        view.cacheDisplay(in: view.bounds, to: representation)
        guard let png = representation.representation(using: .png, properties: [:]) else { throw DesktopError.invalidBusiness }
        try png.write(to: output.appendingPathComponent(name + ".png"))
    }
    private static func report(passed: Bool, checks: [String], error: String?, output: URL) throws {
        var json: [String: Any] = ["passed": passed, "checks": checks]
        if let error { json["error"] = error }
        try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys]).write(to: output.appendingPathComponent("verification.json"))
    }
}
#endif
