import SwiftUI
import MapKit
import CoreLocation
import UserNotifications
import CryptoKit
import UIKit
import ActivityKit

// MARK: - Theme

enum AppTheme {
    static let blue = Color(red: 0.05, green: 0.42, blue: 0.95)
    static let softBlue = blue.opacity(0.12)
    static let background = Color(uiColor: .systemGroupedBackground)
    static let card = Color(uiColor: .secondarySystemGroupedBackground)
}

// MARK: - Models

struct UserProfile: Codable, Equatable {
    let name: String
    let email: String
}

// MARK: - Authentication (local account on this iPhone)

final class AuthStore: ObservableObject {
    @Published private(set) var currentUser: UserProfile?
    @Published var errorMessage: String?

    private let userKey = "resenago.currentUser"
    private let accountsKey = "resenago.accounts"

    struct Account: Codable {
        let profile: UserProfile
        let passwordHash: String
    }

    init() {
        if let data = UserDefaults.standard.data(forKey: userKey),
           let profile = try? JSONDecoder().decode(UserProfile.self, from: data) {
            currentUser = profile
        }
    }

    func createAccount(name: String, email: String, password: String) -> Bool {
        let cleanEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              cleanEmail.contains("@"), password.count >= 4 else {
            errorMessage = "Completa los datos. La contraseña debe tener al menos 4 caracteres."
            return false
        }
        var accounts = loadAccounts()
        guard accounts[cleanEmail] == nil else {
            errorMessage = "Ya existe una cuenta con ese correo."
            return false
        }
        let profile = UserProfile(name: name.trimmingCharacters(in: .whitespacesAndNewlines), email: cleanEmail)
        accounts[cleanEmail] = Account(profile: profile, passwordHash: Self.hash(password))
        saveAccounts(accounts)
        setCurrent(profile)
        errorMessage = nil
        return true
    }

    func login(email: String, password: String) -> Bool {
        let cleanEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let accounts = loadAccounts()
        guard let account = accounts[cleanEmail], account.passwordHash == Self.hash(password) else {
            errorMessage = "Correo o contraseña incorrectos."
            return false
        }
        setCurrent(account.profile)
        errorMessage = nil
        return true
    }

    func logout() {
        currentUser = nil
        UserDefaults.standard.removeObject(forKey: userKey)
    }

    private func setCurrent(_ profile: UserProfile) {
        currentUser = profile
        if let data = try? JSONEncoder().encode(profile) {
            UserDefaults.standard.set(data, forKey: userKey)
        }
    }

    private func loadAccounts() -> [String: Account] {
        guard let data = UserDefaults.standard.data(forKey: accountsKey),
              let value = try? JSONDecoder().decode([String: Account].self, from: data) else { return [:] }
        return value
    }

    private func saveAccounts(_ accounts: [String: Account]) {
        if let data = try? JSONEncoder().encode(accounts) {
            UserDefaults.standard.set(data, forKey: accountsKey)
        }
    }

