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
            checks += try await verifyCentralAccounts()
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
private final class AuthVerificationProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (Int, [String: Any]))?
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
