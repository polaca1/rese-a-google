import Foundation

@main struct CardLinksTests {
    static func main() throws {
        var checks = 0
        func check(_ value: Bool, _ label: String) { precondition(value, label); checks += 1 }
        func rejects(_ action: () throws -> Void) {
            do { try action(); preconditionFailure("Invalid operation was accepted") }
            catch { checks += 1 }
        }
        let owner = UUID().uuidString, id = UUID()
        let place = PlaceResult(id: "ChIJ-test", name: "Café de la Plaza", address: "Calle Mayor", latitude: 40, longitude: -3)
        var record = VisitRecord(place: place)
        func link(target: String? = nil, active: Bool = true, revision: Int64 = 1) -> ManagedReviewLink {
            ManagedReviewLink(id: id, user_id: owner, business_id: record.id, target_url: target ?? place.reviewURL,
                              active: active, revision: revision, updated_at: "2026-10-26T12:00:00.123456+00:00", label: place.name)
        }
        let original = link()
        try original.validate(owner: owner, expected: id)
        check(original.target_url == place.reviewURL, "The default destination uses this business's Place ID")
        let event = try record.prepareCardWriting(link: original)
        check(record.reviewLinkID == id && event.writtenURL == ReviewLinkAddress.permanent(id), "The NFC payload is the stable managed link, not the Google URL")
        check(event.status == .prepared && event.confirmedAt == nil && CardLinkRules.confirmedWrites(record).isEmpty,
              "Launching the writer never invents a confirmed physical write")
        check(record.cardsSold == 0 && record.earnings == 0 && record.status == .contacted, "Preparing a card never creates a sale")
        try record.finishCardWriting(event.id, confirmed: true)
        check(CardLinkRules.confirmedWrites(record).count == 1 && record.nfcWrites?.first?.confirmedAt != nil, "The user's confirmation records the write")
        try record.finishCardWriting(event.id, confirmed: true)
        check(record.nfcWrites?.count == 1, "Repeated confirmation is idempotent")
        rejects { try record.finishCardWriting(event.id, confirmed: false) }
        let replacement = link(target: "https://example.org/new", revision: 2)
        try record.applyManagedLink(replacement)
        check(record.reviewLinkTarget == replacement.target_url && record.nfcWrites?.first?.writtenURL == original.permanentURL,
              "A remote destination change leaves the URL already stored on a locked tag unchanged")
        check(record.nfcWrites?.first?.initialTarget == place.reviewURL, "The write history preserves the destination at preparation time")
        let paused = link(target: replacement.target_url, active: false, revision: 3)
        try record.applyManagedLink(paused)
        check(record.reviewLinkActive == false && record.reviewLinkID == id, "Deactivation preserves the physical token")
        rejects { _ = try record.prepareCardWriting(link: paused) }
        let another = try record.prepareCardWriting(link: original)
        try record.finishCardWriting(another.id, confirmed: false)
        check(CardLinkRules.confirmedWrites(record).count == 1 && record.nfcWrites?.last?.status == .cancelled, "A failed/cancelled write is retained without being counted as written")
        let decoded = try JSONDecoder().decode(VisitRecord.self, from: JSONEncoder().encode(record))
        check(decoded.nfcWrites == record.nfcWrites && decoded.reviewLinkID == id, "Writing history survives the shared account backup format")
        var old = try JSONSerialization.jsonObject(with: JSONEncoder().encode(record)) as! [String: Any]
        old.removeValue(forKey: "nfcWrites")
        check(try JSONDecoder().decode(VisitRecord.self, from: JSONSerialization.data(withJSONObject: old)).nfcWrites == nil,
              "Older saved businesses decode without invented writing history")
        rejects { try original.validate(owner: UUID().uuidString, expected: id) }
        rejects { try original.validate(owner: owner, expected: UUID()) }
        rejects { try link(revision: Int64.max).validate(owner: owner, expected: id) }
        for target in ["http://example.org", "javascript:alert(1)", "https://user:pass@example.org", "https://example.org:444/a", "https://example.org/a b", ReviewLinkAddress.permanent(id)] {
            check(!CardLinkRules.validTarget(target, linkID: id), "Unsafe destination or managed-link redirect loop rejected")
        }
        check(CardLinkRules.validTarget("https://example.org/path?a=1&b=2#review", linkID: id), "Valid custom HTTPS destinations remain supported")
        check(!ClientDirectoryFilter.customers.matches(record, income: 0, cards: 0), "A prepared NFC or manually changed status does not invent a paying client")
        record.status = .pending
        check(ClientDirectoryFilter.customers.matches(record, income: 1500, cards: 1), "A customer remains a customer when a return visit is pending")
        check(CardLinkRules.visits(record).isEmpty, "Saving a business or writing a tag does not invent a visit")
        let now = Date()
        record.arrivedAt = now
        check(CardLinkRules.visits(record).count == 1, "A legacy arrival is shown as one visit")
        record.followUp = [FollowUpEvent(date: now, text: "Visita realizada", isVisit: true), FollowUpEvent(text: "Nota comercial")]
        check(CardLinkRules.visits(record).count == 1, "The arrival and its history entry are not counted twice")
        record.followUp?.append(FollowUpEvent(date: now.addingTimeInterval(-86400), text: "Visita anterior", isVisit: true))
        check(CardLinkRules.visits(record).count == 2 && ClientDirectoryFilter.visits.matches(record, income: 0, cards: 0), "The customer history includes multiple real visits")
        let daily = [CardOpeningDay(day: "2026-10-26", opens: 3)]
        let stats = CardStatistics(link_id: id, total: 9, last_7_days: 3, last_30_days: 3,
                                   last_opened_at: "2026-10-26T12:00:00Z", first_recorded_day: "2026-10-01", daily: daily)
        try stats.validate(linkID: id)
        check(stats.total == 9 && stats.daily.first?.date != nil, "Real server counts and UTC dates are accepted")
        rejects { try stats.validate(linkID: UUID()) }
        rejects { try CardStatistics(link_id: id, total: 1, last_7_days: 2, last_30_days: 1, last_opened_at: nil, first_recorded_day: nil, daily: []).validate(linkID: id) }
        rejects { try CardStatistics(link_id: id, total: 9, last_7_days: 0, last_30_days: 0, last_opened_at: nil, first_recorded_day: nil, daily: [CardOpeningDay(day: "2026-02-31", opens: 0)]).validate(linkID: id) }
        rejects { try CardStatistics(link_id: id, total: Int64.max, last_7_days: 0, last_30_days: 0, last_opened_at: nil, first_recorded_day: nil,
                                     daily: [CardOpeningDay(day: "2026-10-25", opens: Int64.max), CardOpeningDay(day: "2026-10-26", opens: Int64.max)]).validate(linkID: id) }
        print("Managed card links, clients, visits and writing history: \(checks) checks passed")
    }
}