    private static func hash(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - App data

@MainActor
final class AppStore: ObservableObject {
    @Published var records: [VisitRecord] = []
    @Published private(set) var money = MoneyLedger()
    @Published private(set) var hasLoadedRecords = false
    @Published private(set) var loadedUserEmail: String?
    private var userKey: String?

    var totalEarnings: Double { Double(money.incomeCents) / 100 }
    var totalCardsSold: Int { records.reduce(0) { $0 + $1.cardsSold } }
    var pendingReminders: [VisitRecord] {
        records.filter { $0.reminderDate != nil && $0.status != .completed }
            .sorted { ($0.reminderDate ?? .distantFuture) < ($1.reminderDate ?? .distantFuture) }
    }

    func switchUser(_ email: String?) {
        hasLoadedRecords = false
        userKey = email
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
        if let index = records.firstIndex(where: { $0.place.id == place.id }) {
            records[index].place = place
            records[index].createdAt = Date()
        } else {
            records.insert(VisitRecord(place: place), at: 0)
        }
        save()
    }

    func saveReminder(for place: PlaceResult, visitDate: Date, notificationDate: Date, notes: String) -> VisitRecord {
        var record: VisitRecord
        if let index = records.firstIndex(where: { $0.place.id == place.id }) {
            records[index].place = place
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
        guard money.canAssign(value), MoneyLedger.cents(value.earnings) != nil else { return false }
        records[index] = value
        save()
        return true
    }

    func delete(at offsets: IndexSet) {
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
        money.synchronize(records)
        persistMoney()
        if let data = try? JSONEncoder().encode(records) {
            UserDefaults.standard.set(data, forKey: storageKey())
        }
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
        money = updated; persistMoney(); publishWidgets()
    }
    func reverseExpense(_ id: UUID) throws {
        var updated = money; try updated.reverseExpense(id)
        money = updated; persistMoney(); publishWidgets()
    }
    func adjustStock(_ id: UUID, quantity: Int, reason: String) throws {
        var updated = money; try updated.adjustStock(id, quantity: quantity, reason: reason)
        money = updated; persistMoney(); publishWidgets()
    }
    private func publishWidgets() {
        var snapshot = WidgetSnapshot(records: records, isSignedIn: userKey != nil)
        if userKey != nil {
            snapshot.moneyBalance = Double(money.balanceCents) / 100
            snapshot.moneyExpenses = Double(money.expenseCents) / 100
            snapshot.totalEarnings = totalEarnings
            snapshot.moneyOperations = money.history.filter { $0.cents != 0 }.prefix(10).map {
                WidgetMoneyOperation(id: $0.id, name: $0.title, amount: $0.amount, date: $0.date,
                    businessID: $0.businessID.flatMap { id in records.contains(where: { $0.id == id }) ? id : nil })
            }
        }
        WidgetSharedStore.publish(snapshot)
    }
}

// MARK: - Location and Google Places

struct MapFocusRequest {
    enum Target { case user, place }
    let id = UUID()
    let coordinate: CLLocationCoordinate2D
    let target: Target
}

@MainActor
final class PlaceFinder: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var userLocation: CLLocationCoordinate2D?
    @Published var selectedPlace: PlaceResult?
    @Published private(set) var mapFocus: MapFocusRequest?
    @Published private(set) var searchResults: [PlaceResult] = []
    @Published var isLoading = false
    @Published var status = "Buscando tu ubicación…"
    @Published var errorMessage: String?

    private let manager = CLLocationManager()
    private var didInitialSearch = false
    private var searchRevision: UUID?
    private var apiKey: String {
        Bundle.main.object(forInfoDictionaryKey: "GooglePlacesAPIKey") as? String ?? ""
    }

    override init() {
        super.init()
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--verification-map") { didInitialSearch = true }
        #endif
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
    }

    func start() {
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            manager.startUpdatingLocation()
        case .denied, .restricted:
            status = "Activa la ubicación en Ajustes para detectar negocios cercanos."
        @unknown default:
            break
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        if manager.authorizationStatus == .authorizedWhenInUse || manager.authorizationStatus == .authorizedAlways {
            manager.startUpdatingLocation()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last, location.horizontalAccuracy >= 0,
              CLLocationCoordinate2DIsValid(location.coordinate) else { return }
        let isFirstLocation = userLocation == nil
        userLocation = location.coordinate
        if isFirstLocation && mapFocus == nil { focusOnUserLocation(cancelSearch: false) }
        status = "Ubicación encontrada · ±\(Int(location.horizontalAccuracy)) m"
        if !didInitialSearch {
            didInitialSearch = true
            if searchRevision == nil {
                Task {
                    guard self.searchRevision == nil else { return }
                    await searchNearest(to: location.coordinate, focusResult: false)
                }
            }
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        errorMessage = error.localizedDescription
    }

    func focusOnUserLocation(cancelSearch: Bool = true) {
        if cancelSearch { searchRevision = UUID(); isLoading = false }
        guard let coordinate = userLocation else { start(); return }
        mapFocus = MapFocusRequest(coordinate: coordinate, target: .user)
    }

    func selectPlace(_ place: PlaceResult?, focus: Bool) {
        selectedPlace = place
        if focus, let place {
            mapFocus = MapFocusRequest(coordinate: place.coordinate, target: .place)
        }
    }

    #if DEBUG
    func prepareMapVerification() { didInitialSearch = true }
    #endif

    func searchNearest(to coordinate: CLLocationCoordinate2D, focusResult: Bool = true) async {
        let revision = UUID()
        searchRevision = revision
        isLoading = true
        errorMessage = nil
        defer { if searchRevision == revision { isLoading = false } }

        do {
            let results = try await GooglePlacesService(apiKey: apiKey).nearby(coordinate: coordinate)
            guard searchRevision == revision else { return }
            guard !results.isEmpty else {
                status = "No se han encontrado negocios cerca de ese punto."
                return
            }
            let target = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
            let nearest = results.min { a, b in
                target.distance(from: CLLocation(latitude: a.latitude, longitude: a.longitude)) <
                target.distance(from: CLLocation(latitude: b.latitude, longitude: b.longitude))
            }
            selectPlace(nearest, focus: focusResult)
            status = "Negocio más cercano seleccionado"
        } catch {
            guard searchRevision == revision else { return }
            errorMessage = "No se pudo consultar Google Places: \(error.localizedDescription)"
        }
    }

    func beginNameSearch(_ query: String, saved: [PlaceResult]) {
        searchRevision = UUID(); isLoading = false; errorMessage = nil
        if !query.isEmpty { didInitialSearch = true }
        searchResults = SearchSuggestions.savedMatches(query, places: saved)
    }
    func chooseSearchResult(_ place: PlaceResult) {
        searchRevision = UUID(); isLoading = false; searchResults = []
        selectPlace(place, focus: true); status = "Negocio seleccionado"
    }
    func searchByName(_ query: String, saved: [PlaceResult] = []) async {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.count >= 2 else { return }
        let revision = UUID(); searchRevision = revision; didInitialSearch = true
        isLoading = true; errorMessage = nil
        defer { if searchRevision == revision { isLoading = false } }
        do {
            let results = try await GooglePlacesService(apiKey: apiKey).textSearch(query: query, bias: userLocation)
            guard !Task.isCancelled, searchRevision == revision else { return }
            searchResults = SearchSuggestions.merge(local: SearchSuggestions.savedMatches(query, places: saved), remote: results)
            status = searchResults.isEmpty ? "No se han encontrado coincidencias." : "Elige un resultado para enfocarlo"
        } catch {
            guard !Task.isCancelled, searchRevision == revision else { return }
            errorMessage = "No se pudo buscar en Google. Puedes elegir una coincidencia guardada o volver a intentarlo."
        }
    }

}

struct GooglePlacesService {
    let apiKey: String

    struct NearbyResponse: Decodable { let places: [APIPlace]? }
    struct APIPlace: Decodable {
        struct DisplayName: Decodable { let text: String }
        struct Location: Decodable { let latitude: Double; let longitude: Double }
        let id: String
        let displayName: DisplayName?
        let formattedAddress: String?
        let location: Location?
    }

    func nearby(coordinate: CLLocationCoordinate2D) async throws -> [PlaceResult] {
        let url = URL(string: "https://places.googleapis.com/v1/places:searchNearby")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "X-Goog-Api-Key")
        request.setValue("places.id,places.displayName,places.formattedAddress,places.location", forHTTPHeaderField: "X-Goog-FieldMask")
        let body: [String: Any] = [
            "maxResultCount": 12,
            "rankPreference": "DISTANCE",
            "locationRestriction": [
                "circle": [
                    "center": ["latitude": coordinate.latitude, "longitude": coordinate.longitude],
                    "radius": 800.0
                ]
            ]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return try await execute(request)
    }

    func textSearch(query: String, bias: CLLocationCoordinate2D?) async throws -> [PlaceResult] {
        let url = URL(string: "https://places.googleapis.com/v1/places:searchText")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "X-Goog-Api-Key")
        request.setValue("places.id,places.displayName,places.formattedAddress,places.location", forHTTPHeaderField: "X-Goog-FieldMask")
        var body: [String: Any] = ["textQuery": query, "maxResultCount": 10]
        if let bias {
            body["locationBias"] = [
                "circle": [
                    "center": ["latitude": bias.latitude, "longitude": bias.longitude],
                    "radius": 5000.0
                ]
            ]
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return try await execute(request)
    }

    private func execute(_ request: URLRequest) async throws -> [PlaceResult] {
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            let text = String(data: data, encoding: .utf8) ?? "Error HTTP \(http.statusCode)"
            throw NSError(domain: "GooglePlaces", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: text])
        }
        let decoded = try JSONDecoder().decode(NearbyResponse.self, from: data)
        return (decoded.places ?? []).compactMap { place in
            guard let loc = place.location else { return nil }
            return PlaceResult(
                id: place.id,
                name: place.displayName?.text ?? "Negocio",
                address: place.formattedAddress ?? "",
                latitude: loc.latitude,
                longitude: loc.longitude
            )
        }
    }
}


// MARK: - NFC handoff (sin entitlement Core NFC)

enum ExternalNFCWriter {
    private static let appStoreURL = URL(string: "https://apps.apple.com/es/app/nfc-helper/id6472720100")!

    /// NFC Helper documenta nfchelper://write?url=... para abrir directamente
    /// la pantalla de escritura con el registro URL ya cargado.
    static func write(reviewURL: String) {
        // Respaldo silencioso: si hiciera falta, el mismo enlace queda en el portapapeles.
        UIPasteboard.general.string = reviewURL

        var components = URLComponents()
        components.scheme = "nfchelper"
        components.host = "write"
        components.queryItems = [
            URLQueryItem(name: "url", value: reviewURL)
        ]

        guard let writerURL = components.url else { return }
        UIApplication.shared.open(writerURL, options: [:]) { success in
            if !success {
                UIApplication.shared.open(appStoreURL)
            }
        }
    }
}


// MARK: - Directions

enum MapLauncher {
    static func openAppleMaps(place: PlaceResult) {
        var components = URLComponents(string: "https://maps.apple.com/")!
        components.queryItems = [
            URLQueryItem(name: "daddr", value: "\(place.latitude),\(place.longitude)"),
            URLQueryItem(name: "q", value: place.name),
            URLQueryItem(name: "dirflg", value: "d")
        ]
        if let url = components.url { UIApplication.shared.open(url) }
    }

    static func openGoogleMaps(place: PlaceResult) {
        var components = URLComponents(string: "https://www.google.com/maps/dir/")!
        components.queryItems = [
            URLQueryItem(name: "api", value: "1"),
            URLQueryItem(name: "destination", value: "\(place.latitude),\(place.longitude)"),
            URLQueryItem(name: "destination_place_id", value: place.id),
            URLQueryItem(name: "travelmode", value: "driving")
        ]
        if let url = components.url { UIApplication.shared.open(url) }
    }

    static func openAppleMaps(latitude: Double, longitude: Double, name: String?) {
        let place = PlaceResult(id: "", name: name ?? "Destino", address: "", latitude: latitude, longitude: longitude)
        openAppleMaps(place: place)
    }

    static func openGoogleMaps(latitude: Double, longitude: Double, name: String?, placeID: String?) {
        var components = URLComponents(string: "https://www.google.com/maps/dir/")!
        var items = [
            URLQueryItem(name: "api", value: "1"),
            URLQueryItem(name: "destination", value: "\(latitude),\(longitude)"),
            URLQueryItem(name: "travelmode", value: "driving")
        ]
        if let placeID, !placeID.isEmpty { items.append(URLQueryItem(name: "destination_place_id", value: placeID)) }
        components.queryItems = items
        if let url = components.url { UIApplication.shared.open(url) }
    }
}

// MARK: - Root / Auth

struct RootView: View {
    @EnvironmentObject var auth: AuthStore

    var body: some View {
        Group {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--verification-widgets") {
                WidgetVerificationView()
            } else if ProcessInfo.processInfo.arguments.contains("--verification-dates") {
                QuickReminderView(place: PlaceResult(id: "date-verification", name: "Negocio de prueba", address: "Calle Mayor, Madrid", latitude: 40.4168, longitude: -3.7038))
            } else {
                authenticatedContent
            }
            #else
            authenticatedContent
            #endif
        }
    }
    @ViewBuilder private var authenticatedContent: some View {
            if auth.currentUser == nil {
                AuthView()
            } else {
                MainTabView()
            }
    }
}

struct AuthView: View {
    @EnvironmentObject var auth: AuthStore
    @State private var createMode = false
    @State private var name = ""
    @State private var email = ""
    @State private var password = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Spacer(minLength: 36)
                    HStack(spacing: 14) {
                        LogoMark(size: 58)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("reviewNfcGo").font(.system(size: 34, weight: .bold, design: .rounded))
                            Text("Encuentra. Copia. Gestiona.").foregroundStyle(.secondary)
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text(createMode ? "Crear cuenta" : "Iniciar sesión")
                            .font(.title2.bold())
                        Text("Tus negocios, ganancias y recordatorios quedan organizados en tu cuenta de este iPhone.")
                            .foregroundStyle(.secondary)
                    }

