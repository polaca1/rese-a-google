import AppKit
import SwiftUI
import UniformTypeIdentifiers
import MapKit
import UserNotifications

enum MacSection: String, CaseIterable, Identifiable {
    case dashboard = "Resumen", businesses = "Negocios", visits = "Visitas", money = "Dinero", analytics = "Análisis", inventory = "Inventario", map = "Mapa"
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .dashboard: return "square.grid.2x2"
        case .businesses: return "building.2"
        case .visits: return "calendar"
        case .money: return "eurosign.circle"
        case .analytics: return "chart.xyaxis.line"
        case .inventory: return "shippingbox"
        case .map: return "map"
        }
    }
}
enum MacSheet: Identifiable {
    case business(UUID?), expense, transaction(UUID), stock(UUID)
    var id: String {
        switch self {
        case .business(let id): return "business-" + (id?.uuidString ?? "new")
        case .expense: return "expense"
        case .transaction(let id): return "transaction-" + id.uuidString
        case .stock(let id): return "stock-" + id.uuidString
        }
    }
}
@MainActor final class MacNavigation: ObservableObject {
    static let shared = MacNavigation()
    @Published var section: MacSection? = .dashboard
    @Published var selectedBusiness: UUID?
    @Published var sheet: MacSheet?
    @Published var importCandidate: BusinessBackup?
    func openBusiness(_ id: UUID, store: MacStore) {
        guard store.records.contains(where: { $0.id == id }) else { store.errorMessage = DesktopError.missingBusiness.localizedDescription; return }
        selectedBusiness = id; section = .businesses
    }
}

@MainActor enum MacFiles {
    static func chooseImport(store: MacStore, navigation: MacNavigation) {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.json]; panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false; panel.message = "Elige la copia exportada desde Perfil → Copias de seguridad en tu iPhone."
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in
                let scoped = url.startAccessingSecurityScopedResource(); defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                store.run { navigation.importCandidate = try MacStore.readBackup(Data(contentsOf: url)) }
            }
        }
    }
    static func export(store: MacStore, csv: Bool = false) {
        let panel = NSSavePanel(); panel.allowedContentTypes = csv ? [.commaSeparatedText] : [.json]
        panel.nameFieldStringValue = csv ? "reviewNfcGo-operaciones.csv" : "reviewNfcGo-copia.json"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in
                store.run { try (csv ? DesktopAnalytics.csv(store.money) : store.exportData()).write(to: url, options: .atomic) }
            }
        }
    }
    static func copy(_ value: String) { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(value, forType: .string) }
    static func maps(_ place: PlaceResult) {
        let item = MKMapItem(placemark: MKPlacemark(coordinate: place.coordinate)); item.name = place.name
        item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeWalking])
    }
}

@MainActor final class MacPlaceSearch: ObservableObject {
    @Published private(set) var results: [PlaceResult] = []
    @Published private(set) var isLoading = false
    @Published var message: String?
    private var revision = UUID()
    func search(_ query: String) async {
        let token = UUID(); revision = token
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.count >= 3 else { results = []; isLoading = false; message = nil; return }
        isLoading = true; message = nil
        do {
            try await Task.sleep(for: .milliseconds(450))
            try Task.checkCancellation()
            let key = Bundle.main.object(forInfoDictionaryKey: "GooglePlacesAPIKey") as? String ?? ""
            let found: [PlaceResult]
            if key.isEmpty {
                let request = MKLocalSearch.Request(); request.naturalLanguageQuery = query
                let response = try await MKLocalSearch(request: request).start()
                found = response.mapItems.prefix(8).map { item in
                    PlaceResult(id: "local-" + UUID().uuidString, name: item.name ?? query,
                                address: item.placemark.title ?? "", latitude: item.placemark.coordinate.latitude, longitude: item.placemark.coordinate.longitude)
                }
            } else {
                var request = URLRequest(url: URL(string: "https://places.googleapis.com/v1/places:searchText")!, timeoutInterval: 20)
                request.httpMethod = "POST"; request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.setValue(key, forHTTPHeaderField: "X-Goog-Api-Key")
                request.setValue("places.id,places.displayName,places.formattedAddress,places.location", forHTTPHeaderField: "X-Goog-FieldMask")
                request.httpBody = try JSONSerialization.data(withJSONObject: ["textQuery": query, "languageCode": "es", "maxResultCount": 8])
                let (data, response) = try await PlacesTransport.execute(request)
                guard let response = response as? HTTPURLResponse, (200...299).contains(response.statusCode), data.count <= 2_000_000 else {
                    throw NSError(domain: "Places", code: 1, userInfo: [NSLocalizedDescriptionKey: "No se ha podido buscar el negocio. Puedes añadirlo manualmente o intentarlo otra vez."])
                }
                struct Response: Decodable {
                    struct Place: Decodable {
                        struct Name: Decodable { var text: String }
                        struct Location: Decodable { var latitude: Double; var longitude: Double }
                        var id: String; var displayName: Name; var formattedAddress: String?; var location: Location
                    }
                    var places: [Place]?
                }
                found = try JSONDecoder().decode(Response.self, from: data).places?.map {
                    PlaceResult(id: $0.id, name: $0.displayName.text, address: $0.formattedAddress ?? "", latitude: $0.location.latitude, longitude: $0.location.longitude)
                } ?? []
            }
            try Task.checkCancellation()
            guard revision == token else { return }
            results = found; isLoading = false
            if found.isEmpty { message = "Sin coincidencias. Añade la ciudad o la dirección a la búsqueda." }
        } catch {
            guard revision == token else { return }
            isLoading = false
            if !(error is CancellationError) { results = []; message = error.localizedDescription }
        }
    }
}

