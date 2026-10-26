import Foundation

enum CardLinkError: LocalizedError {
    case invalid, conflict, notReady, unavailable, inactive
    var errorDescription: String? {
        switch self {
        case .invalid: return "No se pudieron comprobar los datos de esta tarjeta."
        case .conflict: return "La tarjeta ha cambiado desde otro dispositivo. Recarga sus datos antes de guardar."
        case .notReady: return "Las tarjetas y sus estadísticas todavía no están disponibles. Inténtalo más tarde."
        case .unavailable: return "No se pudo conectar. Tus cambios aún no se han aplicado. Vuelve a intentarlo."
        case .inactive: return "Este enlace está desactivado. Actívalo antes de escribir la tarjeta."
        }
    }
}

struct ManagedReviewLink: Decodable, Equatable, Identifiable {
    let id: UUID
    let user_id: String
    let business_id: UUID?
    var place_id: String? = nil
    let target_url: String
    let active: Bool
    let revision: Int64
    let updated_at: String
    let label: String
    var permanentURL: String { ReviewLinkAddress.permanent(id) }
    var defaultGoogleURL: String? {
        guard let place_id, !place_id.isEmpty, place_id.count <= 500 else { return nil }
        var url = URLComponents(string: "https://search.google.com/local/writereview")!
        url.queryItems = [URLQueryItem(name: "placeid", value: place_id)]; return url.string
    }
    func validate(owner: String, expected: UUID) throws {
        guard UUID(uuidString: owner) != nil, UUID(uuidString: user_id) != nil,
              id == expected, user_id.lowercased() == owner.lowercased(), revision > 0, revision < Int64.max,
              label.count <= 500, ReviewLinkAddress.validTarget(target_url),
              place_id.map({ !$0.isEmpty && $0.count <= 500 }) ?? true,
              CardLinkDates.timestamp(updated_at) != nil else { throw CardLinkError.invalid }
    }
}

struct CardOpeningDay: Decodable, Identifiable, Equatable {
    let day: String
    let opens: Int64
    var id: String { day }
    var date: Date? { CardLinkDates.day(day) }
}
struct CardStatistics: Decodable, Equatable {
    let link_id: UUID
    let total: Int64
    let last_7_days: Int64
    let last_30_days: Int64
    let last_opened_at: String?
    let first_recorded_day: String?
    let daily: [CardOpeningDay]
    func validate(linkID: UUID) throws {
        guard link_id == linkID, total >= 0, last_7_days >= 0,
              last_7_days <= last_30_days, last_30_days <= total,
              daily.count <= 31, Set(daily.map(\.day)).count == daily.count,
              daily.allSatisfy({ $0.date != nil && (0...total).contains($0.opens) }),
              last_opened_at.map({ CardLinkDates.timestamp($0) != nil }) ?? true,
              first_recorded_day.map({ CardLinkDates.day($0) != nil }) ?? true else { throw CardLinkError.invalid }
        var sum: Int64 = 0
        for day in daily {
            let addition = sum.addingReportingOverflow(day.opens)
            guard !addition.overflow else { throw CardLinkError.invalid }; sum = addition.partialValue
        }
        guard sum <= total else { throw CardLinkError.invalid }
    }
}

enum CardLinkDates {
    static var utcCalendar: Calendar {
        var value = Calendar(identifier: .gregorian); value.timeZone = TimeZone(secondsFromGMT: 0)!; return value
    }
    static func timestamp(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }
    static func day(_ value: String) -> Date? {
        guard value.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil else { return nil }
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian); formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"; formatter.isLenient = false
        guard let date = formatter.date(from: value), formatter.string(from: date) == value else { return nil }; return date
    }
}

enum CardLinkRules {
    static func validTarget(_ value: String, linkID: UUID) -> Bool {
        guard ReviewLinkAddress.validTarget(value),
              let destination = URLComponents(string: value),
              let permanent = URLComponents(string: ReviewLinkAddress.permanent(linkID)) else { return false }
        // Chaining managed links can create redirect loops and inflate opening counts.
        return !(destination.host?.lowercased() == permanent.host?.lowercased() && destination.path == permanent.path)
    }
    static func visits(_ record: VisitRecord) -> [FollowUpEvent] {
        var values = (record.followUp ?? []).filter(\.isVisit)
        if let arrived = record.arrivedAt, !values.contains(where: { abs($0.date.timeIntervalSince(arrived)) < 1 }) {
            values.append(FollowUpEvent(date: arrived, text: "Visita realizada", isVisit: true))
        }
        return values.sorted { $0.date > $1.date }
    }
    static func confirmedWrites(_ record: VisitRecord) -> [NFCWritingEvent] {
        (record.nfcWrites ?? []).filter { $0.status == .confirmed }.sorted { $0.date > $1.date }
    }
}

enum ClientDirectoryFilter: String, CaseIterable, Identifiable {
    case all = "Todos", customers = "Clientes", visits = "Visitas"
    var id: String { rawValue }
    func matches(_ record: VisitRecord, income: Int64, cards: Int) -> Bool {
        switch self {
        case .all: return true
        case .customers: return income > 0 || cards > 0
        case .visits: return record.reminderDate != nil || !CardLinkRules.visits(record).isEmpty
        }
    }
}

extension VisitRecord {
    mutating func applyManagedLink(_ link: ManagedReviewLink) throws {
        try link.validate(owner: link.user_id, expected: link.id)
        guard link.business_id == nil || link.business_id == id,
              reviewLinkID == nil || reviewLinkID == link.id else { throw CardLinkError.invalid }
        reviewLinkID = link.id; reviewLinkTarget = link.target_url; reviewLinkActive = link.active
    }
    mutating func prepareCardWriting(link: ManagedReviewLink, now: Date = Date()) throws -> NFCWritingEvent {
        guard link.active else { throw CardLinkError.inactive }
        guard CardLinkRules.validTarget(link.target_url, linkID: link.id) else { throw CardLinkError.invalid }
        try applyManagedLink(link)
        let event = NFCWritingEvent(date: now, linkID: link.id, writtenURL: link.permanentURL, initialTarget: link.target_url)
        nfcWrites = Array(((nfcWrites ?? []) + [event]).suffix(1000))
        return event
    }
    mutating func finishCardWriting(_ eventID: UUID, confirmed: Bool, now: Date = Date()) throws {
        guard var values = nfcWrites, let index = values.firstIndex(where: { $0.id == eventID }) else { throw CardLinkError.invalid }
        let status: NFCWritingStatus = confirmed ? .confirmed : .cancelled
        if values[index].status == status { return }
        guard values[index].status == .prepared else { throw CardLinkError.conflict }
        values[index].status = status; values[index].confirmedAt = confirmed ? now : nil
        nfcWrites = values
    }
}