                    VStack(spacing: 12) {
                        if createMode {
                            NativeField(title: "Nombre", icon: "person", text: $name)
                        }
                        NativeField(title: "Correo electrónico", icon: "envelope", text: $email)
                        NativeSecureField(title: "Contraseña", text: $password)
                    }

                    if let error = auth.errorMessage {
                        Text(error).font(.footnote).foregroundStyle(.red)
                    }

                    Button {
                        if createMode {
                            _ = auth.createAccount(name: name, email: email, password: password)
                        } else {
                            _ = auth.login(email: email, password: password)
                        }
                    } label: {
                        Text(createMode ? "Crear cuenta" : "Entrar")
                            .frame(maxWidth: .infinity)
                    }
                    .appPrimaryButton()

                    Button(createMode ? "Ya tengo cuenta" : "Crear una cuenta") {
                        createMode.toggle()
                        auth.errorMessage = nil
                    }
                    .frame(maxWidth: .infinity)
                    .appSecondaryButton()

                    Spacer(minLength: 20)
                }
                .padding(24)
            }
            .background(Color(uiColor: .systemBackground))
            .navigationBarHidden(true)
        }
    }
}

struct NativeField: View {
    let title: String
    let icon: String
    @Binding var text: String
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon).foregroundStyle(.secondary).frame(width: 22)
            TextField(title, text: $text)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        }
        .padding(14)
        .appGlassField()
    }
}

struct NativeSecureField: View {
    let title: String
    @Binding var text: String
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "lock").foregroundStyle(.secondary).frame(width: 22)
            SecureField(title, text: $text)
        }
        .padding(14)
        .appGlassField()
    }
}

// MARK: - Main tabs

struct MainTabView: View {
    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var portalRouter: PortalRouter
    @State private var selectedTab = 0
    @State private var businessPath: [UUID] = []
    @State private var showUnavailableBusiness = false

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack { HomeView() }
                .tabItem { Label("Inicio", systemImage: "location.fill") }.tag(0)
            NavigationStack(path: $businessPath) {
                HistoryView()
                    .navigationDestination(for: UUID.self) { id in
                        RecordDetailView(recordID: id)
                    }
            }
                .tabItem { Label("Sitios", systemImage: "clock.fill") }.tag(1)
            NavigationStack { MoneyView() }
                .tabItem { Label("Dinero", systemImage: "eurosign.circle.fill") }.tag(2)
            NavigationStack { RemindersView() }
                .tabItem { Label("Avisos", systemImage: "bell.fill") }.tag(3)
            NavigationStack { ProfileView() }
                .tabItem { Label("Perfil", systemImage: "person.crop.circle.fill") }.tag(4)
        }
        .onAppear {
            openPendingBusiness()
            openPendingWidgetSection()
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--verification-profile") { selectedTab = 4 }
            if ProcessInfo.processInfo.arguments.contains("--verification-history") { selectedTab = 3 }
            #endif
        }
        .onChange(of: portalRouter.pendingRecordID) { _ in openPendingBusiness() }
        .onChange(of: portalRouter.pendingWidgetSection) { _ in openPendingWidgetSection() }
        .onChange(of: store.hasLoadedRecords) { _ in openPendingBusiness(); openPendingWidgetSection() }
        .onChange(of: store.loadedUserEmail) { _ in openPendingBusiness(); openPendingWidgetSection() }
        .alert("Negocio no disponible", isPresented: $showUnavailableBusiness) {
            Button("Aceptar", role: .cancel) {}
        } message: {
            Text("Este negocio se ha eliminado o pertenece a otra cuenta. Inicia sesión con la cuenta que lo guardó.")
        }
    }

    private func openPendingWidgetSection() {
        guard store.hasLoadedRecords, store.loadedUserEmail == auth.currentUser?.email,
              let section = portalRouter.pendingWidgetSection else { return }
        selectedTab = section == .visits ? 3 : 2
        portalRouter.consumeWidgetSection()
    }

    private func openPendingBusiness() {
        guard store.hasLoadedRecords, store.loadedUserEmail == auth.currentUser?.email,
              let id = portalRouter.pendingRecordID else { return }
        portalRouter.consume()
        guard store.records.contains(where: { $0.id == id }) else {
            showUnavailableBusiness = true
            return
        }
        selectedTab = 1
        // Replace a previous detail/editor with the requested business portal.
        businessPath = [id]
    }
}

// MARK: - Home

