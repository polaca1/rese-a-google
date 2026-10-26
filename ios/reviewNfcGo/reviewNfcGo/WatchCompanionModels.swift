import Foundation

enum WatchSnapshotError: Error { case invalid }
struct WatchCompanionBusiness: Codable, Equatable, Identifiable {
    var id: UUID
    var name: String
    var address: String
    var latitude: Double
    var longitude: Double
    var visitDate: Date?
    var completed: Bool
    var arrived: Bool
    var incomeCents: Int64
    var mapsURL: URL? {
        var url = URLComponents(string: "https://maps.apple.com/")!
        url.queryItems = [URLQueryItem(name: "daddr", value: "\(latitude),\(longitude)"), URLQueryItem(name: "q", value: name), URLQueryItem(name: "dirflg", value: "w")]
        return url.url
    }
}
struct WatchCompanionSnapshot: Codable, Equatable {
    var schema = 1
    var generatedAt = Date()
    var ownerID: String? = nil
    var balanceCents: Int64? = nil
    var dayIncomeCents: Int64? = nil
    var cardsSold: Int? = nil
    var businesses: [WatchCompanionBusiness] = []
    var isAvailable: Bool { ownerID != nil }
    func validated() throws -> Self {
        guard schema == 1, generatedAt.timeIntervalSince1970.isFinite, businesses.count <= 40,
              Set(businesses.map(\.id)).count == businesses.count else { throw WatchSnapshotError.invalid }
        if let ownerID {
            guard ownerID.range(of: "^[0-9a-f]{64}$", options: .regularExpression) != nil,
                  let balanceCents, (-100_000_000_000_000...100_000_000_000_000).contains(balanceCents),
                  let dayIncomeCents, (-100_000_000_000_000...100_000_000_000_000).contains(dayIncomeCents),
                  let cardsSold, (0...100_000_000).contains(cardsSold) else { throw WatchSnapshotError.invalid }
        } else {
            guard balanceCents == nil, dayIncomeCents == nil, cardsSold == nil, businesses.isEmpty else { throw WatchSnapshotError.invalid }
        }
        for item in businesses {
            guard !item.name.isEmpty, item.name.count <= 160, item.address.count <= 220,
                  item.latitude.isFinite, item.longitude.isFinite,
                  (-90...90).contains(item.latitude), (-180...180).contains(item.longitude),
                  (-100_000_000_000_000...100_000_000_000_000).contains(item.incomeCents),
                  item.visitDate.map({ $0.timeIntervalSince1970.isFinite }) ?? true else { throw WatchSnapshotError.invalid }
        }
        return self
    }
    static func decode(_ data: Data) throws -> Self {
        guard data.count <= 60_000 else { throw WatchSnapshotError.invalid }
        return try JSONDecoder().decode(Self.self, from: data).validated()
    }
    var nextVisit: WatchCompanionBusiness? {
        businesses.filter { !$0.completed && !$0.arrived && $0.visitDate != nil }
            .min { $0.visitDate! < $1.visitDate! }
    }
}
