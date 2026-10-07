import SwiftUI
import UniformTypeIdentifiers
import MapKit
import UserNotifications

struct BackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data
    init(data: Data = Data()) { self.data = data }
    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else { throw BackupError.invalid }
        self.data = data
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}
struct BackupView: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var photos: ProfilePhotoStore
    @State private var document = BackupDocument()
    @State private var exporting = false
    @State private var importing = false
    @State private var preview: BusinessBackup?
    @State private var error: String?
    @State private var message: String?
    var body: some View {
        List {
            Section {
                Button { export() } label: { Label("Guardar copia en Archivos", systemImage: "square.and.arrow.up") }
                Button { importing = true } label: { Label("Restaurar una copia", systemImage: "arrow.clockwise") }
            } footer: {
                Text("Incluye negocios, visitas, ventas, inventario, movimientos y foto de perfil. El archivo contiene datos personales: guárdalo en un lugar privado. No contiene contraseñas ni claves de API.")
            }
            Section {
                Button("Recuperar el estado anterior a la última restauración") {
                    do {
                        guard let value = try store.recoveryBackup() else { message = "Todavía no has restaurado ninguna copia."; return }
                        preview = value
                    } catch { self.error = error.localizedDescription }
                }
            } footer: { Text("Antes de restaurar, se conserva una copia de recuperación en este iPhone.") }
            if let message { Section { Text(message).foregroundStyle(.secondary) } }
        }.navigationTitle("Copias de seguridad").navigationBarTitleDisplayMode(.inline)
            .fileExporter(isPresented: $exporting, document: document, contentType: .json, defaultFilename: "reviewNfcGo-" + Date().formatted(.iso8601.year().month().day().dateSeparator(.dash))) { result in
                if case .failure(let value) = result { error = value.localizedDescription }
                else { message = "Copia guardada." }
            }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
                do {
                    let url = try result.get()
                    let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
                    let bytes = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                    guard bytes <= 25_000_000 else { throw BackupError.tooLarge }
                    let value = try BusinessBackup.decode(Data(contentsOf: url), for: store.loadedUserEmail)
                    try ProfilePhotoStore.validateBackupPhoto(value.photo)
                    preview = value
                } catch { self.error = error.localizedDescription }
            }
            .sheet(isPresented: Binding(get: { preview != nil }, set: { if !$0 { preview = nil } })) {
                if let value = preview {
                    NavigationStack {
                        List {
                            Section("Contenido de la copia") {
                                LabeledContent("Fecha", value: value.createdAt.formatted(date: .abbreviated, time: .shortened))
                                LabeledContent("Negocios", value: "\(value.records.count)")
                                LabeledContent("Productos", value: "\(value.money.products.count)")
                                LabeledContent("Movimientos", value: "\(value.money.transactions.count)")
                                LabeledContent("Saldo", value: (Double(value.money.balanceCents) / 100).formatted(.currency(code: "EUR")))
                            }
                            Section {
                                Button("Restaurar esta copia", role: .destructive) {
                                    do {
                                        try ProfilePhotoStore.validateBackupPhoto(value.photo)
                                        try store.restore(value, previousPhoto: photos.backupData)
                                        try photos.restoreBackupData(value.photo)
                                        preview = nil; message = "Copia restaurada. Tus visitas y widgets se han actualizado."
                                    } catch { preview = nil; self.error = error.localizedDescription }
                                }
                            } footer: { Text("Sustituye los datos de esta cuenta por los de la copia. Se guardará el estado actual para poder recuperarlo.") }
                        }.navigationTitle("Revisar copia").navigationBarTitleDisplayMode(.inline)
                            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { preview = nil } } }
                    }
                }
            }
            .alert("No se pudo completar", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) { Button("Aceptar") { error = nil } } message: { Text(error ?? "") }
    }
    private func export() {
        do { document = BackupDocument(data: try store.backup(photo: photos.backupData).encoded()); exporting = true }
        catch { self.error = error.localizedDescription }
    }
}