struct HomeView: View {
    @EnvironmentObject var auth: AuthStore
    @EnvironmentObject var store: AppStore
    @StateObject private var finder = PlaceFinder()
    @State private var searchText = ""
    @State private var showSearchResults = false
    @FocusState private var searchFocused: Bool
    @State private var showSavedToast = false
    @State private var reminderPlace: PlaceResult?
    @EnvironmentObject private var portalRouter: PortalRouter

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                header
                VStack(spacing: 8) {
                    searchBar
                    if showSearchResults && searchText.trimmingCharacters(in: .whitespacesAndNewlines).count >= 2 { searchSuggestions }
                }
                NativeMapView(selectedPlace: finder.selectedPlace, focusRequest: finder.mapFocus) { coordinate in
                    Task { await finder.searchNearest(to: coordinate) }
                }
                .frame(height: 330)
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))

                statusRow

                if let place = finder.selectedPlace {
                    placeCard(place)
                } else if finder.isLoading {
                    ProgressView("Buscando negocio más cercano…")
                        .frame(maxWidth: .infinity, minHeight: 120)
                }

                if let error = finder.errorMessage {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .background(AppTheme.background)
        .navigationBarHidden(true)
        .onAppear {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--verification-map") {
                Task { await MapCameraVerification.run(finder: finder) }
                return
            }
            #endif
            finder.start()
        }
        .onDisappear { reminderPlace = nil }
        .onChange(of: searchText) { query in
            showSearchResults = true
            finder.beginNameSearch(query, saved: store.records.map(\.place))
        }
        .task(id: searchText) {
            let query = searchText
            guard showSearchResults, query.trimmingCharacters(in: .whitespacesAndNewlines).count >= 2 else { return }
            do { try await Task.sleep(nanoseconds: 450_000_000) } catch { return }
            guard !Task.isCancelled else { return }
            await finder.searchByName(query, saved: store.records.map(\.place))
        }
        .overlay(alignment: .top) {
            if showSavedToast {
                Text("Enlace copiado y sitio guardado")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(.black.opacity(0.85))
                    .foregroundStyle(.white)
                    .clipShape(Capsule())
                    .padding(.top, 10)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .onChange(of: portalRouter.pendingRecordID) { id in
            if id != nil { reminderPlace = nil }
        }
        .sheet(item: $reminderPlace) { place in
            QuickReminderView(place: place)
                .environmentObject(store)
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Hola, \(auth.currentUser?.name.components(separatedBy: " ").first ?? "")")
                    .font(.title2.bold())
                Text("Obtén el enlace de reseña en segundos")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
            ProfileAvatar(size: 42)
        }
        .padding(.top, 12)
    }

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Buscar negocio por nombre", text: $searchText)
                .submitLabel(.search).focused($searchFocused).autocorrectionDisabled()
                .onSubmit { searchFocused = false; showSearchResults = true; Task { await finder.searchByName(searchText, saved: store.records.map(\.place)) } }
            if finder.isLoading { ProgressView().controlSize(.small) }
            if !searchText.isEmpty {
                Button { searchText = ""; showSearchResults = false; finder.beginNameSearch("", saved: []) } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                    .accessibilityLabel("Borrar búsqueda")
            }
        }.padding(.horizontal, 18).padding(.vertical, 16).appGlassSearch()
    }
    private var searchSuggestions: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Coincidencias y recomendaciones").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
                Button { showSearchResults = false; searchFocused = false } label: { Image(systemName: "chevron.up") }.accessibilityLabel("Ocultar resultados")
            }.padding(.horizontal, 16).padding(.vertical, 12)
            if finder.searchResults.isEmpty {
                Text(finder.isLoading ? "Buscando coincidencias…" : "Escribe el nombre y la ciudad para afinar la búsqueda.")
                    .font(.footnote).foregroundStyle(.secondary).padding(.horizontal, 16).padding(.bottom, 14)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(finder.searchResults) { place in
                            Button {
                                showSearchResults = false; searchFocused = false
                                finder.chooseSearchResult(place)
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: "mappin.circle.fill").font(.title3).foregroundStyle(AppTheme.blue)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(place.name).font(.subheadline.weight(.semibold)).foregroundStyle(.primary).lineLimit(2)
                                        Text(place.address).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                                    }
                                    Spacer(minLength: 0)
                                    Image(systemName: "arrow.up.left").font(.caption).foregroundStyle(.secondary)
                                }.padding(.horizontal, 16).padding(.vertical, 12).contentShape(Rectangle())
                            }.buttonStyle(.plain)
                            if place.id != finder.searchResults.last?.id { Divider().padding(.leading, 48) }
                        }
                    }
                }.frame(maxHeight: min(280, CGFloat(finder.searchResults.count) * 82))
            }
        }.background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private var statusRow: some View {
        HStack(spacing: 8) {
            Image(systemName: finder.isLoading ? "location.circle" : "location.fill")
                .foregroundStyle(AppTheme.blue)
            Text(finder.status).font(.footnote.weight(.medium))
            Spacer()
            if let coordinate = finder.userLocation {
                Button("Mi ubicación") {
                    showSearchResults = false; searchFocused = false
                    finder.focusOnUserLocation()
                    Task { await finder.searchNearest(to: coordinate, focusResult: false) }
                }
                .font(.footnote.weight(.semibold))
                .appSecondaryButton()
                .controlSize(.small)
            }
        }
        .padding(.horizontal, 4)
    }

    private func placeCard(_ place: PlaceResult) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("NEGOCIO SELECCIONADO")
                        .font(.caption.weight(.bold)).foregroundStyle(.secondary)
                    Text(place.name).font(.title3.bold())
                    if !place.address.isEmpty {
                        Text(place.address).font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Image(systemName: "checkmark.circle.fill")
                    .font(.title2).foregroundStyle(.green)
            }

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Text("PLACE ID").font(.caption.weight(.bold)).foregroundStyle(.secondary)
                Text(place.id).font(.system(.footnote, design: .monospaced)).textSelection(.enabled)
            }

            Button {
                UIPasteboard.general.string = place.reviewURL
                store.addOrUpdatePlace(place)
                withAnimation { showSavedToast = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.7) {
                    withAnimation { showSavedToast = false }
                }
            } label: {
                Label("Copiar enlace de reseña", systemImage: "doc.on.doc.fill")
                    .frame(maxWidth: .infinity)
            }
            .appPrimaryButton()

            Button {
                store.addOrUpdatePlace(place)
                ExternalNFCWriter.write(reviewURL: place.reviewURL)
            } label: {
                Label("Escribir NFC", systemImage: "wave.3.right")
                    .frame(maxWidth: .infinity)
            }
            .appSecondaryButton()

            Button {
                store.addOrUpdatePlace(place)
                reminderPlace = place
            } label: {
                Label("Volver más tarde", systemImage: "calendar.badge.clock")
                    .frame(maxWidth: .infinity)
            }
            .appSecondaryButton()

            Button {
                UIPasteboard.general.string = place.id
            } label: {
                Label("Copiar Place ID", systemImage: "number")
                    .frame(maxWidth: .infinity)
            }
            .appSecondaryButton()

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                Text("UBICACIÓN")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)

                ZStack {
                    PlaceMiniMap(place: place)
                        .allowsHitTesting(false)
                    Button {
                        MapLauncher.openAppleMaps(place: place)
                    } label: {
                        Color.clear
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Cómo llegar con Apple Maps")
                }
                .frame(height: 170)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(alignment: .bottomTrailing) {
                    Label("Cómo llegar", systemImage: "arrow.triangle.turn.up.right.diamond.fill")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .appGlassOverlay()
                        .padding(10)
                        .allowsHitTesting(false)
                }

                HStack(spacing: 10) {
                    Button { MapLauncher.openAppleMaps(place: place) } label: {
                        Label("Apple Maps", systemImage: "map.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .appSecondaryButton()

                    Button { MapLauncher.openGoogleMaps(place: place) } label: {
                        Label("Google Maps", systemImage: "location.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .appSecondaryButton()
                }
            }
        }
        .padding(18)
        .background(Color(uiColor: .systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

// Keep the two native compact controls on the same row as their label.
struct InlineDateTimePicker: View {
    let title: String
    @Binding var selection: Date
    let range: ClosedRange<Date>

    init(_ title: String, selection: Binding<Date>, in range: PartialRangeFrom<Date>) {
        self.title = title; _selection = selection
        self.range = range.lowerBound...Date.distantFuture
    }
    init(_ title: String, selection: Binding<Date>, in range: ClosedRange<Date>) {
        self.title = title; _selection = selection; self.range = range
    }
    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Text(title).lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
                #if DEBUG
                .background(GeometryReader { geometry in
                    Color.clear.onAppear { DateRowVerification.observe(title: title, component: "label", frame: geometry.frame(in: .global)) }
                })
                #endif
            DatePicker(title, selection: $selection, in: range, displayedComponents: [.date, .hourAndMinute])
                .datePickerStyle(.compact)
                .labelsHidden()
                .fixedSize(horizontal: true, vertical: false)
                .accessibilityLabel(title)
                #if DEBUG
                .background(GeometryReader { geometry in
                    Color.clear.onAppear { DateRowVerification.observe(title: title, component: "controls", frame: geometry.frame(in: .global)) }
                })
                #endif
        }
    }
}

#if DEBUG
@MainActor
enum DateRowVerification {
    static var frames: [String: [String: CGRect]] = [:]
    static func observe(title: String, component: String, frame: CGRect) {
        guard ProcessInfo.processInfo.arguments.contains("--verification-dates"), frame.width > 0 else { return }
        frames[title, default: [:]][component] = frame
        guard frames.count == 2, frames.values.allSatisfy({ $0.count == 2 }) else { return }
        let aligned = frames.values.allSatisfy { abs($0["label"]!.midY - $0["controls"]!.midY) < 1 }
        let output = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("date-layout-verification.json")
        try? JSONSerialization.data(withJSONObject: ["passed": aligned, "rows": frames.count], options: .prettyPrinted).write(to: output)
    }
}
#endif

// MARK: - Quick reminder

struct QuickReminderView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    let place: PlaceResult
    @State private var visitDate = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date().addingTimeInterval(86400)
    @State private var notificationDate = Calendar.current.date(byAdding: .hour, value: 23, to: Date()) ?? Date().addingTimeInterval(82800)
    @State private var notes = ""
    @State private var showNotificationHelp = false
    @FocusState private var notesFocused: Bool

    private var minimumDate: Date { Date().addingTimeInterval(5) }

    var body: some View {
        NavigationStack {
            Form {
                Section("Volver a") {
                    Text(place.name).font(.headline)
                    Text(place.address).font(.subheadline).foregroundStyle(.secondary)
                }
                Section("Visita") {
                    InlineDateTimePicker("Fecha y hora de la visita", selection: $visitDate, in: minimumDate...)
                        .onChange(of: visitDate) { newValue in
                            if notificationDate > newValue { notificationDate = newValue }
                        }
                    InlineDateTimePicker("Avisarme el", selection: $notificationDate, in: minimumDate...max(visitDate, minimumDate))
                    Text("La visita y el aviso no pueden estar en el pasado. Puedes hacer que el aviso llegue antes de la hora de la visita.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("Nota opcional") {
                    TextField("Ej. Preguntar por el encargado", text: $notes, axis: .vertical)
                        .lineLimit(2...5)
                        .focused($notesFocused)
                }
                Section("Ubicación guardada") {
                    PlaceMiniMap(place: place)
                        .frame(height: 170)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    Button { MapLauncher.openAppleMaps(place: place) } label: {
                        Label("Abrir en Apple Maps", systemImage: "map.fill")
                    }
                    Button { MapLauncher.openGoogleMaps(place: place) } label: {
                        Label("Abrir en Google Maps", systemImage: "location.fill")
                    }
                }
            }
            .navigationTitle("Volver más tarde")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") {
                        notesFocused = false
                        guard visitDate > Date(), notificationDate > Date(), notificationDate <= visitDate else { return }
                        _ = store.saveReminder(for: place, visitDate: visitDate, notificationDate: notificationDate, notes: notes)
                        dismiss()
                    }.bold()
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer(); Button("OK") { notesFocused = false }
                }
            }
        }
    }
}

// MARK: - Native MapKit map

