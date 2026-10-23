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
        guard let location = locations.last, location.horizontalAccuracy.isFinite, location.horizontalAccuracy >= 0,
              abs(location.timestamp.timeIntervalSinceNow) <= NearbyBusinessSelection.maximumLocationAge,
              CLLocationCoordinate2DIsValid(location.coordinate) else { return }
        let isFirstLocation = userLocation == nil
        latestLocation = location
        userLocation = location.coordinate
        if isFirstLocation && mapFocus == nil { focusOnUserLocation(cancelSearch: false) }
        guard NearbyBusinessSelection.usableLocation(accuracy: location.horizontalAccuracy, timestamp: location.timestamp) else {
            status = "Ubicación aproximada · ±\(Int(location.horizontalAccuracy)) m. Esperando más precisión…"
            return
        }
        status = "Ubicación encontrada · ±\(Int(location.horizontalAccuracy)) m"
        if pendingUserSelection {
            pendingUserSelection = false; didInitialSearch = true
            focusOnUserLocation()
            Task { await searchNearest(to: location.coordinate, focusResult: false, accuracy: location.horizontalAccuracy, advanceAlternative: true) }
        } else if !didInitialSearch {
            didInitialSearch = true
            if searchRevision == nil {
                Task {
                    guard self.searchRevision == nil else { return }
                    await searchNearest(to: location.coordinate, focusResult: false, accuracy: location.horizontalAccuracy)
                }
            }
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
        guard let location = latestLocation,
              NearbyBusinessSelection.usableLocation(accuracy: location.horizontalAccuracy, timestamp: location.timestamp) else {
            pendingUserSelection = true
            status = "Esperando una ubicación reciente y más precisa…"
            start()
            return
        }
        focusOnUserLocation()
        await searchNearest(to: location.coordinate, focusResult: false, accuracy: location.horizontalAccuracy, advanceAlternative: true)
    }

    func searchNearest(to coordinate: CLLocationCoordinate2D, focusResult: Bool = true, accuracy: Double = 15, advanceAlternative: Bool = false) async {
        let revision = UUID()
        searchRevision = revision
        pendingUserSelection = false
        isLoading = true
        isFindingNearby = true
        errorMessage = nil
        defer { if searchRevision == revision { isLoading = false; isFindingNearby = false } }

        guard NearbyBusinessSelection.validCoordinate(latitude: coordinate.latitude, longitude: coordinate.longitude),
              accuracy.isFinite, (0...NearbyBusinessSelection.maximumAccuracy).contains(accuracy) else {
            status = "No hay suficiente precisión para elegir un negocio. Puedes buscarlo por su nombre."
            return
        }
        if let cycle = nearbyCycle, cycle.canReuse(latitude: coordinate.latitude, longitude: coordinate.longitude, accuracy: accuracy) {
            applyNearbySelection(cycle, advance: advanceAlternative && nearbyPosition > 0, focus: focusResult)
            return
        }
        nearbyCycle = nil
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
        if !advance && NearbyBusinessSelection.isAmbiguous(cycle.candidates, latitude: cycle.latitude, longitude: cycle.longitude, accuracy: cycle.accuracy) {
            selectPlace(nil, focus: false)
            nearbyChoices = Array(cycle.candidates.prefix(2))
            status = "Hay dos locales muy cerca. Elige el tuyo."
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
        selectPlace(cycle.candidates[index], focus: true)
        nearbyPosition = index + 1; nearbyCount = cycle.candidates.count
        status = "Negocio seleccionado"
    }

    func beginNameSearch(_ query: String, saved: [PlaceResult]) {
        pendingUserSelection = false; nearbyChoices = []
        searchRevision = UUID(); isLoading = false; isFindingNearby = false; errorMessage = nil
        if !query.isEmpty { didInitialSearch = true }
        searchResults = SearchSuggestions.savedMatches(query, places: saved)
    }
    func chooseSearchResult(_ place: PlaceResult) {
        pendingUserSelection = false
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
        let url = URL(string: "https://places.googleapis.com/v1/places:searchNearby")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "X-Goog-Api-Key")
        request.setValue("places.id,places.displayName,places.formattedAddress,places.location,places.types,places.primaryType,places.businessStatus", forHTTPHeaderField: "X-Goog-FieldMask")
        let body: [String: Any] = [
            "maxResultCount": 20,
            "rankPreference": "DISTANCE",
            "locationRestriction": [
                "circle": [
                    "center": ["latitude": coordinate.latitude, "longitude": coordinate.longitude],
                    "radius": NearbyBusinessSelection.searchRadius
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