struct DailyRouteView: View {
    @EnvironmentObject private var store: AppStore
    @StateObject private var location = RouteLocation()
    @State private var day = Date()
    private var stops: [RouteStop] { DailyRoute.stops(records: store.records, day: day, origin: location.origin) }
    var body: some View {
        List {
            Section {
                DatePicker("Día", selection: $day, displayedComponents: .date)
                Button { location.request() } label: { Label("Ordenar desde mi ubicación", systemImage: "location") }
                if let message = location.message { Text(message).font(.footnote).foregroundStyle(.secondary) }
            } footer: { Text("Las citas mantienen su horario. Después se ordenan los negocios sin cita por cercanía. Las distancias son en línea recta; Mapas calcula el trayecto real.") }
            if stops.isEmpty { Section { Text("No tienes visitas para este día ni negocios pendientes sin cita.").foregroundStyle(.secondary) } }
            ForEach(Array(stops.enumerated()), id: \.element.id) { index, stop in
                Section {
                    NavigationLink { RecordDetailView(recordID: stop.id) } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("\(index + 1). \(stop.record.place.name)").font(.headline)
                            if let date = stop.record.reminderDate { Label(date.formatted(date: .omitted, time: .shortened), systemImage: "clock") }
                            else { Text("Sin hora fijada").foregroundStyle(.secondary) }
                            Text(stop.record.place.address).font(.caption).foregroundStyle(.secondary)
                            if let distance = stop.distanceMeters { Text(Measurement(value: distance, unit: UnitLength.meters).formatted(.measurement(width: .abbreviated, usage: .road))).font(.caption).foregroundStyle(.secondary) }
                        }
                    }
                    Button("Cómo llegar") { MapLauncher.openAppleMaps(latitude: stop.record.place.latitude, longitude: stop.record.place.longitude, name: stop.record.place.name) }
                }
            }
        }.navigationTitle("Ruta del día").navigationBarTitleDisplayMode(.inline)
    }
}
@MainActor final class RouteLocation: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var origin: PlaceResult?
    @Published var message: String?
    private let manager = CLLocationManager()
    override init() { super.init(); manager.delegate = self; manager.desiredAccuracy = kCLLocationAccuracyHundredMeters }
    func request() {
        if manager.authorizationStatus == .notDetermined { manager.requestWhenInUseAuthorization() }
        else if [.authorizedAlways, .authorizedWhenInUse].contains(manager.authorizationStatus) { message = "Buscando ubicación…"; manager.requestLocation() }
        else { message = "Permite la ubicación en Ajustes para ordenar desde donde estás." }
    }
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        if [.authorizedAlways, .authorizedWhenInUse].contains(manager.authorizationStatus) { manager.requestLocation() }
    }
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let value = locations.last else { return }
        origin = PlaceResult(id: "route-origin", name: "Mi ubicación", address: "", latitude: value.coordinate.latitude, longitude: value.coordinate.longitude)
        message = "Ordenada desde tu ubicación."
    }
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) { message = "No se pudo obtener la ubicación. Puedes volver a intentarlo." }
}
enum StockNotifications {
    @MainActor private static var task: Task<Void, Never>?
    @MainActor static func refresh(money: MoneyLedger, owner: String?) {
        task?.cancel()
        guard let owner else {
            task = Task {
                let center = UNUserNotificationCenter.current()
                let pending = await center.pendingNotificationRequests()
                guard !Task.isCancelled else { return }
                center.removePendingNotificationRequests(withIdentifiers: pending.filter { $0.identifier.hasPrefix("stock.") }.map(\.identifier))
                let delivered = await center.deliveredNotifications()
                guard !Task.isCancelled else { return }
                center.removeDeliveredNotifications(withIdentifiers: delivered.filter { $0.request.identifier.hasPrefix("stock.") }.map { $0.request.identifier })
            }
            return
        }
        let low = Set(money.lowStockProducts.map { $0.id.uuidString })
        let key = "resenago.lowStock." + owner
        let previous = Set(UserDefaults.standard.stringArray(forKey: key) ?? [])
        let ownerToken = WatchIdentity.token(owner)
        let center = UNUserNotificationCenter.current()
        for id in previous.subtracting(low) { center.removePendingNotificationRequests(withIdentifiers: ["stock." + ownerToken + "." + id]) }
        let newlyLow = money.lowStockProducts.filter { !previous.contains($0.id.uuidString) }
        task = Task {
            let pending = await center.pendingNotificationRequests()
            guard !Task.isCancelled else { return }
            center.removePendingNotificationRequests(withIdentifiers: pending.filter { $0.identifier.hasPrefix("stock.") && !$0.identifier.hasPrefix("stock." + ownerToken + ".") }.map(\.identifier))
            let settings = await center.notificationSettings()
            guard !Task.isCancelled, [.authorized, .provisional, .ephemeral].contains(settings.authorizationStatus) else { return }
            for product in newlyLow {
                guard !Task.isCancelled else { return }
                let content = UNMutableNotificationContent()
                content.title = "Quedan pocas tarjetas"
                content.body = "\(product.displayName): \(money.stock(product.id)) disponibles. Revisa tu inventario para reponerlas."
                content.sound = .default
                let identifier = "stock." + ownerToken + "." + product.id.uuidString
                let fingerprint = identifier + "." + UUID().uuidString
                let entry = AlertHistoryStore.shared.register(scope: owner, systemID: identifier, fingerprint: fingerprint, kind: .stock,
                    recordID: nil, businessName: nil, title: content.title, body: content.body, scheduledDate: Date().addingTimeInterval(1), startsNewPlan: true)
                content.userInfo = [AlertHistoryStore.accountKey: owner, AlertHistoryStore.entryKey: entry.uuidString, NotificationManager.fingerprintKey: fingerprint]
                do {
                    try await center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)))
                    if Task.isCancelled { center.removePendingNotificationRequests(withIdentifiers: [identifier]); AlertHistoryStore.shared.transition(scope: owner, id: entry, to: .cancelled); return }
                } catch { AlertHistoryStore.shared.transition(scope: owner, id: entry, to: .failed) }
            }
            guard !Task.isCancelled else { return }
            UserDefaults.standard.set(Array(low), forKey: key)
        }
    }
}