struct NativeMapView: UIViewRepresentable {
    let selectedPlace: PlaceResult?
    let focusRequest: MapFocusRequest?
    let onTap: (CLLocationCoordinate2D) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.delegate = context.coordinator
        map.showsUserLocation = true
        map.pointOfInterestFilter = .includingAll
        map.isRotateEnabled = false
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.didTap(_:)))
        tap.cancelsTouchesInView = false
        map.addGestureRecognizer(tap)
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--verification-map") {
            MapCameraVerification.map = map
            MapCameraVerification.coordinator = context.coordinator
        }
        #endif
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        context.coordinator.parent = self
        let coordinator = context.coordinator
        if coordinator.lastPlace != selectedPlace {
            coordinator.lastPlace = selectedPlace
            map.removeAnnotations(map.annotations.filter { !($0 is MKUserLocation) })
            if let place = selectedPlace {
                let annotation = MKPointAnnotation()
                annotation.coordinate = place.coordinate
                annotation.title = place.name
                annotation.subtitle = place.address
                map.addAnnotation(annotation)
            }
        }
        guard let request = focusRequest, coordinator.lastFocusID != request.id else { return }
        coordinator.lastFocusID = request.id
        coordinator.focus(map, request: request)
    }

    static func dismantleUIView(_ map: MKMapView, coordinator: Coordinator) {
        coordinator.cancelFlight()
        map.delegate = nil
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        var parent: NativeMapView
        var lastPlace: PlaceResult?
        var lastFocusID: UUID?
        private weak var flightMap: MKMapView?
        private var flight: MapFlightPlan?
        var isFlying: Bool { flight != nil }
        private var flightRequest: MapFocusRequest?
        private var flightStarted: CFTimeInterval = 0
        private var displayLink: CADisplayLink?
        init(parent: NativeMapView) { self.parent = parent }

        private final class FrameTarget: NSObject {
            weak var owner: Coordinator?
            init(_ owner: Coordinator) { self.owner = owner }
            @objc func tick(_ link: CADisplayLink) { owner?.advanceFlight(link) }
        }

        func focus(_ map: MKMapView, request: MapFocusRequest) {
            cancelFlight()
            // Following must start after arrival; enabling it first jumps to the GPS fix.
            map.setUserTrackingMode(.none, animated: false)
            let distance: CLLocationDistance = request.target == .user ? 850 : 650
            let region = map.regionThatFits(MKCoordinateRegion(center: request.coordinate,
                latitudinalMeters: distance, longitudinalMeters: distance))
            if UIAccessibility.isReduceMotionEnabled {
                map.setRegion(region, animated: false)
                if request.target == .user { map.setUserTrackingMode(.follow, animated: false) }
                return
            }
            let from = map.visibleMapRect
            let west = MKMapPoint(CLLocationCoordinate2D(latitude: region.center.latitude,
                longitude: region.center.longitude - region.span.longitudeDelta / 2))
            let east = MKMapPoint(CLLocationCoordinate2D(latitude: region.center.latitude,
                longitude: region.center.longitude + region.span.longitudeDelta / 2))
            let north = MKMapPoint(CLLocationCoordinate2D(latitude: region.center.latitude + region.span.latitudeDelta / 2,
                longitude: region.center.longitude))
            let south = MKMapPoint(CLLocationCoordinate2D(latitude: region.center.latitude - region.span.latitudeDelta / 2,
                longitude: region.center.longitude))
            let center = MKMapPoint(request.coordinate)
            let width = abs(east.x - west.x)
            let height = abs(south.y - north.y)
            guard from.width > 0, from.height > 0, width > 0, height > 0 else { return }
            flight = MapFlightPlan(start: .init(x: from.midX, y: from.midY, width: from.width, height: from.height),
                destination: .init(x: center.x, y: center.y, width: width, height: height), worldWidth: MKMapRect.world.width)
            flightMap = map
            flightRequest = request
            flightStarted = CACurrentMediaTime()
            let target = FrameTarget(self)
            let link = CADisplayLink(target: target, selector: #selector(FrameTarget.tick(_:)))
            link.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 60, preferred: 60)
            displayLink = link
            link.add(to: .main, forMode: .common)
        }

        private func advanceFlight(_ link: CADisplayLink) {
            guard let map = flightMap, let flight, let request = flightRequest else { cancelFlight(); return }
            let elapsed = max(0, link.timestamp - flightStarted)
            let frame = flight.frame(at: elapsed)
            let v = frame.viewport
            map.setVisibleMapRect(MKMapRect(x: v.x - v.width / 2, y: v.y - v.height / 2,
                                            width: v.width, height: v.height), animated: false)
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--verification-map") {
                MapCameraVerification.samples.append(.init(elapsed: elapsed, phase: frame.phase,
                    rect: map.visibleMapRect))
            }
            #endif
            if frame.phase == .finished {
                cancelFlight()
                if request.target == .user { map.setUserTrackingMode(.follow, animated: false) }
            }
        }

        func cancelFlight() {
            displayLink?.invalidate()
            displayLink = nil
            flight = nil
            flightRequest = nil
            flightMap = nil
        }

        func mapView(_ mapView: MKMapView, regionWillChangeAnimated animated: Bool) {
            // Native pans and pinches take control immediately, without waiting for the flight.
            func isInteracting(_ view: UIView) -> Bool {
                if view.gestureRecognizers?.contains(where: { $0.state == .began || $0.state == .changed }) == true { return true }
                return view.subviews.contains(where: isInteracting)
            }
            if isInteracting(mapView) { cancelFlight() }
        }

        @objc func didTap(_ gesture: UITapGestureRecognizer) {
            guard let map = gesture.view as? MKMapView else { return }
            let point = gesture.location(in: map)
            let coordinate = map.convert(point, toCoordinateFrom: map)
            parent.onTap(coordinate)
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            if annotation is MKUserLocation { return nil }
            let id = "SelectedPlace"
            let view = mapView.dequeueReusableAnnotationView(withIdentifier: id) as? MKMarkerAnnotationView ?? MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: id)
            view.annotation = annotation
            view.markerTintColor = UIColor.systemBlue
            view.glyphImage = UIImage(systemName: "building.2.fill")
            view.canShowCallout = true
            return view
        }
    }
}

// MARK: - History / record editor

struct HistoryView: View {
    @EnvironmentObject var store: AppStore

    var body: some View {
        List {
            if store.records.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "building.2.crop.circle").font(.system(size: 42)).foregroundStyle(.secondary)
                    Text("Todavía no has guardado ningún sitio").font(.headline)
                    Text("Cuando copies un enlace desde Inicio, aparecerá aquí.")
                        .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity).padding(.vertical, 60)
                .listRowBackground(Color.clear)
            } else {
                ForEach(store.records) { record in
                    NavigationLink(value: record.id) {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(record.place.name).font(.headline)
                            Text(record.place.address).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            HStack {
                                Text(record.status.displayName)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(record.status == .completed ? .green : AppTheme.blue)
                                Spacer()
                                if record.earnings > 0 {
                                    Text(record.earnings, format: .currency(code: "EUR"))
                                        .font(.subheadline.bold())
                                }
                            }
                        }.padding(.vertical, 4)
                    }
                }
                .onDelete(perform: store.delete)
            }
        }
        .navigationTitle("Mis sitios")
    }
}

struct RecordDetailView: View {
    @EnvironmentObject var store: AppStore
    let recordID: UUID
    #if DEBUG
    @State private var verificationEditorPresented = false
    #endif

    private var record: VisitRecord? { store.records.first(where: { $0.id == recordID }) }

