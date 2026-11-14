import Foundation

enum SearchSuggestions {
    static func normalize(_ value: String) -> String { value.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "es_ES")) }
    static func savedMatches(_ query: String, places: [PlaceResult]) -> [PlaceResult] {
        let text = normalize(query.trimmingCharacters(in: .whitespacesAndNewlines))
        guard text.count >= 2 else { return [] }
        let words = text.split(separator: " ").map(String.init)
        return places.filter { place in
            let value = normalize(place.name + " " + place.address)
            return words.allSatisfy { value.contains($0) }
        }.sorted { a, b in
            let aa = normalize(a.name), bb = normalize(b.name)
            let scoreA = aa == text ? 3 : aa.hasPrefix(text) ? 2 : aa.contains(text) ? 1 : 0
            let scoreB = bb == text ? 3 : bb.hasPrefix(text) ? 2 : bb.contains(text) ? 1 : 0
            return scoreA == scoreB ? aa < bb : scoreA > scoreB
        }
    }
    static func merge(local: [PlaceResult], remote: [PlaceResult]) -> [PlaceResult] {
        var seen = Set<String>()
        return (local + remote).filter { seen.insert($0.id).inserted }.prefix(10).map { $0 }
    }
}
