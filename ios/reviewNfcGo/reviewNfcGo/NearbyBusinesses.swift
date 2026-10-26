import Foundation

/// Google metadata is decoded in the same way on iPhone and Mac.
struct GooglePlaceSearchResponse: Decodable {
    struct APIPlace: Decodable {
        struct DisplayName: Decodable { let text: String }
        struct Location: Decodable { let latitude: Double; let longitude: Double }
        let id: String
        let displayName: DisplayName?
        let formattedAddress: String?
        let location: Location?
        let types: [String]?
        let primaryType: String?
        let businessStatus: String?
    }
    let places: [APIPlace]?

    var results: [PlaceResult] {
        (places ?? []).compactMap { place in
            guard let location = place.location,
                  NearbyBusinessSelection.validCoordinate(latitude: location.latitude, longitude: location.longitude),
                  !place.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  let name = place.displayName?.text.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else { return nil }
            return PlaceResult(id: place.id, name: name, address: place.formattedAddress ?? "",
                               latitude: location.latitude, longitude: location.longitude,
                               types: place.types, primaryType: place.primaryType, businessStatus: place.businessStatus)
        }
    }
}

enum NearbyBusinessSelection {
    static let searchRadius = 250.0
    static let maximumAccuracy = 80.0
    static let maximumLocationAge = 20.0
    static let cacheLifetime = 60.0

    static func validCoordinate(latitude: Double, longitude: Double) -> Bool {
        latitude.isFinite && longitude.isFinite && (-90...90).contains(latitude) && (-180...180).contains(longitude)
    }

    static func usableLocation(accuracy: Double, timestamp: Date, now: Date = Date()) -> Bool {
        accuracy.isFinite && accuracy >= 0 && accuracy <= maximumAccuracy
            && abs(timestamp.timeIntervalSince(now)) <= maximumLocationAge
    }

    static func preferPreviousFix(previousAccuracy: Double, previousAge: TimeInterval, newAccuracy: Double, movement: Double) -> Bool {
        previousAccuracy.isFinite && newAccuracy.isFinite && movement.isFinite && movement >= 0
            && (0...5).contains(previousAge) && previousAccuracy >= 0 && newAccuracy >= 0
            && previousAccuracy < newAccuracy * 0.7 && movement <= max(10, newAccuracy)
    }

    static func distance(latitude: Double, longitude: Double, to place: PlaceResult) -> Double {
        distance(latitude: latitude, longitude: longitude, toLatitude: place.latitude, toLongitude: place.longitude)
    }

    static func distance(latitude: Double, longitude: Double, toLatitude: Double, toLongitude: Double) -> Double {
        let radians = Double.pi / 180
        let a = sin((toLatitude - latitude) * radians / 2)
        let b = sin((toLongitude - longitude) * radians / 2)
        let h = a * a + cos(latitude * radians) * cos(toLatitude * radians) * b * b
        return 6_371_000 * 2 * asin(sqrt(min(1, max(0, h))))
    }

    private static let geographicTypes: Set<String> = [
        "route", "street_address", "intersection", "premise", "subpremise", "postal_code",
        "locality", "sublocality", "neighborhood", "country", "political", "geocode"
    ]
    private static func geographic(_ type: String) -> Bool {
        geographicTypes.contains(type) || type.hasPrefix("administrative_area_")
            || type.hasPrefix("sublocality_level_") || type.hasPrefix("postal_code_")
    }
    private static func isBusiness(_ place: PlaceResult) -> Bool {
        if place.businessStatus == "CLOSED_PERMANENTLY" { return false }
        if let primary = place.primaryType, geographic(primary) { return false }
        let types = place.types ?? []
        let specific = types.filter { !["establishment", "point_of_interest"].contains($0) }
        if !specific.isEmpty && specific.allSatisfy(geographic) { return false }
        return !place.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !place.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && validCoordinate(latitude: place.latitude, longitude: place.longitude)
    }

    /// Only breaks distance ties. A clearly closer office always precedes a farther bar.
    private static func categoryPriority(_ place: PlaceResult) -> Int {
        let primary = place.primaryType
        let types = primary.map { ["establishment", "point_of_interest"].contains($0) ? (place.types ?? []) : [$0] } ?? (place.types ?? [])
        let food: Set<String> = ["bar", "pub", "cafe", "coffee_shop", "restaurant", "bakery", "meal_takeaway", "meal_delivery", "night_club", "food_court"]
        let retail: Set<String> = ["store", "supermarket", "grocery_store", "convenience_store", "pharmacy", "shopping_mall", "market"]
        let offices: Set<String> = ["insurance_agency", "bank", "accounting", "lawyer", "real_estate_agency", "corporate_office", "finance", "consulting_firm"]
        let base: Int
        if types.contains(where: { food.contains($0) || $0.hasSuffix("_restaurant") }) { base = 0 }
        else if types.contains(where: { retail.contains($0) || $0.hasSuffix("_store") }) { base = 1 }
        else if types.contains(where: { offices.contains($0) }) { base = 3 }
        else { base = 2 }
        return base + (place.businessStatus == "CLOSED_TEMPORARILY" ? 10 : 0)
    }

