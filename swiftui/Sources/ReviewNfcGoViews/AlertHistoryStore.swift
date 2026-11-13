import SwiftUI
import UserNotifications
import ActivityKit

@MainActor
final class AlertHistoryStore: ObservableObject {
    static let shared = AlertHistoryStore()
    static let accountKey = "resenago.historyAccount"
    static let entryKey = "resenago.historyEntry"
    @Published private(set) var ledger = AlertHistoryLedger()
    private(set) var scope: String?
    private var recordIDs = Set<UUID>()
    private var activityObservers: [String: Task<Void, Never>] = [:]
    private var pendingActivityOpens = Set<UUID>()
    private var pendingObservations: [(UNNotificationRequest, Date?, Bool)] = []
    private var refreshTask: Task<Void, Never>?

    private func storageKey(_ scope: String) -> String { "resenago.alertHistory.\(scope)" }
    private func load(_ scope: String) -> AlertHistoryLedger {
        guard let data = UserDefaults.standard.data(forKey: storageKey(scope)),
              let value = try? JSONDecoder().decode(AlertHistoryLedger.self, from: data) else { return AlertHistoryLedger() }
        return value
    }

    func switchUser(_ email: String?, records: [VisitRecord]) {
        let next = email ?? "guest"
        if let previous = scope, previous != next {
            mutate(scope: previous) { ledger in
                let ids = Set(ledger.entries.filter { $0.kind == .reminder || $0.kind == .activityAlert || $0.kind == .stock }.map(\.systemID))
                ledger.cancelNotifications(systemIDs: ids, at: Date())
            }
        }
        scope = next
        ledger = load(next)
        recordIDs = Set(records.map(\.id))
        let observations = pendingObservations
        pendingObservations.removeAll()
        for (request, date, opened) in observations { observe(request, deliveredAt: date, opened: opened) }
        refresh()
    }

    func updateRecords(_ records: [VisitRecord]) { recordIDs = Set(records.map(\.id)) }

    private func mutate(scope: String, _ change: (inout AlertHistoryLedger) -> Void) {
        var value = self.scope == scope ? ledger : load(scope)
        let previous = value
        change(&value)
        guard value != previous else { return }
        if let data = try? JSONEncoder().encode(value) {
            UserDefaults.standard.set(data, forKey: storageKey(scope))
        }
        if self.scope == scope { ledger = value }
    }

    @discardableResult
    func register(scope: String, systemID: String, fingerprint: String, kind: AlertHistoryKind,
                  recordID: UUID?, businessName: String?, title: String, body: String,
                  scheduledDate: Date, status: AlertHistoryStatus = .scheduled, at date: Date = Date(), startsNewPlan: Bool = false) -> UUID {
        var id = UUID()
        mutate(scope: scope) { ledger in
            id = ledger.register(systemID: systemID, fingerprint: fingerprint, kind: kind,
                recordID: recordID, businessName: businessName, title: title, body: body,
                scheduledDate: scheduledDate, at: date, initialStatus: status, startsNewPlan: startsNewPlan)
        }
        return id
    }

    func transition(scope: String, id: UUID, to status: AlertHistoryStatus, at date: Date = Date()) {
        mutate(scope: scope) { $0.transition(id: id, to: status, at: date) }
    }

    func cancelNotifications(scope: String, ids: [String]) {
        mutate(scope: scope) { $0.cancelNotifications(systemIDs: Set(ids), at: Date()) }
    }

    private func requestScope(_ request: UNNotificationRequest) -> String? {
        if let account = request.content.userInfo[Self.accountKey] as? String { return account }
        guard let scope, let recordID = PortalLink.recordID(from: request.content.userInfo),
              recordIDs.contains(recordID) || ledger.entries.contains(where: { $0.recordID == recordID && $0.systemID == request.identifier }) else { return nil }
        return scope
    }

    private func nextFireDate(_ request: UNNotificationRequest) -> Date? {
        if let trigger = request.trigger as? UNCalendarNotificationTrigger { return trigger.nextTriggerDate() }
        if let trigger = request.trigger as? UNTimeIntervalNotificationTrigger { return trigger.nextTriggerDate() }
        return nil
    }

    @discardableResult
    func observe(_ request: UNNotificationRequest, deliveredAt: Date? = nil, opened: Bool = false) -> UUID? {
        guard let owner = requestScope(request) else {
            if scope == nil && (opened || deliveredAt != nil) { pendingObservations.append((request, deliveredAt, opened)) }
            return nil
        }
        let fingerprint = request.content.userInfo[NotificationManager.fingerprintKey] as? String ?? request.identifier
        let decoded = Data(base64Encoded: fingerprint).flatMap { try? JSONDecoder().decode(VisitNotification.self, from: $0) }
        let isTest = request.identifier.hasPrefix("resenago.test")
        let kind: AlertHistoryKind = request.identifier.hasPrefix("stock.") ? .stock : isTest ? .test : (decoded?.kind == .activity ? .activityAlert : .reminder)
        let fireDate = decoded?.fireDate ?? deliveredAt ?? nextFireDate(request) ?? Date()
        let existingID = (request.content.userInfo[Self.entryKey] as? String).flatMap(UUID.init(uuidString:))
        let entryExists = existingID.map { id in (self.scope == owner ? ledger : load(owner)).entries.contains { $0.id == id } } ?? false
        let id: UUID
        if let existingID, entryExists {
            id = existingID
        } else {
            id = register(scope: owner, systemID: request.identifier, fingerprint: fingerprint, kind: kind,
                recordID: PortalLink.recordID(from: request.content.userInfo),
                businessName: request.content.userInfo["placeName"] as? String,
                title: request.content.title, body: request.content.body, scheduledDate: fireDate,
                status: deliveredAt == nil ? .scheduled : .delivered, at: deliveredAt ?? Date())
        }
        if let deliveredAt { transition(scope: owner, id: id, to: .delivered, at: deliveredAt) }
        if opened { transition(scope: owner, id: id, to: .opened) }
        return id
    }

