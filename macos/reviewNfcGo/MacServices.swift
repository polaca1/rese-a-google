import AppKit
import SwiftUI
import UniformTypeIdentifiers
import MapKit
import UserNotifications

enum MacSection: String, CaseIterable, Identifiable {
    case dashboard = "Resumen", businesses = "Negocios", visits = "Visitas", money = "Dinero", inventory = "Inventario", map = "Mapa"
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .dashboard: return "square.grid.2x2"
        case .businesses: return "building.2"
        case .visits: return "calendar"
        case .money: return "eurosign.circle"
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
                let (data, response) = try await URLSession.shared.data(for: request)
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