@MainActor final class MacNotifications: NSObject, ObservableObject, VisitNotificationBackend, UNUserNotificationCenterDelegate {
    static let shared = MacNotifications()
    @Published private(set) var enabled = UserDefaults.standard.bool(forKey: "reviewNfcGo.mac.notifications")
    @Published var message: String?
    var didOpen: ((UUID) -> Void)?
    private let center = UNUserNotificationCenter.current()
    private lazy var scheduler = VisitNotificationScheduler(backend: self, report: { [weak self] in self?.message = $0 })
    override init() { super.init(); center.delegate = self }
    func setEnabled(_ value: Bool, records: [VisitRecord]) async {
        do {
            if value {
                guard try await center.requestAuthorization(options: [.alert, .sound, .badge]) else {
                    message = "Activa los avisos de reviewNfcGo en Ajustes del Sistema → Notificaciones."; return
                }
            }
            enabled = value; UserDefaults.standard.set(value, forKey: "reviewNfcGo.mac.notifications")
            replace(records)
        } catch { message = error.localizedDescription }
    }
    func replace(_ records: [VisitRecord]) {
        scheduler.replace(enabled ? records.map { record in
            ScheduledVisit(id: record.id, name: record.place.name, address: record.place.address, placeID: record.place.id,
                           latitude: record.place.latitude, longitude: record.place.longitude, notes: record.notes,
                           visitDate: record.reminderDate, reminderDate: record.notificationDate,
                           completed: record.status == .completed || record.arrivedAt != nil)
        } : [])
    }
    func authorizationAllowed() async -> Bool { let settings = await center.notificationSettings(); return settings.authorizationStatus == .authorized }
    func pending() async -> [String: String] {
        Dictionary(uniqueKeysWithValues: await center.pendingNotificationRequests().filter { VisitNotification.owns($0.identifier) }
            .map { ($0.identifier, $0.content.userInfo["fingerprint"] as? String ?? "") })
    }
    func deliveredIDs() async -> [String] { await center.deliveredNotifications().map { $0.request.identifier }.filter(VisitNotification.owns) }
    func remove(ids: [String]) { center.removePendingNotificationRequests(withIdentifiers: ids); center.removeDeliveredNotifications(withIdentifiers: ids) }
    func add(_ notification: VisitNotification) async throws {
        let content = UNMutableNotificationContent(); content.title = notification.visit.name
        content.body = notification.kind == .activity ? "Tu visita es dentro de cinco horas." : "Tienes una visita pendiente. " + notification.visit.notes
        content.sound = .default; content.userInfo = ["businessID": notification.visit.id.uuidString, "fingerprint": notification.fingerprint]
        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: notification.fireDate)
        try await center.add(UNNotificationRequest(identifier: notification.id, content: content, trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)))
    }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                          withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound, .list])
    }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                          withCompletionHandler completionHandler: @escaping () -> Void) {
        let rawID = response.notification.request.content.userInfo["businessID"] as? String
        Task { @MainActor in
            if let rawID, let id = UUID(uuidString: rawID) { self.didOpen?(id); NSApp.activate(ignoringOtherApps: true) }
            completionHandler()
        }
    }
}

@MainActor enum MacFinanceExport {
    static func save(_ report: FinanceReport, owner: String, pdf: Bool, store: MacStore) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = pdf ? [.pdf] : [.commaSeparatedText]
        panel.nameFieldStringValue = pdf ? "reviewNfcGo-informe.pdf" : "reviewNfcGo-operaciones-periodo.csv"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in
                store.run { try (pdf ? self.pdf(report, owner: owner) : report.csv).write(to: url, options: .atomic) }
            }
        }
    }
    static func pdf(_ report: FinanceReport, owner: String) -> Data {
        let view = FinancePrintView(report: report, owner: owner)
        return view.dataWithPDF(inside: view.bounds)
    }
}