    func refresh() {
        guard refreshTask == nil, let scope else { return }
        refreshTask = Task {
            let center = UNUserNotificationCenter.current()
            let delivered = await center.deliveredNotifications()
            let pending = await center.pendingNotificationRequests()
            guard self.scope == scope else { self.refreshTask = nil; self.refresh(); return }
            delivered.forEach { _ = observe($0.request, deliveredAt: $0.date) }
            pending.forEach { _ = observe($0) }
            mutate(scope: scope) { ledger in
                ledger.reconcileNotifications(pending: Set(pending.map(\.identifier)),
                    delivered: Set(delivered.map { $0.request.identifier }), at: Date())
            }
            if #available(iOS 16.1, *) {
                let activities = Activity<ReminderActivityAttributes>.activities
                for activity in activities { observe(activity) }
                let available = Set(activities.map(\.id))
                mutate(scope: scope) { $0.reconcileActivities(available: available, at: Date()) }
                for id in Array(activityObservers.keys) where !available.contains(id) {
                    activityObservers[id]?.cancel()
                    activityObservers[id] = nil
                }
            }
            for id in pendingActivityOpens { openActivityPortal(recordID: id) }
            self.refreshTask = nil
        }
    }

    func openActivityPortal(recordID: UUID) {
        guard let scope, let entry = ledger.entries.last(where: {
            $0.kind == .liveActivity && $0.recordID == recordID &&
                [.delivered, .opened, .unconfirmed].contains($0.status)
        }) else { pendingActivityOpens.insert(recordID); return }
        transition(scope: scope, id: entry.id, to: .opened)
        pendingActivityOpens.remove(recordID)
    }

    @available(iOS 16.1, *)
    func activityScope(_ activity: Activity<ReminderActivityAttributes>) -> String? {
        if let owner = activity.attributes.historyAccount { return owner }
        guard let scope, let id = UUID(uuidString: activity.attributes.recordID), recordIDs.contains(id) else { return nil }
        return scope
    }

    @available(iOS 16.1, *)
    func observe(_ activity: Activity<ReminderActivityAttributes>) {
        guard let owner = activityScope(activity) else { return }
        let planned = activity.contentState.visitDate.addingTimeInterval(-ScheduledVisit.leadTime)
        let initialStatus: AlertHistoryStatus
        switch activity.activityState {
        case .active, .stale: initialStatus = .delivered
        case .ended, .dismissed: initialStatus = .scheduled
        default: initialStatus = .scheduled
        }
        let id = register(scope: owner, systemID: activity.id, fingerprint: activity.id, kind: .liveActivity,
            recordID: UUID(uuidString: activity.attributes.recordID), businessName: activity.attributes.placeName,
            title: "Cuenta atrás para \(activity.attributes.placeName)", body: activity.attributes.address,
            scheduledDate: planned, status: initialStatus)
        updateActivity(activity.activityState, scope: owner, id: id)
        guard activityObservers[activity.id] == nil else { return }
        let systemID = activity.id
        activityObservers[systemID] = Task { [weak self] in
            for await state in activity.activityStateUpdates {
                guard !Task.isCancelled else { break }
                self?.updateActivity(state, scope: owner, id: id)
                if state == .ended || state == .dismissed { break }
            }
            self?.activityObservers[systemID] = nil
        }
    }

    @available(iOS 16.1, *)
    private func updateActivity(_ state: ActivityState, scope: String, id: UUID) {
        if #available(iOS 26.0, *), state == .pending { return }
        switch state {
        case .active, .stale: transition(scope: scope, id: id, to: .delivered)
        case .ended, .dismissed:
            let entry = (self.scope == scope ? ledger : load(scope)).entries.first { $0.id == id }
            let status: AlertHistoryStatus
            if entry?.status == .cancelled { status = .cancelled }
            else if entry?.status == .scheduled || entry?.status == .unconfirmed {
                status = (entry?.scheduledDate ?? .distantFuture) > Date() ? .cancelled : .unconfirmed
            } else { status = .finished }
            transition(scope: scope, id: id, to: status)
        default: break
        }
    }

    @available(iOS 16.1, *)
    func ending(_ activity: Activity<ReminderActivityAttributes>) {
        guard let owner = activityScope(activity) else { return }
        let entry = (self.scope == owner ? ledger : load(owner)).entries.last { $0.systemID == activity.id && $0.kind == .liveActivity }
        guard let entry else { return }
        let status: AlertHistoryStatus = (entry.status == .scheduled || entry.status == .unconfirmed)
            ? (entry.scheduledDate > Date() ? .cancelled : .unconfirmed) : .finished
        transition(scope: owner, id: entry.id, to: status)
    }
}
