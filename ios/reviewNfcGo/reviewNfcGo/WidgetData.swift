import Foundation

struct WidgetPlace: Codable, Identifiable, Equatable {
    let id: UUID
    let name: String
    let address: String
    let latitude: Double
    let longitude: Double
    let visitDate: Date?
    let createdAt: Date
    let cardsSold: Int
    let earnings: Double
}

struct WidgetMoneyOperation: Codable, Identifiable, Equatable {
    let id: UUID
    let name: String
    let amount: Double
    let date: Date
    let businessID: UUID?
}

struct WidgetSnapshot: Codable, Equatable {
    var isSignedIn: Bool
    var updatedAt: Date
    var pending: [WidgetPlace]
    var operations: [WidgetPlace]
    var totalEarnings: Double
    var totalCards: Int
    var moneyBalance: Double? = nil
    var moneyExpenses: Double? = nil
    var moneyOperations: [WidgetMoneyOperation]? = nil
    var balance: Double { moneyBalance ?? totalEarnings }
    var expenses: Double { moneyExpenses ?? 0 }

    static let empty = WidgetSnapshot(isSignedIn: false, updatedAt: .distantPast,
        pending: [], operations: [], totalEarnings: 0, totalCards: 0)

    init(isSignedIn: Bool, updatedAt: Date, pending: [WidgetPlace], operations: [WidgetPlace], totalEarnings: Double, totalCards: Int) {
        self.isSignedIn = isSignedIn; self.updatedAt = updatedAt; self.pending = pending
        self.operations = operations; self.totalEarnings = totalEarnings; self.totalCards = totalCards
    }
    init(records: [VisitRecord], isSignedIn: Bool, now: Date = Date()) {
        self.isSignedIn = isSignedIn; updatedAt = now
        guard isSignedIn else { pending = []; operations = []; totalEarnings = 0; totalCards = 0; return }
        func place(_ record: VisitRecord) -> WidgetPlace {
            WidgetPlace(id: record.id, name: record.place.name, address: record.place.address,
                latitude: record.place.latitude, longitude: record.place.longitude,
                visitDate: record.arrivedAt == nil ? record.reminderDate : nil, createdAt: record.createdAt,
                cardsSold: record.cardsSold, earnings: record.earnings)
        }
        pending = records.filter { $0.status != .completed && ($0.status == .pending || $0.reminderDate != nil) }
            .map(place).sorted { ($0.visitDate ?? .distantFuture) < ($1.visitDate ?? .distantFuture) }
        operations = records.filter { $0.earnings > 0 || $0.cardsSold > 0 }.map(place)
            .sorted { $0.createdAt > $1.createdAt }
        totalEarnings = records.reduce(0) { $0 + $1.earnings }
        totalCards = records.reduce(0) { $0 + $1.cardsSold }
    }
    var nextVisits: [WidgetPlace] { pending.filter { $0.visitDate != nil } }
    var validMapPlaces: [WidgetPlace] {
        pending.filter { $0.latitude.isFinite && $0.longitude.isFinite && abs($0.latitude) <= 85 && abs($0.longitude) <= 180 }
    }
    // Densest 2.5 km neighborhood, not a centroid of disconnected cities.
    var densePlaces: [WidgetPlace] {
        let places = validMapPlaces
        var best: [WidgetPlace] = []
        for anchor in places {
            let group = places.filter { Self.distance(anchor, $0) <= 2500 }
            if group.count > best.count { best = group }
        }
        return best
    }
    static func distance(_ a: WidgetPlace, _ b: WidgetPlace) -> Double {
        let rad = Double.pi / 180
        let lat = (b.latitude - a.latitude) * rad
        let lon = (b.longitude - a.longitude) * rad
        let h = pow(sin(lat / 2), 2) + cos(a.latitude * rad) * cos(b.latitude * rad) * pow(sin(lon / 2), 2)
        return 6371000 * 2 * asin(sqrt(min(1, max(0, h))))
    }
}

enum WidgetSection: String {
    case visits, earnings
    var url: URL { URL(string: "reviewnfcgo://widgets/\(rawValue)")! }
    static func parse(_ url: URL) -> WidgetSection? {
        guard let c = URLComponents(url: url, resolvingAgainstBaseURL: false),
              c.scheme?.lowercased() == "reviewnfcgo", c.host?.lowercased() == "widgets",
              c.user == nil, c.password == nil, c.port == nil, c.query == nil, c.fragment == nil else { return nil }
        let segments = c.path.split(separator: "/", omittingEmptySubsequences: false)
        guard segments.count == 2, segments[0].isEmpty else { return nil }
        return WidgetSection(rawValue: String(segments[1]))
    }
}