    var body: some View {
        Group {
            if let record {
                ScrollView {
                    VStack(spacing: 16) {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(alignment: .top) {
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(record.place.name).font(.title2.bold())
                                    Text(record.place.address).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(record.status.displayName)
                                    .font(.caption.bold())
                                    .padding(.horizontal, 10).padding(.vertical, 6)
                                    .background(record.status == .completed ? Color.green.opacity(0.14) : AppTheme.softBlue)
                                    .foregroundStyle(record.status == .completed ? .green : AppTheme.blue)
                                    .clipShape(Capsule())
                            }
                            if !record.notes.isEmpty {
                                Divider()
                                Label(record.notes, systemImage: "note.text")
                                    .font(.subheadline)
                            }
                            if record.cardsSold > 0 {
                                Divider()
                                LabeledContent("Tarjetas vendidas", value: "\(record.cardsSold)")
                            }
                            if record.cardsSold > 0 {
                                LabeledContent("Ganancia por tarjeta") {
                                    Text(record.earningsPerCard, format: .currency(code: "EUR"))
                                }
                            }
                            if record.earnings > 0 {
                                Divider()
                                LabeledContent("Ganancia total") {
                                    Text(record.earnings, format: .currency(code: "EUR")).bold()
                                }
                            }
                        }
                        .padding(18)
                        .background(Color(uiColor: .systemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))

                        if let visit = record.reminderDate, record.status != .completed {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("PRÓXIMA VISITA").font(.caption.bold()).foregroundStyle(.secondary)
                                Label(visit.formatted(date: .long, time: .shortened), systemImage: "calendar")
                                    .font(.headline)
                                if let notify = record.notificationDate ?? record.reminderDate {
                                    Label("Aviso: \(notify.formatted(date: .abbreviated, time: .shortened))", systemImage: "bell.fill")
                                        .foregroundStyle(AppTheme.blue)
                                }
                                TimelineView(.periodic(from: .now, by: 1)) { context in
                                    if visit > context.date {
                                        HStack {
                                            Image(systemName: "timer")
                                            Text("Quedan \(Self.remainingString(from: context.date, to: visit))")
                                                .font(.headline.monospacedDigit())
                                        }
                                    } else {
                                        Text("La hora prevista ya ha llegado").foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(18)
                            .background(Color(uiColor: .systemBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                        }

                        VStack(spacing: 10) {
                            Button {
                                ExternalNFCWriter.write(reviewURL: record.place.reviewURL)
                            } label: {
                                Label("Escribir NFC", systemImage: "wave.3.right")
                                    .frame(maxWidth: .infinity)
                            }
                            .appPrimaryButton()

                            Button {
                                UIPasteboard.general.string = record.place.reviewURL
                            } label: {
                                Label("Copiar enlace de reseña", systemImage: "doc.on.doc")
                                    .frame(maxWidth: .infinity)
                            }
                            .appSecondaryButton()
                        }

                        VStack(alignment: .leading, spacing: 10) {
                            Text("UBICACIÓN").font(.caption.bold()).foregroundStyle(.secondary)
                            ZStack {
                                PlaceMiniMap(place: record.place).allowsHitTesting(false)
                                Button { MapLauncher.openAppleMaps(place: record.place) } label: {
                                    Color.clear.contentShape(Rectangle())
                                }.buttonStyle(.plain)
                            }
                            .frame(height: 210)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            HStack(spacing: 10) {
                                Button { MapLauncher.openAppleMaps(place: record.place) } label: {
                                    Label("Apple Maps", systemImage: "map.fill").frame(maxWidth: .infinity)
                                }.appSecondaryButton()
                                Button { MapLauncher.openGoogleMaps(place: record.place) } label: {
                                    Label("Google Maps", systemImage: "location.fill").frame(maxWidth: .infinity)
                                }.appSecondaryButton()
                            }
                        }
                        .padding(18)
                        .background(Color(uiColor: .systemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    }
                    .padding(16)
                }
                .background(AppTheme.background)
                .navigationTitle("Ficha")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        NavigationLink("Editar", destination: RecordEditView(recordID: recordID)).bold()
                    }
                }
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "building.2").font(.system(size: 42)).foregroundStyle(.secondary)
                    Text("Sitio no encontrado").font(.headline)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        #if DEBUG
        .navigationDestination(isPresented: $verificationEditorPresented) {
            RecordEditView(recordID: recordID)
        }
        .onAppear {
            if ProcessInfo.processInfo.arguments.contains("--verification-editor") { verificationEditorPresented = true }
        }
        #endif
    }

    private static func remainingString(from: Date, to: Date) -> String {
        let seconds = max(0, Int(to.timeIntervalSince(from)))
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        let s = seconds % 60
        return h > 0 ? String(format: "%02d:%02d:%02d", h, m, s) : String(format: "%02d:%02d", m, s)
    }
}

struct RecordEditView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    let recordID: UUID

    @State private var original: VisitRecord?
    @State private var draft: VisitRecord?
    @State private var reminderEnabled = false
    @State private var unitEarningsText = ""
    @State private var showDiscardAlert = false
    @FocusState private var focusedField: EditorField?

    enum EditorField: Hashable { case notes, earnings }
    private var isSold: Bool { draft?.status == .completed }
    private var minimumDate: Date { Date().addingTimeInterval(5) }

    private var hasChanges: Bool {
        guard var draft, let original else { return false }
        guard let amount = parsedUnitEarnings else { return true }
        draft.earnings = calculatedTotal ?? 0
        if unitPriceChanged { draft.unitEarnings = amount }
        if !reminderEnabled || draft.status == .completed {
            draft.reminderDate = nil
            draft.notificationDate = nil
        }
        return draft != original
    }

    private var parsedUnitEarnings: Double? { SaleAmountFormatting.parse(unitEarningsText) }

    private var unitPriceChanged: Bool {
        guard let original, let draft else { return true }
        return unitEarningsText != (original.earningsPerCard == 0 ? "" : SaleAmountFormatting.text(for: original.earningsPerCard)) || draft.cardsSold != original.cardsSold
    }
    private var calculatedTotal: Double? {
        guard let draft, let amount = parsedUnitEarnings else { return nil }
        if !unitPriceChanged, let original { return original.earnings }
        return VisitRecord.totalEarnings(perCard: amount, count: draft.cardsSold)
    }
    private var earningsAreValid: Bool {
        guard draft != nil, let amount = parsedUnitEarnings, let total = calculatedTotal else { return false }
        return amount <= VisitRecord.maximumEarningsPerCard && MoneyLedger.cents(total) != nil && store.money.canAssign(draft!)
    }

    var body: some View {
        Form {
            if draft != nil {
                let binding = Binding<VisitRecord>(get: { draft! }, set: { draft = $0 })
                Section("Negocio") {
                    Text(binding.wrappedValue.place.name).font(.headline)
                    Text(binding.wrappedValue.place.address).foregroundStyle(.secondary)
                }
                Section("Seguimiento") {
                    Picker("Estado", selection: binding.status) {
                        Text("Contactado").tag(VisitStatus.contacted)
                        Text("Volver").tag(VisitStatus.pending)
                        Text("Vendido").tag(VisitStatus.completed)
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: binding.wrappedValue.status) { status in
                        if status == .completed {
                            draft?.cardsSold = max(1, draft?.cardsSold ?? 0)
                            reminderEnabled = false
                            draft?.reminderDate = nil
                            draft?.notificationDate = nil
                        }
                    }
                    TextField("Notas", text: binding.notes, axis: .vertical).lineLimit(3...7).focused($focusedField, equals: .notes)
                }
                Section {
                    Stepper(value: binding.cardsSold, in: (isSold ? 1 : 0)...max(100_000, original?.cardsSold ?? 0)) {
                        LabeledContent("Tarjetas vendidas", value: "\(binding.wrappedValue.cardsSold)")
                    }
                    if !store.money.products.filter({ $0.kind == .nfcCard }).isEmpty {
                        Picker("Tarjeta / color", selection: binding.inventoryProductID) {
                            Text("Sin asignar inventario").tag(UUID?.none)
                            ForEach(store.money.products.filter { $0.kind == .nfcCard }) { product in
                                Text("\(product.displayName) (\(store.money.stock(product.id)) disponibles)").tag(Optional(product.id))
                            }
                        }
                        if !store.money.canAssign(binding.wrappedValue) {
                            Text("No hay suficientes tarjetas de este color. Registra la compra en Dinero o revisa la cantidad.").font(.footnote).foregroundStyle(.red)
                        }
                    }
                    HStack {
                        Text("Ganancia por tarjeta"); Spacer()
                        TextField("0,00", text: $unitEarningsText).keyboardType(.decimalPad).multilineTextAlignment(.trailing).focused($focusedField, equals: .earnings).frame(maxWidth: 110)
                        Text("€").foregroundStyle(.secondary)
                    }
                    LabeledContent("Ganancia total") {
                        Text(calculatedTotal ?? 0, format: .currency(code: "EUR")).bold()
                    }
                    LabeledContent("Máximo por tarjeta", value: "50,00 €")
                    if let original, let amount = parsedUnitEarnings,
                       original.unitEarnings == nil, !unitPriceChanged,
                       VisitRecord.totalEarnings(perCard: amount, count: original.cardsSold) != original.earnings {
                        Text("Total de una venta anterior conservado. Cambiar el precio o la cantidad de tarjetas recalcula el total.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    if !earningsAreValid {
                        Text("Introduce una ganancia por tarjeta entre 0 € y 50 €.")
                            .font(.footnote).foregroundStyle(.red)
                    }
                } header: {
                    Text("Venta de tarjetas")
                } footer: {
                    Text("Ganancia total = tarjetas vendidas × ganancia por tarjeta. Máximo de 50 € por tarjeta.")
                }
                Section("Recordatorio") {
                    Toggle("Volver otro día", isOn: $reminderEnabled)
                        .disabled(isSold)
                        .onChange(of: reminderEnabled) { enabled in
                            if enabled && draft?.reminderDate == nil {
                                let visit = Date().addingTimeInterval(3600)
                                draft?.reminderDate = visit
                                draft?.notificationDate = Date().addingTimeInterval(1800)
                            }
                            if !enabled {
                                draft?.reminderDate = nil
                                draft?.notificationDate = nil
                            }
                        }
                    if isSold {
                        Text("Este negocio está marcado como vendido; sus avisos quedan cancelados.").font(.footnote).foregroundStyle(.secondary)
                    } else if reminderEnabled {
                        InlineDateTimePicker("Fecha y hora de la visita", selection: Binding(
                            get: { max(draft?.reminderDate ?? Date().addingTimeInterval(3600), minimumDate) },
                            set: { newValue in
                                draft?.reminderDate = newValue
                                if let n = draft?.notificationDate, n > newValue { draft?.notificationDate = newValue }
                            }
                        ), in: minimumDate...)
                        if let visit = draft?.reminderDate {
                            InlineDateTimePicker("Avisarme el", selection: Binding(
                                get: { max(min(draft?.notificationDate ?? visit, visit), minimumDate) },
                                set: { draft?.notificationDate = $0 }
                            ), in: minimumDate...max(visit, minimumDate))
                        }
                        Text("No se pueden guardar fechas pasadas. El aviso puede ser anterior a la visita.").font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("Editar")
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button { focusedField = nil; attemptDismiss() } label: { Label("Atrás", systemImage: "chevron.left") }
            }
            ToolbarItem(id: "save-business-record", placement: .confirmationAction) {
                Button("Guardar") { saveAndDismiss() }.bold().disabled(!earningsAreValid)
            }
            ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("OK") { focusedField = nil } }
        }
        .onAppear {
            if let value = store.records.first(where: { $0.id == recordID }) {
                original = value; draft = value
                reminderEnabled = value.reminderDate != nil && value.status != .completed
                unitEarningsText = value.earningsPerCard == 0 ? "" : SaleAmountFormatting.text(for: value.earningsPerCard)
                if value.notificationDate == nil { draft?.notificationDate = value.reminderDate }
                #if DEBUG
                if ProcessInfo.processInfo.arguments.contains("--verification-unit-calculation") { verifyUnitEarningsEditor() }
                #endif
            }
        }
        .alert("¿Descartar cambios?", isPresented: $showDiscardAlert) {
            Button("Seguir editando", role: .cancel) {}
            Button("Descartar", role: .destructive) { dismiss() }
        } message: { Text("Los cambios que no hayas guardado se perderán.") }
    }

    #if DEBUG
    private func verifyUnitEarningsEditor() {
        let savedDraft = draft, savedText = unitEarningsText
        unitEarningsText = "20"
        draft?.cardsSold = 3
        let three = calculatedTotal == 60 && earningsAreValid
        draft?.cardsSold = 5
        let five = calculatedTotal == 100 && earningsAreValid
        draft?.cardsSold = 1
        let one = calculatedTotal == 20 && earningsAreValid
        unitEarningsText = "51"
        let cap = !earningsAreValid
        draft = savedDraft; unitEarningsText = savedText
        let unchanged = !hasChanges
        let output = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("unit-earnings-verification.json")
        try? JSONSerialization.data(withJSONObject: ["passed": three && five && one && cap && unchanged,
            "threeCards": three, "fiveCards": five, "oneCard": one, "cap": cap, "unchanged": unchanged], options: .prettyPrinted).write(to: output)
    }
    #endif

    private func attemptDismiss() { if hasChanges { showDiscardAlert = true } else { dismiss() } }

    private func saveAndDismiss() {
        focusedField = nil
        guard earningsAreValid, var value = draft, let amount = parsedUnitEarnings else { return }
        value.earnings = calculatedTotal ?? 0
        if unitPriceChanged { value.unitEarnings = amount }
        value.normalizeSales()
        if value.status == .completed || !reminderEnabled {
            value.reminderDate = nil; value.notificationDate = nil
        } else {
            if value.reminderDate == nil || value.reminderDate! <= Date() { value.reminderDate = Date().addingTimeInterval(3600) }
            if value.notificationDate == nil || value.notificationDate! <= Date() { value.notificationDate = min(Date().addingTimeInterval(60), value.reminderDate!) }
            if value.notificationDate! > value.reminderDate! { value.notificationDate = value.reminderDate }
        }
        guard store.update(value) else { return }
        original = value; draft = value; dismiss()
    }


}

// MARK: - Reminders

struct RemindersView: View {
    @EnvironmentObject var store: AppStore
    #if DEBUG
    @State private var verificationHistoryPresented = false
    #endif

    var body: some View {
        List {
            Section {
                NotificationDiagnosticsRow()
            }
            if store.pendingReminders.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "bell.slash").font(.system(size: 40)).foregroundStyle(.secondary)
                    Text("Sin recordatorios pendientes").font(.headline)
                    Text("En un sitio guardado puedes indicar que debes volver otro día y elegir fecha y hora.")
                        .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity).padding(.vertical, 60)
                .listRowBackground(Color.clear)
            } else {
                ForEach(store.pendingReminders) { record in
                    NavigationLink(destination: RecordDetailView(recordID: record.id)) {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(record.place.name).font(.headline)
                            if let date = record.reminderDate {
                                Label("Visita: \(date.formatted(date: .abbreviated, time: .shortened))", systemImage: "calendar")
                                    .font(.subheadline).foregroundStyle(AppTheme.blue)
                            }
                            if let notify = record.notificationDate ?? record.reminderDate {
                                Label("Aviso: \(notify.formatted(date: .abbreviated, time: .shortened))", systemImage: "bell")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Label(record.place.address, systemImage: "mappin.and.ellipse")
                                .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                            if !record.notes.isEmpty {
                                Text(record.notes).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                            }
                        }.padding(.vertical, 4)
                    }
                }
            }
        }
        .navigationTitle("Recordatorios")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                NavigationLink(destination: AlertHistoryView()) {
                    Image(systemName: "bell.badge")
                }
                .accessibilityLabel("Ver historial de notificaciones y Live Activities")
            }
        }
        .onAppear {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--verification-history") {
                verificationHistoryPresented = true
                return
            }
            #endif
            NotificationManager.requestPermission()
        }
        #if DEBUG
        .navigationDestination(isPresented: $verificationHistoryPresented) { AlertHistoryView() }
        #endif
    }
}