@MainActor private final class FinancePrintView: NSView {
    let report: FinanceReport
    let owner: String
    override var isFlipped: Bool { true }
    init(report: FinanceReport, owner: String) {
        self.report = report; self.owner = owner
        super.init(frame: NSRect(x: 0, y: 0, width: 595, height: 842))
        appearance = NSAppearance(named: .aqua)
    }
    required init?(coder: NSCoder) { nil }
    private func text(_ text: String, x: CGFloat = 40, y: CGFloat, width: CGFloat = 515, size: CGFloat = 11, bold: Bool = false, color: NSColor = .black) {
        let font = bold ? NSFont.boldSystemFont(ofSize: size) : NSFont.systemFont(ofSize: size)
        (text as NSString).draw(in: NSRect(x: x, y: y, width: width, height: 34), withAttributes: [.font: font, .foregroundColor: color])
    }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.white.setFill(); bounds.fill()
        text("reviewNfcGo · Informe de caja", y: 35, size: 21, bold: true)
        text(report.label, y: 68, size: 12)
        text(owner, y: 89, size: 10, color: .darkGray)
        let metrics = [("Ingresos netos", report.totals.income), ("Gastos netos", report.totals.expenses), ("Resultado de caja", report.totals.result)]
        for (index, metric) in metrics.enumerated() {
            let x = CGFloat(40 + index * 175)
            text(metric.0, x: x, y: 126, width: 170, size: 10, color: .darkGray)
            text(euro(metric.1), x: x, y: 146, width: 170, size: 19, bold: true)
        }
        text("Saldo inicial " + euro(report.openingBalance) + " · Saldo final " + euro(report.closingBalance), y: 185)
        let points = Array(report.points.suffix(12))
        text("Ingresos y gastos · últimos \(points.count) intervalos del periodo", y: 220, size: 12, bold: true)
        if !points.isEmpty {
            let values = points.flatMap { [Double($0.income) / 100, Double($0.expenses) / 100] }
            let low = min(0, values.min() ?? 0)
            let high = max(0, values.max() ?? 0)
            let span = max(1, high - low)
            let height: CGFloat = 145
            let top: CGFloat = 252
            let baseline = top + CGFloat(high / span) * height
            NSColor.lightGray.setStroke()
            let axis = NSBezierPath(); axis.move(to: NSPoint(x: 40, y: baseline)); axis.line(to: NSPoint(x: 555, y: baseline)); axis.stroke()
            let step = CGFloat(515) / CGFloat(points.count)
            for (index, point) in points.enumerated() {
                let x = CGFloat(40) + CGFloat(index) * step
                for (position, amount) in [point.income, point.expenses].enumerated() {
                    let value = Double(amount) / 100
                    let y = top + CGFloat((high - value) / span) * height
                    (position == 0 ? NSColor.systemBlue : NSColor.systemOrange).setFill()
                    NSRect(x: x + CGFloat(position) * step * 0.4, y: min(y, baseline), width: max(1, step * 0.34), height: abs(y - baseline)).fill()
                }
                text(point.date.formatted(.dateTime.day().month(.twoDigits)), x: x, y: top + height + 8, width: step, size: 7)
            }
        }
        text("Azul: ingresos · Naranja: gastos · Euros", y: 430, size: 9, color: .darkGray)
        text("Distribución de gastos netos", y: 464, size: 12, bold: true)
        for (index, category) in report.categories.prefix(5).enumerated() {
            text(category.title, y: CGFloat(490 + index * 21), width: 370)
            text(euro(category.cents), x: 430, y: CGFloat(490 + index * 21), width: 125)
        }
        if report.categories.isEmpty { text("Sin gastos en este periodo.", y: 490, color: .darkGray) }
        text("Negocios que más aportan", y: 614, size: 12, bold: true)
        for (index, business) in report.businesses.prefix(5).enumerated() {
            text(business.title, y: CGFloat(640 + index * 23), width: 375)
            text(euro(business.cents), x: 430, y: CGFloat(640 + index * 23), width: 125)
        }
        if report.businesses.isEmpty { text("Sin ingresos de negocios en este periodo.", y: 640, color: .darkGray) }
        text("Incluye ajustes y devoluciones. El resultado de caja no equivale al beneficio contable.\nDetalle completo de operaciones disponible en la exportación CSV del periodo.", y: 784, size: 8, color: .darkGray)
    }
}
