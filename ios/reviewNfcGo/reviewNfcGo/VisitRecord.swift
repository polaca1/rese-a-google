import Foundation
#if canImport(CoreLocation)
import CoreLocation
#endif

struct PlaceResult: Identifiable, Codable, Equatable {
    let id: String
    let name: String
    let address: String
    let latitude: Double
    let longitude: Double

    #if canImport(CoreLocation)
    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
    #endif

    var reviewURL: String {
        "https://search.google.com/local/writereview?placeid=\(id)"
    }
}

enum VisitStatus: String, Codable, CaseIterable {
    case contacted = "Contactado"
    case pending = "Volver otro día"
    case completed = "Completado"

    var displayName: String {
        switch self {
        case .contacted: return "Contactado"
        case .pending: return "Volver otro día"
        case .completed: return "Ya lo he vendido"
        }
    }
}

enum ContactStage: String, Codable, CaseIterable, Identifiable {
    case pending = "Pendiente", interested = "Interesado", returnLater = "Volver", sold = "Vendido"
    var id: String { rawValue }
}
struct FollowUpEvent: Identifiable, Codable, Equatable {
    var id = UUID()
    var date = Date()
    var text: String
    var isVisit = false
}
struct VisitRecord: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var place: PlaceResult
    var createdAt: Date = Date()
    var earnings: Double = 0
    var cardsSold: Int = 0
    /// Nil preserves historical total amounts that cannot be split exactly into cents.
    var unitEarnings: Double? = nil
    var inventoryProductID: UUID? = nil
    var arrivedAt: Date? = nil
    var notes: String = ""
    var status: VisitStatus = .contacted
    /// Fecha/hora de la visita prevista.
    var reminderDate: Date? = nil
    /// Momento en el que el usuario quiere recibir el aviso. Si es nil, se avisa a la hora de la visita.
    var notificationDate: Date? = nil

    var interested: Bool? = nil
    var followUp: [FollowUpEvent]? = nil
    var hasQuickSales: Bool? = nil
    var trackingStage: ContactStage {
        get { status == .completed ? .sold : status == .pending ? .returnLater : interested == true ? .interested : .pending }
        set {
            // Tracking a completed deal does not invent a legacy card sale.
            if newValue == .sold && cardsSold == 0 { hasQuickSales = true }
            interested = newValue == .interested
            status = newValue == .sold ? .completed : newValue == .returnLater ? .pending : .contacted
        }
    }
    mutating func trackChanges(from old: VisitRecord?, now: Date = Date()) {
        var events = followUp ?? []
        if let old, old.trackingStage != trackingStage { events.append(FollowUpEvent(date: now, text: "Estado: " + trackingStage.rawValue)) }
        if let old, old.notes != notes { events.append(FollowUpEvent(date: now, text: notes.isEmpty ? "Nota eliminada" : notes)) }
        if let arrivedAt, arrivedAt != old?.arrivedAt, !events.contains(where: { $0.isVisit && abs($0.date.timeIntervalSince(arrivedAt)) < 1 }) {
            events.append(FollowUpEvent(date: arrivedAt, text: "Visita realizada", isVisit: true))
        }
        followUp = events.isEmpty ? nil : Array(events.suffix(1000))
    }
    static let maximumEarningsPerCard: Double = 50
    var maximumEarnings: Double { Double(max(0, cardsSold)) * Self.maximumEarningsPerCard }
    var earningsPerCard: Double { unitEarnings ?? (cardsSold > 0 ? earnings / Double(cardsSold) : 0) }
    static func totalEarnings(perCard: Double, count: Int) -> Double {
        (((perCard * 100).rounded() / 100) * Double(max(0, count)) * 100).rounded() / 100
    }
    var cardsSoldDescription: String { cardsSold == 1 ? "1 tarjeta vendida" : "\(cardsSold) tarjetas vendidas" }

    mutating func normalizeSales() {
        cardsSold = max(status == .completed && hasQuickSales != true ? 1 : 0, cardsSold)
        if let unitEarnings {
            let unit = unitEarnings.isFinite ? min(max(0, unitEarnings), Self.maximumEarningsPerCard) : 0
            self.unitEarnings = (unit * 100).rounded() / 100
            earnings = Self.totalEarnings(perCard: self.unitEarnings!, count: cardsSold)
        }
        earnings = earnings.isFinite ? min(max(0, earnings), maximumEarnings) : 0
    }

    enum CodingKeys: String, CodingKey {
        case interested, followUp, hasQuickSales
        case id, place, createdAt, earnings, cardsSold, unitEarnings, inventoryProductID, arrivedAt, notes, status, reminderDate, notificationDate
    }
}

extension VisitRecord {
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        place = try values.decode(PlaceResult.self, forKey: .place)
        createdAt = try values.decode(Date.self, forKey: .createdAt)
        earnings = try values.decode(Double.self, forKey: .earnings)
        notes = try values.decode(String.self, forKey: .notes)
        status = try values.decode(VisitStatus.self, forKey: .status)
        reminderDate = try values.decodeIfPresent(Date.self, forKey: .reminderDate)
        notificationDate = try values.decodeIfPresent(Date.self, forKey: .notificationDate)
        if let count = try values.decodeIfPresent(Int.self, forKey: .cardsSold) {
            cardsSold = count
        } else {
            // Older versions stored only the amount. Infer a count without losing existing earnings.
            let inferred = ceil(max(0, earnings) / Self.maximumEarningsPerCard)
            cardsSold = inferred >= Double(Int.max) ? Int.max : Int(inferred)
        }
        unitEarnings = try values.decodeIfPresent(Double.self, forKey: .unitEarnings)
        inventoryProductID = try values.decodeIfPresent(UUID.self, forKey: .inventoryProductID)
        arrivedAt = try values.decodeIfPresent(Date.self, forKey: .arrivedAt)
        interested = try values.decodeIfPresent(Bool.self, forKey: .interested)
        followUp = try values.decodeIfPresent([FollowUpEvent].self, forKey: .followUp)
        hasQuickSales = try values.decodeIfPresent(Bool.self, forKey: .hasQuickSales)
        normalizeSales()
    }
}


enum SaleAmountFormatting {
    private static let formatter: NumberFormatter = {
        let value = NumberFormatter()
        value.locale = Locale(identifier: "es_ES")
        value.numberStyle = .decimal
        value.usesGroupingSeparator = false
        value.minimumFractionDigits = 0
        value.maximumFractionDigits = 2
        return value
    }()

    static func text(for amount: Double) -> String {
        formatter.string(from: NSNumber(value: amount)) ?? String(amount)
    }

    static func parse(_ text: String) -> Double? {
        var value = text.replacingOccurrences(of: "€", with: "").replacingOccurrences(of: " ", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
        if value.isEmpty { return 0 }
        if value.contains(",") { value = value.replacingOccurrences(of: ".", with: "").replacingOccurrences(of: ",", with: ".") }
        guard let amount = Double(value), amount.isFinite, amount >= 0 else { return nil }
        return amount
    }
}
