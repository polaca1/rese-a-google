import Foundation

/// A persisted visit projected into the scheduler. No additional UI or stored setting.
struct ScheduledVisit: Codable, Equatable {
    static let leadTime: TimeInterval = 5 * 60 * 60

    let id: UUID
    let name: String
    let address: String
    let placeID: String
    let latitude: Double
    let longitude: Double
    let notes: String
    let visitDate: Date?
    let reminderDate: Date?
    let completed: Bool

    var notificationIDs: [String] {
        [id.uuidString, "resenago.activity.\(id.uuidString)"]
    }

    func isUpcoming(at now: Date) -> Bool {
        !completed && (visitDate.map { $0 > now } ?? false)
    }

    func needsActivity(at now: Date) -> Bool {
        isUpcoming(at: now) && visitDate!.timeIntervalSince(now) <= Self.leadTime
    }

    func notifications(at now: Date) -> [VisitNotification] {
        guard isUpcoming(at: now), let visitDate else { return [] }
        var result: [VisitNotification] = []
        let reminder = reminderDate ?? visitDate // Compatibility with older saved records.
        if reminder > now && reminder <= visitDate {
            result.append(VisitNotification(visit: self, kind: .reminder, fireDate: reminder))
        }
        let automatic = visitDate.addingTimeInterval(-Self.leadTime)
        if automatic > now {
            result.append(VisitNotification(visit: self, kind: .activity, fireDate: automatic))
        }
        return result
    }
}

struct VisitNotification: Codable, Equatable {
    enum Kind: String, Codable { case reminder, activity }
    let visit: ScheduledVisit
    let kind: Kind
    let fireDate: Date

    var id: String { visit.notificationIDs[kind == .reminder ? 0 : 1] }

    /// Stable across launches; used to recognise unchanged requests and stale callbacks.
    var fingerprint: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return (try? encoder.encode(self).base64EncodedString()) ?? ""
    }

    static func owns(_ id: String) -> Bool {
        UUID(uuidString: id) != nil || id.hasPrefix("resenago.activity.")
    }
}

@MainActor
protocol VisitNotificationBackend: AnyObject {
    func authorizationAllowed() async -> Bool
    func pending() async -> [String: String]
    func deliveredIDs() async -> [String]
    func remove(ids: [String])
    func add(_ notification: VisitNotification) async throws
}

/// One writer, with a revision check after every suspension point. A save/delete during
/// the permission dialog or an in-flight add can never resurrect an obsolete request.
@MainActor
final class VisitNotificationScheduler {
    private let backend: VisitNotificationBackend
    private let now: () -> Date
    private let report: (String) -> Void
    private(set) var visits: [UUID: ScheduledVisit] = [:]
    private var revision = 0
    private var worker: Task<Void, Never>?

    init(backend: VisitNotificationBackend, now: @escaping () -> Date = Date.init,
         report: @escaping (String) -> Void = { print($0) }) {
        self.backend = backend
        self.now = now
        self.report = report
    }

    func replace(_ visits: [ScheduledVisit]) {
        let next = Dictionary(uniqueKeysWithValues: visits.map { ($0.id, $0) })
        let changed = Set(self.visits.keys).union(next.keys).filter { self.visits[$0] != next[$0] }
        // This also clears delivered banners, even when permission is now denied.
        backend.remove(ids: changed.flatMap { id in
            (self.visits[id] ?? next[id])!.notificationIDs
        })
        self.visits = next
        refresh()
    }

    func refresh() {
        revision += 1
        guard worker == nil else { return }
        worker = Task { await reconcile() }
    }

    func waitUntilIdle() async { await worker?.value }

    func isCurrent(id: String, fingerprint: String) -> Bool {
        guard let visit = visits.values.first(where: { $0.notificationIDs.contains(id) }),
              !visit.completed, visit.visitDate != nil else { return false }
        // Ask for the original plan, including an alert which has just fired.
        return visit.notifications(at: .distantPast).contains {
            $0.id == id && $0.fingerprint == fingerprint &&
                ($0.kind == .reminder || visit.isUpcoming(at: now()))
        }
    }

    private func desired() -> [VisitNotification] {
        visits.values.flatMap { $0.notifications(at: now()) }.sorted {
            if $0.fireDate == $1.fireDate { return $0.id < $1.id }
            return $0.fireDate < $1.fireDate
        }
    }

