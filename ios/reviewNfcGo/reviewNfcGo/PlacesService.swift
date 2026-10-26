import SwiftUI
import MapKit
import CoreLocation
import UserNotifications
import UIKit
import ActivityKit

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
    @Published private(set) var nearbyPosition = 0
    @Published private(set) var nearbyCount = 0
    @Published private(set) var nearbyChoices: [PlaceResult] = []
    @Published private(set) var nearbyCandidates: [PlaceResult] = []
    @Published var isLoading = false
    @Published private(set) var isFindingNearby = false
    @Published var status = "Buscando tu ubicación…"
    @Published var errorMessage: String?

    private let manager = CLLocationManager()
    private var didInitialSearch = false
    private var searchRevision: UUID?
    private var nearbyCycle: NearbyBusinessCycle?
    private var latestLocation: CLLocation?
    private var pendingUserSelection = false
    private var waitingForBetterFix = false
    private var automaticRefinement = false
    private let nearbyLookup: (CLLocationCoordinate2D) async throws -> [PlaceResult]
    private var apiKey: String {
        Bundle.main.object(forInfoDictionaryKey: "GooglePlacesAPIKey") as? String ?? ""
    }

    override convenience init() {
        self.init(nearbyLookup: { coordinate in
            let key = Bundle.main.object(forInfoDictionaryKey: "GooglePlacesAPIKey") as? String ?? ""
            return try await GooglePlacesService(apiKey: key).nearby(coordinate: coordinate)
        })
    }

    init(nearbyLookup: @escaping (CLLocationCoordinate2D) async throws -> [PlaceResult]) {
        self.nearbyLookup = nearbyLookup
        super.init()
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--verification-map") || ProcessInfo.processInfo.arguments.contains("--verification-nearby") { didInitialSearch = true }
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
        let valid = locations.filter { $0.horizontalAccuracy.isFinite && $0.horizontalAccuracy >= 0 && abs($0.timestamp.timeIntervalSinceNow) <= NearbyBusinessSelection.maximumLocationAge && CLLocationCoordinate2DIsValid($0.coordinate) }
        let fresh = valid.filter { abs($0.timestamp.timeIntervalSinceNow) <= 5 }
        guard var location = (fresh.isEmpty ? valid : fresh).min(by: { $0.horizontalAccuracy < $1.horizontalAccuracy }) else { return }
        if let previous = latestLocation, NearbyBusinessSelection.preferPreviousFix(previousAccuracy: previous.horizontalAccuracy, previousAge: Date().timeIntervalSince(previous.timestamp), newAccuracy: location.horizontalAccuracy, movement: previous.distance(from: location)) { location = previous }

        let isFirstLocation = userLocation == nil
        latestLocation = location
        userLocation = location.coordinate
        if isFirstLocation && mapFocus == nil { focusOnUserLocation(cancelSearch: false) }
        guard NearbyBusinessSelection.usableLocation(accuracy: location.horizontalAccuracy, timestamp: location.timestamp) else {
            status = "Ubicación aproximada · ±\(Int(location.horizontalAccuracy)) m. Esperando más precisión…"
            return
        }
        status = "Ubicación encontrada · ±\(Int(location.horizontalAccuracy)) m"
        if waitingForBetterFix { return }
        if pendingUserSelection {
            pendingUserSelection = false; didInitialSearch = true
            focusOnUserLocation()
            let revision = searchRevision
            Task { guard self.searchRevision == revision else { return }; await searchNearest(to: location.coordinate, focusResult: false, accuracy: location.horizontalAccuracy, advanceAlternative: true) }
        } else if !didInitialSearch {
            didInitialSearch = true
            if searchRevision == nil {
                Task {
                    if location.horizontalAccuracy > 12 { try? await Task.sleep(for: .milliseconds(1500)) }
                    guard self.searchRevision == nil, let improved = self.latestLocation,
                          NearbyBusinessSelection.usableLocation(accuracy: improved.horizontalAccuracy, timestamp: improved.timestamp) else { return }
                    await searchNearest(to: improved.coordinate, focusResult: false, accuracy: improved.horizontalAccuracy)
                }
            }
        } else if automaticRefinement, let cycle = nearbyCycle, cycle.accuracy >= 25, location.horizontalAccuracy <= 15, !isFindingNearby {
            automaticRefinement = false
            let revision = searchRevision
            Task { guard self.searchRevision == revision else { return }; await searchNearest(to: location.coordinate, focusResult: false, accuracy: location.horizontalAccuracy) }
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        errorMessage = error.localizedDescription
    }

    func focusOnUserLocation(cancelSearch: Bool = true) {
        if cancelSearch { searchRevision = UUID(); isLoading = false; isFindingNearby = false }
        guard let coordinate = userLocation else { start(); return }
        mapFocus = MapFocusRequest(coordinate: coordinate, target: .user)
    }

    func selectPlace(_ place: PlaceResult?, focus: Bool) {
        selectedPlace = place
        nearbyPosition = 0; nearbyCount = 0; nearbyChoices = []
        if focus, let place {
            mapFocus = MapFocusRequest(coordinate: place.coordinate, target: .place)
        }
    }

    #if DEBUG
    func prepareMapVerification() { didInitialSearch = true }
    func prepareNearbyChoicesVerification(_ candidates: [PlaceResult], coordinate: CLLocationCoordinate2D) {
        didInitialSearch = true
        userLocation = coordinate
        latestLocation = CLLocation(coordinate: coordinate, altitude: 0, horizontalAccuracy: 5, verticalAccuracy: 5, timestamp: Date())
        let cycle = NearbyBusinessCycle(candidates: NearbyBusinessSelection.ranked(candidates, latitude: coordinate.latitude, longitude: coordinate.longitude, accuracy: 5),
                                        latitude: coordinate.latitude, longitude: coordinate.longitude, accuracy: 5, createdAt: Date())
        nearbyCycle = cycle
        focusOnUserLocation()
        applyNearbySelection(cycle, advance: false, focus: false)
    }
    #endif

    func useMyLocation() async {
        guard !isFindingNearby else { return }
        if manager.accuracyAuthorization == .reducedAccuracy {
            manager.requestTemporaryFullAccuracyAuthorization(withPurposeKey: "NearbyBusiness")
        }
        let needsFreshFix = latestLocation.map { $0.horizontalAccuracy > 15 || abs($0.timestamp.timeIntervalSinceNow) > 5 } ?? true
        if needsFreshFix {
            let revision = UUID(); searchRevision = revision
            pendingUserSelection = true; waitingForBetterFix = true
            isFindingNearby = true; isLoading = true
            status = "Afinando tu ubicación…"
            manager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
            start(); manager.requestLocation()
            try? await Task.sleep(for: .milliseconds(2500))
            guard searchRevision == revision else { return }
            waitingForBetterFix = false; isFindingNearby = false; isLoading = false
            manager.desiredAccuracy = kCLLocationAccuracyBest
        }
        guard !Task.isCancelled, let location = latestLocation,
              NearbyBusinessSelection.usableLocation(accuracy: location.horizontalAccuracy, timestamp: location.timestamp) else {
            pendingUserSelection = true
            selectPlace(nil, focus: false); nearbyCandidates = []
            status = "Necesito una ubicación más precisa. Activa Ubicación precisa o busca el local por nombre."
            start(); return
        }
        pendingUserSelection = false
        focusOnUserLocation()
        await searchNearest(to: location.coordinate, focusResult: false, accuracy: location.horizontalAccuracy, advanceAlternative: true)
    }

    func searchNearest(to coordinate: CLLocationCoordinate2D, focusResult: Bool = true, accuracy: Double = 15, advanceAlternative: Bool = false) async {
        let revision = UUID()
        searchRevision = revision
        pendingUserSelection = false; waitingForBetterFix = false
        automaticRefinement = !focusResult && !advanceAlternative
        isLoading = true
        isFindingNearby = true
        errorMessage = nil
        defer { if searchRevision == revision { isLoading = false; isFindingNearby = false } }

        guard NearbyBusinessSelection.validCoordinate(latitude: coordinate.latitude, longitude: coordinate.longitude),
              accuracy.isFinite, (0...NearbyBusinessSelection.maximumAccuracy).contains(accuracy) else {
            selectPlace(nil, focus: false); nearbyCandidates = []
            status = "No hay suficiente precisión para elegir un negocio. Puedes buscarlo por su nombre."
            return
        }
        if let cycle = nearbyCycle, cycle.canReuse(latitude: coordinate.latitude, longitude: coordinate.longitude, accuracy: accuracy) {
            applyNearbySelection(cycle, advance: advanceAlternative && nearbyPosition > 0, focus: focusResult)
            return
        }
        nearbyCycle = nil; nearbyCandidates = []
        selectPlace(nil, focus: false)
        do {
            let found = try await nearbyLookup(coordinate)
            guard !Task.isCancelled, searchRevision == revision else { return }
            let results = NearbyBusinessSelection.ranked(found, latitude: coordinate.latitude, longitude: coordinate.longitude, accuracy: accuracy)
            guard !results.isEmpty else {
                status = "No se ha encontrado un local lo bastante cerca. Busca por nombre o toca su punto en el mapa."
                return
            }
            let cycle = NearbyBusinessCycle(candidates: results, latitude: coordinate.latitude, longitude: coordinate.longitude,
                                            accuracy: accuracy, createdAt: Date())
            nearbyCycle = cycle
            applyNearbySelection(cycle, advance: false, focus: focusResult)
        } catch {
            guard !Task.isCancelled, searchRevision == revision else { return }
            errorMessage = "No se pudieron consultar los negocios. Comprueba la conexión y vuelve a intentarlo."
        }
    }

    private func applyNearbySelection(_ cycle: NearbyBusinessCycle, advance: Bool, focus: Bool) {
        nearbyCandidates = cycle.candidates
        if !advance && NearbyBusinessSelection.isAmbiguous(cycle.candidates, latitude: cycle.latitude, longitude: cycle.longitude, accuracy: cycle.accuracy) {
            selectPlace(nil, focus: false)
            nearbyChoices = Array(cycle.candidates.prefix(2))
            status = nearbyChoices.count > 1 ? "Confirma el local: hay varias opciones cercanas." : "Confirma el local antes de escribir la tarjeta."
            return
        }
        guard let selection = cycle.selection(after: selectedPlace?.id, advance: advance) else { return }
        selectPlace(selection.place, focus: focus)
        nearbyPosition = selection.position; nearbyCount = cycle.candidates.count
        status = "Local cercano \(nearbyPosition) de \(nearbyCount)"
    }

    func chooseNearbyPlace(_ place: PlaceResult) {
        guard nearbyChoices.contains(where: { $0.id == place.id }), let cycle = nearbyCycle,
              let index = cycle.candidates.firstIndex(where: { $0.id == place.id }) else { return }
        searchRevision = UUID(); isLoading = false; isFindingNearby = false; pendingUserSelection = false
        automaticRefinement = false; waitingForBetterFix = false
        selectPlace(cycle.candidates[index], focus: true)
        nearbyPosition = index + 1; nearbyCount = cycle.candidates.count
        status = "Negocio seleccionado"
    }

    func chooseNearbyCandidate(_ place: PlaceResult) {
        guard nearbyCandidates.contains(where: { $0.id == place.id }), let cycle = nearbyCycle,
              let index = cycle.candidates.firstIndex(where: { $0.id == place.id }) else { return }
        searchRevision = UUID(); pendingUserSelection = false; waitingForBetterFix = false; automaticRefinement = false
        isLoading = false; isFindingNearby = false
        selectPlace(cycle.candidates[index], focus: true)
        nearbyPosition = index + 1; nearbyCount = cycle.candidates.count; status = "Negocio seleccionado"
    }
    func distanceText(to place: PlaceResult) -> String? {
        guard let cycle = nearbyCycle else { return nil }
        let meters = NearbyBusinessSelection.distance(latitude: cycle.latitude, longitude: cycle.longitude, to: place)
        return "≈ \(Int(meters.rounded())) m"
    }

    func beginNameSearch(_ query: String, saved: [PlaceResult]) {
        pendingUserSelection = false; nearbyChoices = []; nearbyCandidates = []
        automaticRefinement = false; waitingForBetterFix = false
        searchRevision = UUID(); isLoading = false; isFindingNearby = false; errorMessage = nil
        if !query.isEmpty { didInitialSearch = true }
        searchResults = SearchSuggestions.savedMatches(query, places: saved)
    }
    func chooseSearchResult(_ place: PlaceResult) {
        pendingUserSelection = false; automaticRefinement = false; waitingForBetterFix = false; nearbyCandidates = []
        searchRevision = UUID(); isLoading = false; isFindingNearby = false; searchResults = []
        selectPlace(place, focus: true); status = "Negocio seleccionado"
    }
    func searchByName(_ query: String, saved: [PlaceResult] = []) async {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.count >= 2 else { return }
        let revision = UUID(); searchRevision = revision; didInitialSearch = true
        isFindingNearby = false
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

    func nearby(coordinate: CLLocationCoordinate2D) async throws -> [PlaceResult] {
        func request(wider: Bool) throws -> URLRequest {
            var value = URLRequest(url: URL(string: "https://places.googleapis.com/v1/places:searchNearby")!)
            value.httpMethod = "POST"
            value.setValue("application/json", forHTTPHeaderField: "Content-Type")
            value.setValue(apiKey, forHTTPHeaderField: "X-Goog-Api-Key")
            value.setValue("places.id,places.displayName,places.formattedAddress,places.location,places.types,places.primaryType,places.businessStatus", forHTTPHeaderField: "X-Goog-FieldMask")
            value.httpBody = try JSONSerialization.data(withJSONObject: NearbySearchCoverage.body(latitude: coordinate.latitude, longitude: coordinate.longitude, wider: wider))
            return value
        }
        let closeRequest = try request(wider: false), widerRequest = try request(wider: true)
        async let close: [PlaceResult]? = try? execute(closeRequest)
        async let wider: [PlaceResult]? = try? execute(widerRequest)
        let (front, businesses) = await (close, wider)
        guard front != nil || businesses != nil else { throw URLError(.badServerResponse) }
        var seen = Set<String>()
        return ((front ?? []) + (businesses ?? [])).filter { seen.insert($0.id).inserted }
    }

    func textSearch(query: String, bias: CLLocationCoordinate2D?) async throws -> [PlaceResult] {
        let url = URL(string: "https://places.googleapis.com/v1/places:searchText")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "X-Goog-Api-Key")
        request.setValue("places.id,places.displayName,places.formattedAddress,places.location,places.types,places.primaryType,places.businessStatus", forHTTPHeaderField: "X-Goog-FieldMask")
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
        var boundedRequest = request
        boundedRequest.timeoutInterval = 20
        let (data, response) = try await PlacesTransport.execute(boundedRequest)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode), data.count <= 2_000_000 else {
            throw NSError(domain: "PlaceSearch", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "La búsqueda no está disponible. Vuelve a intentarlo más tarde."])
        }
        return try JSONDecoder().decode(GooglePlaceSearchResponse.self, from: data).results
    }
}