struct NotificationDiagnosticsRow: View {
    @State private var statusText = "Comprobando notificaciones…"
    @State private var denied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: denied ? "bell.slash.fill" : "bell.badge.fill")
                    .foregroundStyle(denied ? .red : AppTheme.blue)
                Text(statusText).font(.subheadline.weight(.semibold))
            }
            Button("Probar notificación en 5 segundos") {
                NotificationManager.scheduleTest()
            }
            .appSecondaryButton()
            if denied {
                Button("Abrir Ajustes de notificaciones") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                }
            }
        }
        .onAppear { refresh() }
    }

    private func refresh() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async {
                switch settings.authorizationStatus {
                case .authorized, .provisional, .ephemeral:
                    statusText = "Notificaciones activadas"
                    denied = false
                case .denied:
                    statusText = "Notificaciones desactivadas"
                    denied = true
                case .notDetermined:
                    statusText = "Falta dar permiso a las notificaciones"
                    denied = false
                @unknown default:
                    statusText = "Comprueba las notificaciones"
                    denied = false
                }
            }
        }
    }
}

struct PlaceMiniMap: UIViewRepresentable {
    let place: PlaceResult

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.isScrollEnabled = false
        map.isZoomEnabled = false
        map.isRotateEnabled = false
        map.isPitchEnabled = false
        map.pointOfInterestFilter = .includingAll
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        map.removeAnnotations(map.annotations)
        let annotation = MKPointAnnotation()
        annotation.coordinate = place.coordinate
        annotation.title = place.name
        map.addAnnotation(annotation)
        map.setRegion(MKCoordinateRegion(center: place.coordinate, latitudinalMeters: 650, longitudinalMeters: 650), animated: false)
    }
}

// MARK: - Profile

struct ProfileView: View {
    @EnvironmentObject var auth: AuthStore
    @EnvironmentObject var store: AppStore

