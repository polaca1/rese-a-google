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
            errorMessage = "No se pudieron consultar los negocios. Comprueba la conexión y vuelve a intentarlo."
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
        var boundedRequest = request
        boundedRequest.timeoutInterval = 20
        let (data, response) = try await PlacesTransport.execute(boundedRequest)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode), data.count <= 2_000_000 else {
            throw NSError(domain: "PlaceSearch", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "La búsqueda no está disponible. Vuelve a intentarlo más tarde."])
        }
        let decoded = try JSONDecoder().decode(NearbyResponse.self, from: data)
        return (decoded.places ?? []).compactMap { place in
            guard let loc = place.location, !place.id.isEmpty, CLLocationCoordinate2DIsValid(CLLocationCoordinate2D(latitude: loc.latitude, longitude: loc.longitude)) else { return nil }
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