    private func reconcile() async {
        while true {
            let currentRevision = revision
            let pending = await backend.pending()
            guard currentRevision == revision else { continue }
            let delivered = await backend.deliveredIDs()
            guard currentRevision == revision else { continue }
            let desiredIDs = Set(desired().map(\.id))
            let activeIDs = Set(visits.values.filter { $0.isUpcoming(at: now()) }.flatMap(\.notificationIDs))
            backend.remove(ids: Array(Set(pending.keys).subtracting(desiredIDs)
                .union(Set(delivered).subtracting(activeIDs))))

            // Await the actual permission result BEFORE adding either kind of request.
            let allowed = desiredIDs.isEmpty ? false : await backend.authorizationAllowed()
            guard currentRevision == revision else { continue }
            if allowed {
                // Recompute after the permission dialog: it might have crossed T−5h.
                for notification in desired() {
                    guard currentRevision == revision else { break }
                    guard notification.fireDate > now(), pending[notification.id] != notification.fingerprint else { continue }
                    do {
                        try await backend.add(notification)
                    } catch {
                        report("No se pudo programar \(notification.id): \(error)")
                    }
                    if currentRevision != revision {
                        backend.remove(ids: [notification.id])
                        break
                    }
                }
                guard currentRevision == revision else { continue }
                let registered = await backend.pending()
                guard currentRevision == revision else { continue }
                for notification in desired() where notification.fireDate.timeIntervalSince(now()) > 1 {
                    if registered[notification.id] != notification.fingerprint {
                        report("iOS no confirmó el aviso \(notification.id). Se reintentará al activar la app.")
                    }
                }
            }
            guard currentRevision == revision else { continue }
            worker = nil
            return
        }
    }
}

struct RunningVisitActivity {
    let id: String
    let recordID: String
    let name: String
    let address: String
    let visitDate: Date
    var isPending: Bool = false

    func matches(_ visit: ScheduledVisit) -> Bool {
        recordID == visit.id.uuidString && visitDate == visit.visitDate &&
            name == visit.name && address == visit.address
    }
}

@MainActor
protocol VisitActivityBackend: AnyObject {
    var canStart: Bool { get }
    var supportsScheduling: Bool { get }
    func activities() -> [RunningVisitActivity]
    func end(id: String) async
    func start(_ visit: ScheduledVisit) throws
}

extension VisitActivityBackend {
    var supportsScheduling: Bool { false }
}

@MainActor
final class VisitActivityScheduler {
    private let backend: VisitActivityBackend
    private let now: () -> Date
    private var visits: [ScheduledVisit] = []
    private var revision = 0
    private var worker: Task<Void, Never>?

    init(backend: VisitActivityBackend, now: @escaping () -> Date = Date.init) {
        self.backend = backend
        self.now = now
    }

    func replace(_ visits: [ScheduledVisit]) {
        self.visits = visits
        refresh()
    }

    func refresh() {
        revision += 1
        guard worker == nil else { return }
        worker = Task { await reconcile() }
    }

    func waitUntilIdle() async { await worker?.value }

    private func reconcile() async {
        while true {
            let currentRevision = revision
            var retained = Set<UUID>()
            for activity in backend.activities() {
                if let visit = visits.first(where: {
                    activity.matches($0) && $0.isUpcoming(at: now()) &&
                        (activity.isPending ? backend.supportsScheduling : $0.needsActivity(at: now()))
                }),
                   retained.insert(visit.id).inserted {
                    continue
                }
                // Finish the old activity before requesting its replacement.
                await backend.end(id: activity.id)
                if currentRevision != revision { break }
            }
            guard currentRevision == revision else { continue }
            for visit in visits.sorted(by: { ($0.visitDate ?? .distantFuture) < ($1.visitDate ?? .distantFuture) }) {
                let eligible = backend.supportsScheduling ? visit.isUpcoming(at: now()) : visit.needsActivity(at: now())
                guard backend.canStart, eligible, !retained.contains(visit.id) else { continue }
                do { try backend.start(visit) }
                catch { print("No se pudo iniciar Live Activity: \(error)") }
            }
            worker = nil
            return
        }
    }
}
