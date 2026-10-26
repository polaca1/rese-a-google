import Foundation

@main struct NearbyBusinessTests {
    static func main() throws {
        var checks = 0
        func check(_ value: Bool, _ message: String) { precondition(value, message); checks += 1 }
        let latitude = 40.4168, longitude = -3.7038
        func place(_ id: String, meters: Double, type: String? = nil, status: String? = nil) -> PlaceResult {
            PlaceResult(id: id, name: id, address: "Calle de prueba", latitude: latitude + meters / 6_371_000 * 180 / .pi,
                        longitude: longitude, types: type.map { [$0, "point_of_interest", "establishment"] }, primaryType: type, businessStatus: status)
        }
        func rank(_ values: [PlaceResult], accuracy: Double = 15) -> [PlaceResult] {
            NearbyBusinessSelection.ranked(values, latitude: latitude, longitude: longitude, accuracy: accuracy)
        }
        func ambiguous(_ values: [PlaceResult], accuracy: Double = 15) -> Bool {
            NearbyBusinessSelection.isAmbiguous(rank(values, accuracy: accuracy), latitude: latitude, longitude: longitude, accuracy: accuracy)
        }
        let bar = place("bar", meters: 5, type: "bar")
        let insurer = place("insurer", meters: 5, type: "insurance_agency")
        check(rank([insurer, bar]).map(\.id) == ["bar", "insurer"], "Bar precedes insurance at the same distance")
        check(!ambiguous([insurer, bar]), "The requested bar/office tie has a clear preference")
        check(rank([place("bar-far", meters: 50, type: "bar"), insurer], accuracy: 40).first?.id == "insurer", "Five-meter insurer wins over fifty-meter bar")
        check(rank([place("bar-far", meters: 18, type: "bar"), insurer]).first?.id == "insurer", "Type does not override a clear thirteen-meter distance difference")
        check(rank([insurer, place("shop", meters: 5, type: "clothing_store")]).first?.id == "shop", "Shop wins a distance tie against an office")
        check(rank([insurer, place("restaurant", meters: 5, type: "spanish_restaurant")]).first?.id == "restaurant", "Specific Google restaurant categories are recognized")
        check(rank([place("closed", meters: 1, type: "bar", status: "CLOSED_PERMANENTLY"), insurer]).map(\.id) == ["insurer"], "Permanently closed business is excluded")
        check(rank([place("street", meters: 0, type: "route"), insurer]).map(\.id) == ["insurer"], "Street geography is never selected as a business")
        check(rank([place("postal", meters: 0, type: "postal_code"), insurer]).count == 1, "Postal areas do not become businesses")
        check(rank([bar, bar, insurer]).count == 2, "Duplicate place IDs are removed")
        check(rank([place("building-centre", meters: 120, type: "bar")]).count == 1 && ambiguous([place("building-centre", meters: 120, type: "bar")]), "A building-centre pin remains available but requires confirmation")
        check(rank([place("outside-area", meters: 280, type: "bar")]).isEmpty, "Candidates outside the bounded search area are rejected")
        check(rank([place("unknown", meters: 3)]).count == 1, "Missing optional category keeps a real nearby business")
        check(rank([bar], accuracy: 200).isEmpty, "Poor GPS does not choose a random business")
        check(rank([bar], accuracy: -.infinity).isEmpty, "Invalid accuracy is rejected")
        var invalid = bar
        invalid = PlaceResult(id: "invalid", name: "Invalid", address: "", latitude: .nan, longitude: 0)
        check(rank([invalid, bar]).map(\.id) == ["bar"], "Invalid coordinates are filtered")
        let cafe = place("cafe", meters: 6, type: "cafe")
        check(ambiguous([bar, cafe]), "Two equally plausible cafes require a user choice")
        check(ambiguous([bar, insurer], accuracy: 35), "Uncertain GPS offers two choices even when categories differ")
        check(!ambiguous([bar]), "A single candidate is not ambiguous")
        check(!ambiguous([bar, place("other", meters: 30, type: "cafe")]), "Clearly separated businesses do not trigger unnecessary choice")
        check(ambiguous([place("a", meters: 5), place("b", meters: 5)]), "Unknown categories at the same distance cannot produce false confidence")
        let shuffled = [cafe, insurer, bar]
        check(rank(shuffled).map(\.id) == rank(Array(shuffled.reversed())).map(\.id), "Ranking is stable under Google response reordering")
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let cycle = NearbyBusinessCycle(candidates: rank([insurer, bar]), latitude: latitude, longitude: longitude, accuracy: 5, createdAt: now)
        check(cycle.selection(after: nil, advance: false)?.place.id == "bar", "First selection starts with the most likely candidate")
        check(cycle.selection(after: "bar", advance: true)?.place.id == "insurer", "Second tap selects insurance")
        check(cycle.selection(after: "insurer", advance: true)?.place.id == "bar", "The list wraps after the last candidate")
        check(cycle.selection(after: "manual", advance: true)?.place.id == "bar", "A manual search outside the list restarts at the first candidate")
        check(cycle.canReuse(latitude: latitude, longitude: longitude, accuracy: 5, now: now.addingTimeInterval(30)), "Repeated tap reuses results instead of charging another query")
        check(cycle.canReuse(latitude: place("jitter", meters: 8).latitude, longitude: longitude, accuracy: 10, now: now.addingTimeInterval(30)), "Small GPS jitter retains a stable cycle")
        check(!cycle.canReuse(latitude: place("moved", meters: 60).latitude, longitude: longitude, accuracy: 5, now: now.addingTimeInterval(30)), "Walking elsewhere refreshes results")
        check(!cycle.canReuse(latitude: latitude, longitude: longitude, accuracy: 5, now: now.addingTimeInterval(121)), "Expired results are refreshed")
        check(!cycle.canReuse(latitude: latitude, longitude: longitude, accuracy: 5, now: now.addingTimeInterval(-1)), "A clock moving backwards cannot reuse a future cache")
        let single = NearbyBusinessCycle(candidates: [bar], latitude: latitude, longitude: longitude, accuracy: 5, createdAt: now)
        check(single.selection(after: "bar", advance: true)?.position == 1, "Single candidate cycles safely")
        let empty = NearbyBusinessCycle(candidates: [], latitude: latitude, longitude: longitude, accuracy: 5, createdAt: now)
        check(empty.selection(after: nil, advance: true) == nil, "An empty cycle never invents a candidate")
        check(NearbyBusinessSelection.usableLocation(accuracy: 5, timestamp: now, now: now), "Fresh precise fixes are usable")
        check(!NearbyBusinessSelection.usableLocation(accuracy: 5, timestamp: now.addingTimeInterval(-60), now: now), "A stale last-known position is rejected")
        check(!NearbyBusinessSelection.usableLocation(accuracy: 300, timestamp: now, now: now), "An imprecise fix waits for improvement")
        let legacy = Data("{\"id\":\"legacy\",\"name\":\"Old business\",\"address\":\"Street\",\"latitude\":40,\"longitude\":-3}".utf8)
        let decodedLegacy = try JSONDecoder().decode(PlaceResult.self, from: legacy)
        check(decodedLegacy.types == nil && decodedLegacy.primaryType == nil, "Older saved copies remain readable")
        let encoded = try JSONEncoder().encode(bar)
        check(try JSONDecoder().decode(PlaceResult.self, from: encoded) == bar, "Google category metadata survives device synchronization")
        let response: [String: Any] = ["places": [
            ["id": "real", "displayName": ["text": "Café real"], "location": ["latitude": latitude, "longitude": longitude], "types": ["cafe"], "primaryType": "cafe", "businessStatus": "OPERATIONAL"],
            ["id": "nameless", "location": ["latitude": latitude, "longitude": longitude]],
            ["id": "missing-location", "displayName": ["text": "Missing"]]
        ]]
        let parsed = try JSONDecoder().decode(GooglePlaceSearchResponse.self, from: JSONSerialization.data(withJSONObject: response)).results
        check(parsed.count == 1 && parsed[0].name == "Café real" && parsed[0].primaryType == "cafe" && parsed[0].businessStatus == "OPERATIONAL", "Parser preserves real names and categories; never invents a business for incomplete data")
        check(ambiguous([bar], accuracy: 45), "Poor precision requires confirmation even with only one real match")
        check(ambiguous([place("one", meters: 8, type: "cafe"), place("two", meters: 16, type: "cafe")], accuracy: 20), "GPS uncertainty between neighbouring doors does not produce false confidence")
        check(!cycle.canReuse(latitude: latitude, longitude: longitude, accuracy: 2, now: now.addingTimeInterval(10)), "Much better GPS invalidates results ranked using an older imprecise fix")
        check(NearbyBusinessSelection.preferPreviousFix(previousAccuracy: 4, previousAge: 2, newAccuracy: 45, movement: 6), "Brief GPS degradation keeps the fresh precise fix")
        check(!NearbyBusinessSelection.preferPreviousFix(previousAccuracy: 4, previousAge: 7, newAccuracy: 45, movement: 6), "Old precise fixes cannot freeze the user at another doorway")
        check(!NearbyBusinessSelection.preferPreviousFix(previousAccuracy: 4, previousAge: 2, newAccuracy: 45, movement: 100), "Walking away overrides the earlier precise fix")
        let closeBody = NearbySearchCoverage.body(latitude: latitude, longitude: longitude, wider: false)
        let wideBody = NearbySearchCoverage.body(latitude: latitude, longitude: longitude, wider: true)
        check(closeBody["includedTypes"] == nil && (wideBody["includedTypes"] as? [String])?.contains("insurance_agency") == true, "Wider business query supplements the unrestricted doorway query without excluding insurers")
        check((wideBody["includedTypes"] as? [String])?.contains("store") == true && NearbySearchCoverage.businessTypes.count <= 50, "Business coverage includes shops within Google request limits")
        check(closeBody["maxResultCount"] as? Int == 20 && wideBody["maxResultCount"] as? Int == 20, "Location lookup makes two bounded result sets, not an unbounded pagination loop")
        print("Nearby business ranking and choices: \(checks) checks passed")
    }
}
