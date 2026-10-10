#if DEBUG
import SwiftUI
import AppKit
import CryptoKit
import PDFKit

@MainActor enum MacVerification {
    static func run(store: MacStore, navigation: MacNavigation, output: URL) async {
        var checks: [String] = []
        do {
            try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
            func check(_ value: Bool, _ label: String) throws {
                guard value else { throw NSError(domain: "DesktopVerification", code: 1, userInfo: [NSLocalizedDescriptionKey: label]) }
                checks.append(label)
                try JSONSerialization.data(withJSONObject: ["checks": checks], options: [.prettyPrinted, .sortedKeys])
                    .write(to: output.appendingPathComponent("verification-progress.json"))
            }
            try await Task.sleep(for: .milliseconds(500))
            try capture(name: "mac-login", output: output)
            checks += try await verifyCentralAccounts()
            checks += try await verifySupabaseAccounts()
            checks += try await verifyGoogleAccounts()
            let liveSuite = "reviewNfcGo.live-service." + UUID().uuidString
            let liveDefaults = UserDefaults(suiteName: liveSuite)!
            defer { liveDefaults.removePersistentDomain(forName: liveSuite) }
            let liveAuth = RemoteAuthClient(defaults: liveDefaults, credentialService: liveSuite)
            let googleReady = try await liveAuth.verifyLiveGoogleService()
            try check(googleReady && !liveAuth.signedIn, "La app nativa conecta con la configuración y Google de Supabase reales sin crear cuentas")
            checks += try await verifyCloudData()
            checks += try await verifyCloudTransport()
            checks += try await verifyAutomaticCloudChanges()
            let owner = "pablo@example.invalid"
            let transitionURL = output.appendingPathComponent("transition/Workspace.json")
            let transition = MacStore(fileURL: transitionURL)
            try check(!transition.hasWorkspace, "Mac nuevo muestra el inicio de sesión")
            try transition.activateAccount(owner)
            try check(transition.hasWorkspace && transition.owner == owner, "Iniciar sesión permite pasar al panel del Mac")
            let imported = BusinessBackup(owner: owner, records: [], money: MoneyLedger())
            try transition.deactivateAccount()
            try check(!transition.hasWorkspace && !MacStore(fileURL: transitionURL).hasWorkspace, "Cerrar sesión vuelve al acceso incluso al reiniciar")
            try transition.importBackup(imported)
            try check(transition.hasWorkspace, "Importar JSON abre el panel local sin exigir una sesión de nube")
            try transition.deactivateAccount()
            let damagedBytes = Data("archivo anterior ilegible".utf8)
            try damagedBytes.write(to: transitionURL)
            let damagedStore = MacStore(fileURL: transitionURL)
            try damagedStore.activateAccount(owner)
            let preserved = try FileManager.default.contentsOfDirectory(at: transitionURL.deletingLastPathComponent(), includingPropertiesForKeys: nil).filter { $0.lastPathComponent.hasPrefix("Recuperacion-") }
            try check(damagedStore.hasWorkspace && !damagedStore.damaged && preserved.count == 1, "Archivo antiguo dañado no bloquea el inicio de sesión")
            try check(try Data(contentsOf: preserved[0]) == damagedBytes, "Se conserva íntegro el archivo dañado para recuperación")
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
            var quoteClient = VisitRecord(place: PlaceResult(id: "quote-client", name: "Cliente de presupuesto", address: "", latitude: 38.88, longitude: -6.97))
            quoteClient.contactName = "María"; quoteClient.contactPhone = "+34 600 000 000"
            try store.save(quoteClient)
            let quoteNow = Date()
            let quote = BusinessQuote(businessID: quoteClient.id, businessName: quoteClient.place.name, createdAt: quoteNow, expiresAt: quoteNow.addingTimeInterval(86400),
                items: [QuoteLine(productID: card.id, title: card.displayName, quantity: 2, unitPriceCents: 999)], discountPercent: 10, notes: String(repeating: "Condiciones de entrega\n", count: 200))
            try store.saveQuote(quote)
            let quotePDF = try QuotePDF.create(quote, owner: owner)
            guard let document = PDFDocument(url: quotePDF) else { throw DesktopError.invalidBusiness }
            try check(document.pageCount > 1 && document.string?.contains("PRESUPUESTO") == true && document.string?.contains("17,98") == true, "Presupuesto PDF paginado incluye cliente, descuento y total real")
            try Data(contentsOf: quotePDF).write(to: output.appendingPathComponent("presupuesto-verificado.pdf"))
            let oldBalance = store.money.balanceCents, oldStock = store.money.stock(card.id)
            try store.convertQuote(quote.id, payment: "Transferencia")
            try check(store.money.balanceCents == oldBalance + 1798 && store.money.stock(card.id) == oldStock - 2, "Mac convierte presupuesto en venta con stock y descuento exactos")
            let afterQuote = store.money
            do { try store.convertQuote(quote.id, payment: "Transferencia"); throw DesktopError.invalidBusiness } catch MoneyError.quoteAlreadySold {}
            try check(store.money == afterQuote, "Mac bloquea doble conversión de presupuesto")
            let majorReloaded = MacStore(fileURL: store.fileURL)
            try check(majorReloaded.records.first { $0.id == quoteClient.id }?.contactName == "María" && majorReloaded.money.quotations?.first?.saleID != nil, "Mac conserva contacto y presupuesto al volver a abrir")
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
    private static func verifyCentralAccounts() async throws -> [String] {
        var checks: [String] = []
        func check(_ value: Bool, _ label: String) throws {
            guard value else { throw NSError(domain: "CentralAccounts", code: 1, userInfo: [NSLocalizedDescriptionKey: label]) }
            checks.append(label)
        }
        let suite = "reviewNfcGo.auth-verification." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite); AuthVerificationProtocol.handler = nil }
        defaults.set("https://untrusted.example.com", forKey: "reviewNfcGo.accountsServer")
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AuthVerificationProtocol.self]
        let network = URLSession(configuration: configuration)
        let auth = RemoteAuthClient(defaults: defaults, credentialService: suite, networkSession: network)
        defer { auth.clearSession(); network.invalidateAndCancel() }
        var calls: [String] = []
        AuthVerificationProtocol.handler = { request in
            calls.append(request.url!.path)
            return (200, ["schema": 1, "serverURL": NSNull()])
        }
        do {
            _ = try await auth.authenticate(email: "pablo@example.com", password: "Verification-password", name: "Pablo")
            throw DesktopError.invalidBusiness
        } catch RemoteAuthError.notReady {}
        try check(!auth.signedIn && calls.count == 1 && !auth.configured, "Sin servidor no crea cuentas locales ni utiliza direcciones antiguas")
        var registrationChecked = false
        AuthVerificationProtocol.handler = { request in
            calls.append(request.url!.path)
            if request.url!.host == "raw.githubusercontent.com" { return (200, ["schema": 1, "serverURL": "https://accounts.example.com"]) }
            guard request.url!.host == "accounts.example.com", request.url!.path == "/v1/auth/register", request.httpMethod == "POST" else { throw URLError(.badServerResponse) }
            let body = try JSONSerialization.jsonObject(with: AuthVerificationProtocol.bodyData(request)) as? [String: String]
            registrationChecked = body?["email"] == "pablo@example.com" && body?["name"] == "Pablo" && body?["password"] == "Verification-password"
            return (201, ["token": "verification-token-opaque", "expiresAt": Date().timeIntervalSince1970 + 86400,
                          "user": ["name": "Pablo", "email": "pablo@example.com"]])
        }
        let user = try await auth.authenticate(email: " PABLO@example.com ", password: "Verification-password", name: "Pablo")
        try check(registrationChecked && user.email == "pablo@example.com" && auth.signedIn && calls.last == "/v1/auth/register", "Crear cuenta envía el registro al servidor común y conserva su sesión")
        let reloaded = RemoteAuthClient(defaults: defaults, credentialService: suite, networkSession: network)
        try check(reloaded.signedIn && reloaded.session?.user.email == user.email, "Sesión remota persiste en Keychain vinculada al servidor")
        AuthVerificationProtocol.handler = { _ in throw URLError(.notConnectedToInternet) }
        do { _ = try await auth.validate(); throw DesktopError.invalidBusiness } catch RemoteAuthError.unavailable {}
        try check(auth.signedIn, "Fallo temporal de conexión conserva una sesión existente sin simular una nueva")
        auth.clearSession()
        AuthVerificationProtocol.handler = { request in
            calls.append(request.url!.path)
            return (503, ["detail": "Servidor temporalmente desconectado"])
        }
        do {
            _ = try await auth.authenticate(email: "new@example.com", password: "Verification-password", name: "Nueva")
            throw DesktopError.invalidBusiness
        } catch RemoteAuthError.rejected {}
        try check(!auth.signedIn && calls.last == "/v1/auth/register", "Servidor apagado rechaza el registro: no hay sustituto local")
        let emptyDefaults = UserDefaults(suiteName: suite + ".empty")!
        defer { emptyDefaults.removePersistentDomain(forName: suite + ".empty") }
        let invalid = RemoteAuthClient(defaults: emptyDefaults, credentialService: suite + ".empty", networkSession: network)
        AuthVerificationProtocol.handler = { _ in (200, ["schema": 1, "serverURL": "http://unsafe.example.com"]) }
        do {
            _ = try await invalid.authenticate(email: "new@example.com", password: "Verification-password", name: "Nueva")
            throw DesktopError.invalidBusiness
        } catch RemoteAuthError.invalidURL {}
        try check(!invalid.signedIn && !invalid.configured, "La configuración automática rechaza servidores HTTP")
        return checks
    }
    private static func verifySupabaseAccounts() async throws -> [String] {
        var checks: [String] = []
        func check(_ value: Bool, _ label: String) throws {
            guard value else { throw NSError(domain: "SupabaseAccounts", code: 1, userInfo: [NSLocalizedDescriptionKey: label]) }
            checks.append(label)
        }
        let suite = "reviewNfcGo.supabase-verification." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AuthVerificationProtocol.self]
        let network = URLSession(configuration: configuration)
        let auth = RemoteAuthClient(defaults: defaults, credentialService: suite, networkSession: network)
        defer {
            auth.clearSession(); defaults.removePersistentDomain(forName: suite)
            AuthVerificationProtocol.handler = nil; network.invalidateAndCancel()
        }
        let key = "sb_publishable_verification0123456789"
        let manifest: [String: Any] = ["schema": 1, "provider": "supabase", "serverURL": "https://abcdefghijklmnopqrst.supabase.co", "publishableKey": key]
        let cloudUser: [String: Any] = ["id": UUID().uuidString, "email": "pablo@example.com", "user_metadata": ["name": "Pablo"]]
        var signupChecked = false
        AuthVerificationProtocol.handler = { request in
            if request.url!.host == "raw.githubusercontent.com" { return (200, manifest) }
            let body = try JSONSerialization.jsonObject(with: AuthVerificationProtocol.bodyData(request)) as? [String: Any]
            signupChecked = request.url!.path == "/auth/v1/signup" && request.httpMethod == "POST"
                && request.value(forHTTPHeaderField: "apikey") == key && request.value(forHTTPHeaderField: "Authorization") == nil
                && body?["email"] as? String == "pablo@example.com" && body?["password"] as? String == " Keep-spaces "
                && (body?["data"] as? [String: String])?["name"] == "Pablo"
            return (200, ["access_token": "cloud-access", "refresh_token": "cloud-refresh", "expires_in": 60, "user": cloudUser])
        }
        let user = try await auth.authenticate(email: " PABLO@example.com ", password: " Keep-spaces ", name: " Pablo ")
        try check(signupChecked && auth.signedIn && user.name == "Pablo", "Supabase recibe el registro con clave pública, nombre y contraseña sin modificar")
        let restored = RemoteAuthClient(defaults: defaults, credentialService: suite, networkSession: network)
        try check(restored.session?.refreshToken == "cloud-refresh" && restored.signedIn, "Keychain conserva la sesión de nube y su token de renovación")
        var refreshed = false
        AuthVerificationProtocol.handler = { request in
            if request.url!.host == "raw.githubusercontent.com" { return (200, manifest) }
            let body = try JSONSerialization.jsonObject(with: AuthVerificationProtocol.bodyData(request)) as? [String: String]
            refreshed = request.url!.path == "/auth/v1/token" && request.url!.query == "grant_type=refresh_token"
                && request.httpMethod == "POST" && body?["refresh_token"] == "cloud-refresh"
                && request.value(forHTTPHeaderField: "Authorization") == nil && request.value(forHTTPHeaderField: "apikey") == key
            return (200, ["access_token": "cloud-access-rotated", "refresh_token": "cloud-refresh-rotated", "expires_in": 3600, "user": cloudUser])
        }
        _ = try await restored.validate()
        let rotated = RemoteAuthClient(defaults: defaults, credentialService: suite, networkSession: network)
        try check(refreshed && rotated.session?.token == "cloud-access-rotated" && rotated.session?.refreshToken == "cloud-refresh-rotated", "Renovación usa el refresh token y guarda ambos tokens rotados")
        var validated = false
        AuthVerificationProtocol.handler = { request in
            if request.url!.host == "raw.githubusercontent.com" { return (200, manifest) }
            validated = request.url!.path == "/auth/v1/user" && request.httpMethod == "GET"
                && request.value(forHTTPHeaderField: "Authorization") == "Bearer cloud-access-rotated"
                && request.value(forHTTPHeaderField: "apikey") == key
            return (200, cloudUser)
        }
        _ = try await rotated.validate()
        try check(validated, "La validación consulta la cuenta real con JWT y clave pública")
        AuthVerificationProtocol.handler = { _ in throw URLError(.notConnectedToInternet) }
        do { _ = try await rotated.validate(); throw DesktopError.invalidBusiness } catch RemoteAuthError.unavailable {}
        try check(rotated.signedIn, "Una desconexión temporal no borra la sesión de Supabase")
        auth.clearSession(); restored.clearSession(); rotated.clearSession()
        AuthVerificationProtocol.handler = { request in
            if request.url!.host == "raw.githubusercontent.com" { return (200, manifest) }
            return (200, ["user": cloudUser])
        }
        do {
            _ = try await auth.authenticate(email: "pablo@example.com", password: "Verification-password", name: "Pablo")
            throw DesktopError.invalidBusiness
        } catch RemoteAuthError.rejected(let message) {
            try check(!auth.signedIn && message.contains("confirmar"), "El registro pendiente de confirmar no inventa una sesión local")
        }
        AuthVerificationProtocol.handler = { _ in (400, ["error_code": "invalid_credentials"]) }
        do {
            _ = try await auth.authenticate(email: "pablo@example.com", password: "Wrong-password")
            throw DesktopError.invalidBusiness
        } catch RemoteAuthError.rejected(let message) {
            try check(!auth.signedIn && message == "Correo o contraseña incorrectos.", "Credenciales incorrectas rechazadas con mensaje en español")
        }
        for (label, changed) in [
            ("La app rechaza claves secretas antes de transmitir credenciales", ["publishableKey": "sb_secret_never_embed_this_key"]),
            ("El proveedor de nube rechaza destinos ajenos a Supabase", ["serverURL": "https://untrusted.example.com"])] {
            let isolatedSuite = suite + UUID().uuidString
            let isolatedDefaults = UserDefaults(suiteName: isolatedSuite)!
            defer { isolatedDefaults.removePersistentDomain(forName: isolatedSuite) }
            let invalid = RemoteAuthClient(defaults: isolatedDefaults, credentialService: isolatedSuite, networkSession: network)
            var calls = 0
            var invalidManifest = manifest
            for (field, value) in changed { invalidManifest[field] = value }
            AuthVerificationProtocol.handler = { _ in calls += 1; return (200, invalidManifest) }
            do {
                _ = try await invalid.authenticate(email: "pablo@example.com", password: "Verification-password")
                throw DesktopError.invalidBusiness
            } catch RemoteAuthError.invalidURL {}
            try check(calls == 1 && !invalid.configured && !invalid.signedIn, label)
        }
        return checks
    }
    private static func verifyAutomaticCloudChanges() async throws -> [String] {
        let suite = "cloud-auto-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
        let store = MacStore(fileURL: folder.appendingPathComponent("Workspace.json"))
        let transport = CloudVerificationTransport()
        let sync = CloudBackupController(defaults: defaults)
        let owner = "automatic@example.com"
        try store.createWorkspace(email: owner)
        store.didChange = { [weak sync] in sync?.localChanged() }
        sync.connect(owner: owner, transport: transport, read: { try MacStore.readBackup(store.exportData()) }, apply: { try store.importBackup($0) })
        defer {
            sync.connect(owner: nil, transport: transport, read: { throw BackupError.invalid }, apply: { _ in })
            defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: folder)
        }
        func waitUntil(_ condition: () -> Bool) async throws {
            for _ in 0..<200 {
                if condition() { return }
                try await Task.sleep(for: .milliseconds(25))
            }
            throw NSError(domain: "AutomaticCloudChanges", code: 1, userInfo: [NSLocalizedDescriptionKey: "El cambio no se sincronizó automáticamente: " + sync.message])
        }
        try await waitUntil { sync.state == .empty }
        let product = InventoryProduct(name: "Tarjeta NFC", kind: .nfcCard, color: "Blanco")
        try store.addExpense(title: product.displayName, amount: 10, quantity: 10, productID: product.id, newProduct: product,
                             date: Date(), merchant: "Proveedor", method: "Tarjeta", url: "", notes: "")
        try await waitUntil { sync.state == .saved && transport.row?.payload.money.products.count == 1 && transport.row?.payload.money.balanceCents == -1000 }
        let sale = VisitRecord(place: PlaceResult(id: "automatic-sale", name: "Venta", address: "Centro", latitude: 38, longitude: -6),
                               earnings: 30, cardsSold: 3, unitEarnings: 10, inventoryProductID: product.id, status: .completed)
        try store.save(sale)
        try await waitUntil { sync.state == .saved && transport.row?.payload.money.balanceCents == 2000 && transport.row?.payload.money.stock(product.id) == 7 }
        try store.setWeeklyGoals(WeeklyGoals(cards: 40, visits: 8, profitCents: 12000))
        try await waitUntil { transport.row?.payload.money.weeklyGoals?.cards == 40 && sync.state == .saved }
        try store.registerQuickSale(recordID: sale.id, items: [QuickSaleInput(productID: product.id, quantity: 2, unitPrice: 10)], payment: "Bizum")
        try await waitUntil { transport.row?.payload.money.activeQuickSales.count == 1 && sync.state == .saved }
        try store.updateTracking(recordID: sale.id, stage: .sold, note: "Recibido", visited: true)
        try await waitUntil { transport.row?.payload.records.first?.followUp?.contains(where: { $0.text == "Recibido" }) == true && sync.state == .saved }
        try store.delete(sale.id)
        try await waitUntil { sync.state == .saved && transport.row?.payload.records.isEmpty == true && transport.row?.payload.money.balanceCents == 4000 }
        return ["Añadir un producto sube inventario y gasto automáticamente sin pulsar sincronizar",
                "Guardar una venta sube negocio, ingresos y stock automáticamente",
                "Objetivos, venta rápida y seguimiento se sincronizan sin intervención",
                "Eliminar un negocio sincroniza el cambio sin borrar su historial de ingresos"]
    }
    private static func verifyCloudTransport() async throws -> [String] {
        var checks: [String] = []
        func check(_ value: Bool, _ label: String) throws {
            guard value else { throw NSError(domain: "CloudTransport", code: 1, userInfo: [NSLocalizedDescriptionKey: label]) }; checks.append(label)
        }
        let suite = "cloud-transport-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        let configuration = URLSessionConfiguration.ephemeral; configuration.protocolClasses = [AuthVerificationProtocol.self]
        let network = URLSession(configuration: configuration)
        let auth = RemoteAuthClient(defaults: defaults, credentialService: suite, networkSession: network)
        defer { auth.clearSession(); defaults.removePersistentDomain(forName: suite); AuthVerificationProtocol.handler = nil; network.invalidateAndCancel() }
        let id = UUID().uuidString.lowercased(), email = "transport@example.com"
        let key = "sb_publishable_verification0123456789"
        let user: [String: Any] = ["id": id, "email": email]
        let manifest: [String: Any] = ["schema": 1, "provider": "supabase", "serverURL": "https://abcdefghijklmnopqrst.supabase.co", "publishableKey": key]
        var row: CloudBackupRecord?
        var verifiedHeaders = false, verifiedCAS = false, stale = false, forbidden = false
        var inserts = 0
        AuthVerificationProtocol.handler = { request in
            if request.url!.host == "raw.githubusercontent.com" { return (200, manifest) }
            if request.url!.path == "/auth/v1/settings" { return (200, ["external": ["google": true]]) }
            if request.url!.path == "/auth/v1/signup" || request.url!.path == "/auth/v1/token" { return (200, ["access_token": "private-access", "refresh_token": "private-refresh", "expires_in": 3600, "user": user]) }
            if request.url!.path == "/auth/v1/user" { return (200, user) }
            if request.url!.path == "/rest/v1/reviewnfcgo_backup_history" {
                let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!.queryItems!
                guard query.contains(URLQueryItem(name: "user_id", value: "eq." + id)), query.contains(URLQueryItem(name: "order", value: "revision.desc")), query.contains(URLQueryItem(name: "limit", value: "3")), request.value(forHTTPHeaderField: "Authorization") == "Bearer private-access" else { throw CloudBackupError.invalid }
                return (200, try JSONSerialization.jsonObject(with: JSONEncoder().encode(row.map { [$0] } ?? [])))
            }
            guard request.url!.path == "/rest/v1/reviewnfcgo_backups" else { throw CloudBackupError.invalid }
            verifiedHeaders = request.value(forHTTPHeaderField: "Authorization") == "Bearer private-access" && request.value(forHTTPHeaderField: "apikey") == key
            if forbidden { return (403, ["code": "42501"]) }
            if request.httpMethod != "GET" {
                let incoming = try JSONDecoder().decode(CloudBackupRecord.self, from: AuthVerificationProtocol.bodyData(request))
                if request.httpMethod == "PATCH" {
                    let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!.queryItems!
                    verifiedCAS = query.contains(URLQueryItem(name: "user_id", value: "eq." + id)) && query.contains(URLQueryItem(name: "revision", value: "eq.1")) && incoming.revision == 2
                    if stale { return (200, []) }
                }
                if request.httpMethod == "POST" { inserts += 1 }
                row = incoming
            }
            return (200, try JSONSerialization.jsonObject(with: JSONEncoder().encode(row.map { [$0] } ?? [])))
        }
        _ = try await auth.authenticate(email: email, password: "Test-only-password", name: "Cloud account")
        let record = VisitRecord(place: PlaceResult(id: "shared-business", name: "Negocio compartido", address: "Centro", latitude: 38, longitude: -6), earnings: 30, cardsSold: 3, unitEarnings: 10, status: .completed)
        var ledger = MoneyLedger(); ledger.synchronize([record])
        let backup = BusinessBackup(owner: email, records: [record], money: ledger)
        let first = try await auth.saveCloudBackup(backup, expectedRevision: nil)
        let versions = try await auth.loadCloudHistory(owner: email)
        try check(versions.count == 1 && versions[0].user_id == id, "REST consulta historial limitado y ordenado con la identidad autenticada")
        let restored = try await auth.loadCloudBackup(owner: email)
        try check(verifiedHeaders && first.user_id == id && restored?.payload.owner == email, "REST utiliza sesión privada e identidad de Supabase al guardar y recuperar")
        let googleUser = try await auth.authenticateWithGoogle(expectedEmail: email, openBrowser: { url in
            let query = URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems!
            let callback = query.first(where: { $0.name == "redirect_to" })!.value!
            return URL(string: callback + "?code=one-use-code#_=_")!
        })
        let googleBackup = try await auth.loadCloudBackup(owner: email)
        try check(googleUser.id == id && googleBackup?.payload.records == [record] && googleBackup?.payload.money.balanceCents == 3000 && inserts == 1,
                  "Cuenta normal seguida de Google conserva UUID, negocios e ingresos sin duplicar la copia")
        _ = try await auth.authenticate(email: email, password: "Test-only-password")
        let passwordBackup = try await auth.loadCloudBackup(owner: email)
        try check(passwordBackup?.payload.money == googleBackup?.payload.money && passwordBackup?.user_id == googleBackup?.user_id,
                  "Volver a entrar con contraseña recupera los mismos datos que Google")
        _ = try await auth.saveCloudBackup(backup, expectedRevision: 1)
        try check(verifiedCAS, "REST actualiza solo la revisión esperada de la cuenta autenticada")
        stale = true
        do { _ = try await auth.saveCloudBackup(backup, expectedRevision: 1); throw DesktopError.invalidBusiness }
        catch CloudBackupError.conflict { checks.append("REST detecta conflictos en vez de forzar sobrescritura") }
        forbidden = true
        do { _ = try await auth.loadCloudBackup(owner: email); throw DesktopError.invalidBusiness }
        catch CloudBackupError.notConfigured { checks.append("REST no presenta permisos denegados como nube vacía") }
        return checks
    }
    private static func verifyCloudData() async throws -> [String] {
        var checks: [String] = []
        func check(_ condition: Bool, _ label: String) throws {
            guard condition else { throw NSError(domain: "CloudData", code: 1, userInfo: [NSLocalizedDescriptionKey: label]) }
            checks.append(label)
        }
        let owner = "cloud@example.com"
        let suite = "cloud-data-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let transport = CloudVerificationTransport()
        let record = VisitRecord(place: PlaceResult(id: "cloud-cafe", name: "Café", address: "Centro", latitude: 38, longitude: -6), earnings: 20, cardsSold: 2, unitEarnings: 10, status: .completed)
        var ledger = MoneyLedger(); ledger.synchronize([record])
        let original = BusinessBackup(owner: owner, records: [record], money: ledger)
        var local = original
        let sync = CloudBackupController(defaults: defaults)
        sync.connect(owner: owner, transport: transport, read: { local }, apply: { local = $0 }, automatic: false)
        await sync.synchronize()
        try check(sync.state == .saved && transport.row?.payload.money.balanceCents == 2000, "Guardar negocio sube ingresos y datos a la nube")
        defaults.removePersistentDomain(forName: suite)
        local = BusinessBackup(owner: owner, records: [], money: MoneyLedger())
        let reinstall = CloudBackupController(defaults: defaults)
        reinstall.connect(owner: owner, transport: transport, read: { local }, apply: { local = $0 }, automatic: false)
        await reinstall.synchronize()
        try check(reinstall.state == .saved && local.records == original.records && local.money == original.money && transport.writes == 1, "Reinstalar y entrar recupera negocios y dinero sin sobrescribir la nube vacía")
        local.records[0].notes = "Cambio en iPhone"
        var remote = original; remote.records[0].notes = "Cambio en Mac"
        transport.row = CloudBackupRecord(user_id: "test", revision: 2, payload: remote)
        await reinstall.synchronize()
        try check(reinstall.state == .conflict && local.records[0].notes == "Cambio en iPhone" && transport.writes == 1, "Cambios simultáneos conservan ambas copias y piden resolver")
        await reinstall.resolve(useCloud: true)
        try check(local.records[0].notes == "Cambio en Mac" && defaults.data(forKey: "reviewNfcGo.cloud.recovery.local." + owner) != nil, "Resolver conserva recuperación antes de aplicar nube")
        transport.offline = true
        local.records[0].notes = "Sin conexión"
        await reinstall.synchronize()
        try check(local.records[0].notes == "Sin conexión" && transport.writes == 1, "Sin conexión conserva cambios locales pendientes")
        transport.offline = false
        await reinstall.synchronize()
        try check(reinstall.state == .saved && transport.row?.payload.records[0].notes == "Sin conexión", "Recuperar conexión sube los cambios pendientes")
        let historical = CloudBackupRecord(user_id: "test", revision: 1, payload: original)
        let revisionBeforeRestore = transport.row!.revision
        try await reinstall.restorePrevious(historical)
        try check(reinstall.state == .saved && local.records == original.records && transport.row?.revision == revisionBeforeRestore + 1, "Restaurar una versión antigua crea una revisión nueva sin rebobinar el servidor")
        try check(reinstall.recoveryData(remote: false) != nil && reinstall.recoveryData(remote: true) != nil, "Restaurar conserva copias locales y remotas anteriores")
        let history = try await reinstall.previousCopies()
        try check(!history.isEmpty && history.count <= 3, "Historial de recuperación devuelve las últimas versiones")
        var foreign = original; foreign.owner = "foreign@example.com"
        do { try await reinstall.restorePrevious(CloudBackupRecord(user_id: "other", revision: 1, payload: foreign)); throw DesktopError.invalidBusiness }
        catch BackupError.wrongAccount { checks.append("Restauración rechaza copias de otra cuenta") }
        let another = BusinessBackup(owner: "other@example.com", records: [], money: MoneyLedger())
        transport.row = CloudBackupRecord(user_id: "other", revision: 1, payload: another)
        await reinstall.synchronize()
        try check(local.owner == owner && local.records.count == 1 && reinstall.state != .saved, "Una respuesta de otra cuenta nunca sustituye los datos")
        var dated = original; dated.createdAt = Date().addingTimeInterval(100)
        try check(try original.cloudFingerprint() == dated.cloudFingerprint(), "La fecha de exportación no provoca conflictos falsos")
        return checks
    }
    private static func verifyGoogleAccounts() async throws -> [String] {
        var checks: [String] = []
        func check(_ value: Bool, _ label: String) throws {
            guard value else { throw NSError(domain: "GoogleAccounts", code: 1, userInfo: [NSLocalizedDescriptionKey: label]) }
            checks.append(label)
        }
        let suite = "reviewNfcGo.google-verification." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AuthVerificationProtocol.self]
        let network = URLSession(configuration: configuration)
        let auth = RemoteAuthClient(defaults: defaults, credentialService: suite, networkSession: network)
        defer {
            auth.clearSession(); defaults.removePersistentDomain(forName: suite)
            AuthVerificationProtocol.handler = nil; network.invalidateAndCancel()
        }
        let origin = "https://abcdefghijklmnopqrst.supabase.co"
        let key = "sb_publishable_verification0123456789"
        let manifest: [String: Any] = ["schema": 1, "provider": "supabase", "serverURL": origin, "publishableKey": key]
        var challenge = ""
        var exchanged = false
        var googleEnabled = true
        var responseEmail = "pablo@example.com"
        let accountID = UUID().uuidString
        var responseID = accountID
        var serverExpiry = Date().timeIntervalSince1970 - 7200
        var lifetime = 3600.0
        var exchangeFailure: URLError.Code?
        var usedTimeout: TimeInterval = 0
        AuthVerificationProtocol.handler = { request in
            if request.url!.host == "raw.githubusercontent.com" { return (200, manifest) }
            if request.url!.path == "/auth/v1/settings" { return (200, ["external": ["google": googleEnabled]]) }
            if request.url!.path == "/auth/v1/logout" { return (200, [:]) }
            if request.url!.path == "/auth/v1/user" { return (200, ["id": accountID, "email": "pablo@example.com"]) }
            let body = try JSONSerialization.jsonObject(with: AuthVerificationProtocol.bodyData(request)) as? [String: String]
            let verifier = body?["code_verifier"] ?? ""
            usedTimeout = request.timeoutInterval
            if let exchangeFailure { throw URLError(exchangeFailure) }
            exchanged = request.url!.path == "/auth/v1/token" && request.url!.query == "grant_type=pkce"
                && request.httpMethod == "POST" && request.value(forHTTPHeaderField: "apikey") == key
                && request.value(forHTTPHeaderField: "Authorization") == nil && body?["auth_code"] == "one-use-code"
                && verifier.count == 43 && GoogleOAuthRequest.base64URL(Data(SHA256.hash(data: Data(verifier.utf8)))) == challenge
            return (200, ["access_token": "google-" + responseEmail, "refresh_token": "google-refresh", "expires_in": lifetime, "expires_at": serverExpiry,
                          "user": ["id": responseID, "email": responseEmail, "user_metadata": ["full_name": "Pablo Google"]]])
        }
        func successfulBrowser(_ url: URL) throws -> URL {
            let query = URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems!
            challenge = query.first(where: { $0.name == "code_challenge" })!.value!
            guard query.first(where: { $0.name == "provider" })?.value == "google",
                  query.first(where: { $0.name == "code_challenge_method" })?.value == "s256",
                  query.first(where: { $0.name == "prompt" })?.value == "select_account" else { throw DesktopError.invalidBusiness }
            var callback = URLComponents(string: query.first(where: { $0.name == "redirect_to" })!.value!)!
            callback.queryItems = [URLQueryItem(name: "code", value: "one-use-code")]
            return callback.url!
        }
        let user = try await auth.authenticateWithGoogle(openBrowser: { try successfulBrowser($0) })
        try check(exchanged && auth.signedIn && user.email == "pablo@example.com" && user.name == "Pablo Google",
                  "Google intercambia código con PKCE, clave pública y nombre del perfil verificado")
        try check(auth.session!.expiresAt > Date().timeIntervalSince1970 + 3500 && usedTimeout == 60,
                  "Google usa la duración válida aunque el reloj del equipo difiera del servidor y permite completar el intercambio")
        let tokenBeforeInvalid = auth.session?.token
        lifetime = 0; serverExpiry = Date().timeIntervalSince1970 + 86400
        do {
            _ = try await auth.authenticateWithGoogle(openBrowser: { try successfulBrowser($0) })
            throw DesktopError.invalidBusiness
        } catch RemoteAuthError.rejected { }
        try check(auth.session?.token == tokenBeforeInvalid, "Una duración caducada no se acepta aunque la fecha absoluta sea futura")
        lifetime = 3600
        exchangeFailure = .timedOut
        do {
            _ = try await auth.authenticateWithGoogle(openBrowser: { try successfulBrowser($0) })
            throw DesktopError.invalidBusiness
        } catch RemoteAuthError.rejected(let message) {
            try check(message.contains("tardado") && auth.session?.token == tokenBeforeInvalid,
                      "Un timeout tras volver de Google explica el paso fallido y conserva la sesión anterior")
        }
        exchangeFailure = nil
        let restored = RemoteAuthClient(defaults: defaults, credentialService: suite, networkSession: network)
        try check(restored.session?.token == auth.session?.token && restored.session?.refreshToken == "google-refresh",
                  "La sesión de Google se guarda en Keychain y se recupera al abrir la app")
        for suffix in ["#", "#_=_", "#sb=", "#provider=google"] {
            exchanged = false
            let linked = try await auth.authenticateWithGoogle(expectedEmail: user.email, openBrowser: { url in
                URL(string: try successfulBrowser(url).absoluteString + suffix)!
            })
            try check(exchanged && linked.id == accountID, "Google acepta callback válido con sufijo " + suffix + " y conserva la cuenta")
        }
        let originalToken = auth.session?.token
        do {
            _ = try await auth.authenticateWithGoogle(openBrowser: { _ in throw CancellationError() })
            throw DesktopError.invalidBusiness
        } catch is CancellationError { }
        try check(auth.session?.token == originalToken, "Cancelar Google conserva la cuenta existente")
        responseEmail = "otra@example.com"
        do {
            _ = try await auth.authenticateWithGoogle(expectedEmail: user.email, openBrowser: { try successfulBrowser($0) })
            throw DesktopError.invalidBusiness
        } catch RemoteAuthError.rejected(let message) {
            try check(auth.session?.token == originalToken && message.contains(user.email), "Elegir otro correo desde Perfil conserva la sesión y los datos de la cuenta actual")
        }
        responseEmail = user.email; responseID = UUID().uuidString
        do {
            _ = try await auth.authenticateWithGoogle(expectedEmail: user.email, openBrowser: { try successfulBrowser($0) })
            throw DesktopError.invalidBusiness
        } catch RemoteAuthError.rejected {
            try check(auth.session?.user.id == accountID && auth.session?.token == originalToken, "Mismo correo con UUID distinto no reemplaza la cuenta ni sus datos")
        }
        responseID = accountID
        googleEnabled = false
        var browserOpened = false
        do {
            _ = try await auth.authenticateWithGoogle(openBrowser: { url in browserOpened = true; return url })
            throw DesktopError.invalidBusiness
        } catch RemoteAuthError.rejected { }
        try check(!browserOpened && auth.session?.token == originalToken, "Google desactivado no abre el navegador ni modifica la sesión")
        googleEnabled = true
        exchanged = false
        do {
            _ = try await auth.authenticateWithGoogle(openBrowser: { _ in
                auth.logout()
                return URL(string: "reviewnfcgo://auth/callback/stale?code=one-use-code")!
            })
            throw DesktopError.invalidBusiness
        } catch is CancellationError { }
        try check(!auth.signedIn && !exchanged, "Un callback recibido después de cerrar sesión no vuelve a autenticar al usuario")

        let flow = try GoogleOAuthRequest(origin: origin)
        let next = try GoogleOAuthRequest(origin: origin)
        try check(flow.verifier != next.verifier && flow.callback != next.callback, "Cada intento genera un verificador y un callback independientes")
        for (label, url) in [
            ("Callback de otro intento rechazado", next.callback.absoluteString + "?code=test"),
            ("Callback con destino ajeno rechazado", "reviewnfcgo://business/callback?code=test"),
            ("Tokens implícitos rechazados", flow.callback.absoluteString + "#access_token=unsafe"),
            ("Código repetido rechazado", flow.callback.absoluteString + "?code=a&code=b"),
            ("Código vacío rechazado", flow.callback.absoluteString + "?code="),
            ("Token junto al código rechazado", flow.callback.absoluteString + "?code=test#access_token=unsafe"),
            ("Segundo código en fragmento rechazado", flow.callback.absoluteString + "?code=test#code=other"),
            ("Token ID rechazado", flow.callback.absoluteString + "?code=test#id_token=unsafe")
        ] {
            do { _ = try flow.code(from: URL(string: url)!); throw DesktopError.invalidBusiness }
            catch RemoteAuthError.rejected { try check(true, label) }
        }
        do { _ = try flow.code(from: URL(string: flow.callback.absoluteString + "?error=access_denied")!); throw DesktopError.invalidBusiness }
        catch is CancellationError { try check(true, "Consentimiento denegado tratado como cancelación") }
        do {
            _ = try flow.code(from: URL(string: flow.callback.absoluteString + "?error=access_denied#error=access_denied&sb=")!)
            throw DesktopError.invalidBusiness
        } catch is CancellationError { try check(true, "La cancelación acepta el fragmento de error que añade Supabase") }
        return checks
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
@MainActor private final class CloudVerificationTransport: CloudBackupTransport {
    var row: CloudBackupRecord?
    var writes = 0
    var history: [CloudBackupRecord] = []
    var offline = false
    func loadCloudHistory(owner: String) async throws -> [CloudBackupRecord] {
        if offline { throw CloudBackupError.unavailable }; return history
    }
    func loadCloudBackup(owner: String) async throws -> CloudBackupRecord? {
        if offline { throw CloudBackupError.unavailable }; return row
    }
    func saveCloudBackup(_ value: BusinessBackup, expectedRevision: Int64?) async throws -> CloudBackupRecord {
        if offline { throw CloudBackupError.unavailable }
        guard row?.revision == expectedRevision else { throw CloudBackupError.conflict }
        let next = CloudBackupRecord(user_id: "test", revision: (expectedRevision ?? 0) + 1, payload: value)
        if let row { history.insert(row, at: 0); history = Array(history.prefix(3)) }
        row = next; writes += 1; return next
    }
}

private final class AuthVerificationProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (Int, Any))?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            guard let handler = Self.handler else { throw URLError(.cancelled) }
            let (status, json) = try handler(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: try JSONSerialization.data(withJSONObject: json))
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
    static func bodyData(_ request: URLRequest) -> Data {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return Data() }
        stream.open(); defer { stream.close() }
        var data = Data(); var bytes = [UInt8](repeating: 0, count: 1024)
        while stream.hasBytesAvailable {
            let count = stream.read(&bytes, maxLength: bytes.count)
            if count <= 0 { break }
            data.append(contentsOf: bytes.prefix(count))
        }
        return data
    }
}
#endif