    var body: some View {
        List {
            Section {
                HStack(spacing: 14) {
                    ProfileAvatar(size: 64)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(auth.currentUser?.name ?? "").font(.headline)
                        Text(auth.currentUser?.email ?? "").font(.subheadline).foregroundStyle(.secondary)
                    }
                }.padding(.vertical, 8)
                ProfilePhotoPicker()
            }
            Section("Resumen") {
                LabeledContent("Sitios guardados", value: "\(store.records.count)")
                LabeledContent("Saldo", value: (Double(store.money.balanceCents) / 100).formatted(.currency(code: "EUR")))
                LabeledContent("Tarjetas vendidas", value: "\(store.totalCardsSold)")
                LabeledContent("Recordatorios", value: "\(store.pendingReminders.count)")
            }
            Section("Acerca de reviewNfcGo") {
                Text("Desarrollado por Pablo Cancho Flores")
                    .font(.subheadline)
                LabeledContent("Versión", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "4.0")
            }
            Section("Cuenta") {
                Text("Esta versión guarda la cuenta y sus datos localmente en este iPhone. No se envían a un servidor.")
                    .font(.footnote).foregroundStyle(.secondary)
                Button("Cerrar sesión", role: .destructive) { auth.logout() }
            }
        }
        .navigationTitle("Perfil")
    }
}

// MARK: - Reusable UI

struct LogoMark: View {
    let size: CGFloat
    var body: some View {
        Image("BrandMark")
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.24, style: .continuous))
            .accessibilityHidden(true)
    }
}

extension View {
    @ViewBuilder
    func appGlassSearch() -> some View {
        if #available(iOS 26.0, *) { self.glassEffect(.regular, in: .capsule) }
        else { self.background(.ultraThinMaterial, in: Capsule()) }
    }
    @ViewBuilder
    func appGlassField() -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(.regular, in: .rect(cornerRadius: 14))
        } else {
            self.background(AppTheme.card, in: RoundedRectangle(cornerRadius: 14))
        }
    }

    @ViewBuilder
    func appGlassOverlay() -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(.regular, in: .capsule)
        } else {
            self.background(.ultraThinMaterial, in: Capsule())
        }
    }

    /// Use Apple's actual interactive button styles, including system accessibility.
    @ViewBuilder
    func appPrimaryButton() -> some View {
        if #available(iOS 26.0, *) {
            self.font(.headline)
                .controlSize(.large)
                .buttonBorderShape(.capsule)
                .buttonStyle(.glassProminent)
                .tint(AppTheme.blue)
        } else {
            self.font(.headline)
                .controlSize(.large)
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.blue)
        }
    }

    @ViewBuilder
    func appSecondaryButton() -> some View {
        if #available(iOS 26.0, *) {
            self.font(.headline)
                .controlSize(.large)
                .buttonBorderShape(.capsule)
                .buttonStyle(.glass)
                .tint(AppTheme.blue)
        } else {
            self.font(.headline)
                .controlSize(.large)
                .buttonStyle(.bordered)
                .tint(AppTheme.blue)
        }
    }
}

// Compatibility alias: the old project expects ContentView to exist.
struct ContentView: View {
    var body: some View { RootView() }
}

#if DEBUG
@MainActor
enum MapCameraVerification {
    static weak var map: MKMapView?
    static weak var coordinator: NativeMapView.Coordinator?
    struct Sample {
        let elapsed: Double
        let phase: MapFlightPlan.Phase
        let rect: MKMapRect
    }
    static var samples: [Sample] = []

    static func run(finder: PlaceFinder) async {
        let output = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("map-camera-verification.json")
        var checks: [String] = []
        do {
            for _ in 0..<30 {
                if map != nil { break }
                try await Task.sleep(nanoseconds: 100_000_000)
            }
            guard let map else { throw VerificationError.failed("No se creó el mapa") }
            let madrid = CLLocation(latitude: 40.4168, longitude: -3.7038)
            let seville = PlaceResult(id: "verification-seville", name: "Negocio en Sevilla",
                address: "Sevilla", latitude: 37.3891, longitude: -5.9845)
            let barcelona = CLLocationCoordinate2D(latitude: 41.3874, longitude: 2.1686)
            finder.prepareMapVerification()
            finder.locationManager(CLLocationManager(), didUpdateLocations: [madrid])
            try await assertFocus(map, on: madrid.coordinate, label: "Primera ubicación", checks: &checks)
            samples.removeAll()
            finder.selectPlace(seville, focus: true)
            try await assertFocus(map, on: seville.coordinate, label: "Búsqueda lejos de la ubicación", checks: &checks)
            guard let early = samples.first(where: { $0.elapsed > 0.35 && $0.elapsed < 0.55 }),
                  let middle = samples.first(where: { $0.elapsed > 1.05 && $0.elapsed < 1.25 }),
                  let late = samples.first(where: { $0.elapsed > 1.8 && $0.elapsed < 2.0 }),
                  let finish = samples.first(where: { $0.phase == .finished }),
                  middle.rect.width > early.rect.width * 5,
                  finish.rect.width < middle.rect.width / 20,
                  hypot(middle.rect.midX - early.rect.midX, middle.rect.midY - early.rect.midY) > 10000,
                  hypot(middle.rect.midX - late.rect.midX, middle.rect.midY - late.rect.midY) > 10000,
                  hypot(late.rect.midX - finish.rect.midX, late.rect.midY - finish.rect.midY) > 1
            else { throw VerificationError.failed("Desplazamiento y zoom simultáneos") }
            checks.append("Desplazamiento y zoom simultáneos en una curva continua")
            finder.locationManager(CLLocationManager(), didUpdateLocations: [madrid])
            try await Task.sleep(nanoseconds: 500_000_000)
            try await assertFocus(map, on: seville.coordinate, label: "El GPS no interrumpe el negocio buscado", checks: &checks)
            map.setRegion(MKCoordinateRegion(center: barcelona, latitudinalMeters: 900, longitudinalMeters: 900), animated: false)
            finder.selectPlace(seville, focus: true)
            try await assertFocus(map, on: seville.coordinate, label: "Volver a buscar el mismo negocio después de mover el mapa", checks: &checks)
            finder.focusOnUserLocation()
            try await assertFocus(map, on: madrid.coordinate, label: "Mi ubicación después de una búsqueda", checks: &checks)
            map.setUserTrackingMode(.none, animated: false)
            map.setRegion(MKCoordinateRegion(center: barcelona, latitudinalMeters: 900, longitudinalMeters: 900), animated: false)
            finder.focusOnUserLocation()
            try await assertFocus(map, on: madrid.coordinate, label: "Mi ubicación después de arrastrar el mapa", checks: &checks)
            // A new search interrupts the flight and starts from the current visible camera.
            finder.selectPlace(seville, focus: true)
            try await Task.sleep(nanoseconds: 900_000_000)
            finder.focusOnUserLocation()
            try await assertFocus(map, on: madrid.coordinate, label: "Interrumpir el vuelo con un nuevo destino", checks: &checks)
            finder.selectPlace(seville, focus: true)
            try await Task.sleep(nanoseconds: 900_000_000)
            coordinator?.cancelFlight()
            map.setRegion(MKCoordinateRegion(center: barcelona, latitudinalMeters: 900, longitudinalMeters: 900), animated: false)
            try await Task.sleep(nanoseconds: 1_800_000_000)
            try await assertFocus(map, on: barcelona, label: "Cancelar el vuelo devuelve el control al mapa", checks: &checks)
            finder.focusOnUserLocation()
            try await assertFocus(map, on: madrid.coordinate, label: "Volver a ubicación después de cancelar el vuelo", checks: &checks)
            finder.selectPlace(nil, focus: false)
            try JSONSerialization.data(withJSONObject: ["passed": true, "checks": checks], options: .prettyPrinted).write(to: output)
        } catch {
            try? JSONSerialization.data(withJSONObject: ["passed": false, "checks": checks, "error": String(describing: error)], options: .prettyPrinted).write(to: output)
        }
    }

    private static func assertFocus(_ map: MKMapView, on coordinate: CLLocationCoordinate2D,
                                    label: String, checks: inout [String]) async throws {
        let target = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        for _ in 0..<60 {
            let actual = CLLocation(latitude: map.centerCoordinate.latitude, longitude: map.centerCoordinate.longitude)
            if actual.distance(from: target) < 100 && map.region.span.latitudeDelta < 0.03 && coordinator?.isFlying != true {
                checks.append(label)
                return
            }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        throw VerificationError.failed(label)
    }

    private enum VerificationError: Error { case failed(String) }
}
#endif