struct ProfitView: View {
    @EnvironmentObject private var store: AppStore
    var body: some View {
        List {
            Section {
                Text("El beneficio de cada venta resta el coste de compra de las tarjetas asignadas. Se conserva el coste al guardar la venta; usa el coste medio de las compras registradas. Para ventas anteriores, el coste se reconstruye con esas compras.").font(.footnote).foregroundStyle(.secondary)
                Text("Los gastos de stands, accesorios y otros conceptos se descuentan del saldo general.").font(.footnote).foregroundStyle(.secondary)
            }
            ForEach(store.records.filter { $0.cardsSold > 0 }) { record in
                NavigationLink { RecordDetailView(recordID: record.id) } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(record.place.name).font(.headline)
                        LabeledContent("Ingreso", value: record.earnings.formatted(.currency(code: "EUR")))
                        if let profit = store.money.profitCents(record.id) {
                            LabeledContent("Coste de tarjetas", value: (Double((store.money.sales[record.id.uuidString]?.costCents) ?? 0) / 100).formatted(.currency(code: "EUR")))
                            LabeledContent("Beneficio", value: (Double(profit) / 100).formatted(.currency(code: "EUR")))
                        } else { Text("Asigna un color con compras registradas para calcular el coste.").font(.caption).foregroundStyle(.secondary) }
                    }.padding(.vertical, 4)
                }
            }
        }.navigationTitle("Beneficio por negocio").navigationBarTitleDisplayMode(.inline)
    }
}