    static func ranked(_ places: [PlaceResult], latitude: Double, longitude: Double, accuracy: Double) -> [PlaceResult] {
        guard validCoordinate(latitude: latitude, longitude: longitude), accuracy.isFinite,
              (0...maximumAccuracy).contains(accuracy) else { return [] }
        // Google often pins a business at the building centre, not the entrance.
        // Retain these real candidates; distant/uncertain matches require confirmation.
        let radius = searchRadius
        let sorted = places.filter(isBusiness).map { (place: $0, distance: distance(latitude: latitude, longitude: longitude, to: $0)) }
            .filter { $0.distance <= radius }
            .sorted {
                if $0.distance != $1.distance { return $0.distance < $1.distance }
                let a = categoryPriority($0.place), b = categoryPriority($1.place)
                if a != b { return a < b }
                return $0.place.id < $1.place.id
            }
        var seen = Set<String>()
        let unique = sorted.filter { seen.insert($0.place.id).inserted }
        // Fixed, anchored groups avoid a non-transitive "within epsilon" sorting comparator.
        let tolerance = min(4, max(1, accuracy * 0.2))
        var ranked: [PlaceResult] = []
        var start = 0
        while start < unique.count {
            var end = start + 1
            while end < unique.count && unique[end].distance - unique[start].distance <= tolerance { end += 1 }
            let group = unique[start..<end].sorted {
                let a = categoryPriority($0.place), b = categoryPriority($1.place)
                if a != b { return a < b }
                if $0.distance != $1.distance { return $0.distance < $1.distance }
                return $0.place.id < $1.place.id
            }
            ranked.append(contentsOf: group.map(\.place))
            start = end
        }
        return ranked
    }

    static func isAmbiguous(_ candidates: [PlaceResult], latitude: Double, longitude: Double, accuracy: Double) -> Bool {
        guard let first = candidates.first, accuracy.isFinite, (0...maximumAccuracy).contains(accuracy) else { return false }
        let closestDistance = distance(latitude: latitude, longitude: longitude, to: first)
        if accuracy > 30 || closestDistance > max(25, min(45, accuracy + 10)) { return true }
        guard candidates.count >= 2 else { return false }
        let a = candidates[0], b = candidates[1]
        let da = distance(latitude: latitude, longitude: longitude, to: a)
        let db = distance(latitude: latitude, longitude: longitude, to: b)
        let gap = abs(da - db)
        if accuracy >= 25 && max(da, db) <= accuracy + 10 && gap <= min(12, accuracy * 0.25) { return true }
        guard gap <= min(12, max(4, accuracy * 0.6)) else { return false }
        let pa = categoryPriority(a), pb = categoryPriority(b)
        // A public-facing shop versus an office has the clear tie-breaker requested by the user.
        let categoryTie = gap <= min(4, max(1, accuracy * 0.2))
        let clearTieBreak = categoryTie && ((pa <= 1 && pb == 3) || (pb <= 1 && pa == 3))
        return !clearTieBreak
    }
}

struct NearbyBusinessCycle {
    let candidates: [PlaceResult]
    let latitude: Double
    let longitude: Double
    let accuracy: Double
    let createdAt: Date

    func canReuse(latitude: Double, longitude: Double, accuracy: Double, now: Date = Date()) -> Bool {
        guard !candidates.isEmpty, NearbyBusinessSelection.validCoordinate(latitude: latitude, longitude: longitude),
              accuracy.isFinite, (0...NearbyBusinessSelection.maximumAccuracy).contains(accuracy),
              (0..<NearbyBusinessSelection.cacheLifetime).contains(now.timeIntervalSince(createdAt)) else { return false }
        let movement = NearbyBusinessSelection.distance(latitude: latitude, longitude: longitude,
                                                        toLatitude: self.latitude, toLongitude: self.longitude)
        // Keep a stable order under GPS jitter, but refresh once the user walks elsewhere.
        if accuracy <= self.accuracy * 0.65 { return false }
        return movement <= max(10, min(18, max(accuracy, self.accuracy)))
    }

    func selection(after id: String?, advance: Bool) -> (place: PlaceResult, position: Int)? {
        guard !candidates.isEmpty else { return nil }
        let index: Int
        if advance, let id, let current = candidates.firstIndex(where: { $0.id == id }) { index = (current + 1) % candidates.count }
        else { index = 0 }
        return (candidates[index], index + 1)
    }
}

enum NearbySearchCoverage {
    // Types checked against Google Places Table A. Two bounded, complementary queries.
    static let businessTypes = ["restaurant", "cafe", "bar", "bakery", "supermarket", "pharmacy", "lodging", "gym", "insurance_agency", "store", "bank", "real_estate_agency", "clothing_store", "electronics_store", "hair_care", "beauty_salon", "car_repair", "dentist", "doctor", "hardware_store", "furniture_store", "florist", "book_store", "laundry", "veterinary_care", "convenience_store", "shoe_store", "lawyer", "accounting"]
    static func body(latitude: Double, longitude: Double, wider: Bool) -> [String: Any] {
        var value: [String: Any] = ["maxResultCount": 20, "rankPreference": "DISTANCE", "locationRestriction": ["circle": ["center": ["latitude": latitude, "longitude": longitude], "radius": wider ? NearbyBusinessSelection.searchRadius : 90.0]]]
        if wider { value["includedTypes"] = businessTypes }
        return value
    }
}
