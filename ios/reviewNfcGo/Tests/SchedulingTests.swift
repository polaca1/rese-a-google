import Foundation

@MainActor
final class Gate {
    var entered = false
    private var continuation: CheckedContinuation<Void, Never>?
    func wait() async {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            entered = true
        }
    }
    func release() { continuation?.resume(); continuation = nil }
}

@MainActor
final class TestClock {
    var date = Date(timeIntervalSince1970: 1_800_000_000)
}

@MainActor
final class NotificationBackend: VisitNotificationBackend {
    var allowed = true
    var requests: [String: String] = [:]
    var delivered: [String] = []
    var added: [VisitNotification] = []
    var permissionGate: Gate?
    var addGate: Gate?
    var failNextAdd = false

    func authorizationAllowed() async -> Bool {
        if let gate = permissionGate { permissionGate = nil; await gate.wait() }
        return allowed
    }
    func pending() async -> [String: String] { requests }
    func deliveredIDs() async -> [String] { delivered }
    func remove(ids: [String]) {
        for id in ids { requests.removeValue(forKey: id) }
        delivered.removeAll { ids.contains($0) }
    }
    func add(_ notification: VisitNotification) async throws {
        if let gate = addGate { addGate = nil; await gate.wait() }
        if failNextAdd { failNextAdd = false; throw NSError(domain: "Test", code: 1) }
        requests[notification.id] = notification.fingerprint
        added.append(notification)
    }
}

@MainActor
final class ActivityBackend: VisitActivityBackend {
    var canStart = true
    var supportsScheduling = false
    var now: () -> Date = Date.init
    var running: [RunningVisitActivity] = []
    var events: [String] = []
    var endGate: Gate?
    func activities() -> [RunningVisitActivity] { running }
    func end(id: String) async {
        if let gate = endGate { endGate = nil; await gate.wait() }
        running.removeAll { $0.id == id }
        events.append("end")
    }
    func start(_ visit: ScheduledVisit) throws {
        running.append(RunningVisitActivity(id: UUID().uuidString, recordID: visit.id.uuidString,
            name: visit.name, address: visit.address, visitDate: visit.visitDate!,
            isPending: supportsScheduling && !visit.needsActivity(at: now())))
        events.append("start")
    }
}

@main
@MainActor
struct SchedulingTests {
    static var checks = 0
    nonisolated static let id = UUID(uuidString: "E686DAE0-73ED-4A82-B1D9-A2062F2EACB4")!
    static let clock = TestClock()

    static func check(_ condition: @autoclosure () -> Bool, _ message: String) {
        precondition(condition(), message)
        checks += 1
    }

    static func until(_ condition: () -> Bool) async {
        for _ in 0..<10_000 {
            if condition() { return }
            await Task.yield()
        }
        fatalError("An asynchronous test did not reach its checkpoint")
    }

    static func visit(_ remaining: TimeInterval? = 36_000, notify: TimeInterval? = 32_400,
                      completed: Bool = false, id: UUID = id) -> ScheduledVisit {
        ScheduledVisit(id: id, name: "Negocio", address: "Calle Mayor 1", placeID: "place-1",
            latitude: 38.8, longitude: -6.9, notes: "Nota", visitDate: remaining.map { clock.date.addingTimeInterval($0) },
            reminderDate: notify.map { clock.date.addingTimeInterval($0) }, completed: completed)
    }

    static func main() async {
        let future = visit()
        let plan = future.notifications(at: clock.date)
        check(plan.count == 2, "Every future visit has two alerts")
        check(plan.first { $0.kind == .activity }!.fireDate == future.visitDate!.addingTimeInterval(-18_000), "Exactly five elapsed hours")
        check(plan.first { $0.kind == .reminder }!.fireDate == future.reminderDate, "Preserve the user-selected time")
        check(Set(visit(36_000, notify: 18_000).notifications(at: clock.date).map(\.id)).count == 2, "Coincident alerts still have distinct IDs")
        for seconds in [18_000.0, 17_999.0, 1.0] {
            let near = visit(seconds, notify: seconds)
            check(near.needsActivity(at: clock.date), "Start immediately at or below five hours")
            check(near.notifications(at: clock.date).allSatisfy { $0.kind == .reminder }, "Never enqueue a past automatic alert")
        }
        check(!visit(18_001).needsActivity(at: clock.date), "Do not start before the five-hour window")
        for cancelled in [visit(nil), visit(-1), visit(0), visit(completed: true)] {
            check(cancelled.notifications(at: clock.date).isEmpty && !cancelled.needsActivity(at: clock.date), "Cancelled, sold and expired visits have no plan")
        }
        check(visit(notify: nil).notifications(at: clock.date).first { $0.kind == .reminder }!.fireDate == future.visitDate, "Migrate old records without a separate alert date")

        // Permission ordering; cancellation while the system dialog is open.
        do {
            let backend = NotificationBackend(), gate = Gate()
            backend.permissionGate = gate
            let scheduler = VisitNotificationScheduler(backend: backend, now: { clock.date })
            scheduler.replace([future])
            await until { gate.entered }
            check(backend.requests.isEmpty && backend.added.isEmpty, "Nothing is added before authorization finishes")
            scheduler.replace([])
            gate.release()
            await scheduler.waitUntilIdle()
            check(backend.requests.isEmpty && backend.added.isEmpty, "Cancellation during permission cannot resurrect alerts")
        }

        // An edit during authorization must use only the latest snapshot.
        do {
            let backend = NotificationBackend(), gate = Gate()
            backend.permissionGate = gate
            let scheduler = VisitNotificationScheduler(backend: backend, now: { clock.date })
            scheduler.replace([future])
            await until { gate.entered }
            let replacement = visit(72_000, notify: 70_000)
            scheduler.replace([replacement]); gate.release()
            await scheduler.waitUntilIdle()
            check(backend.added.count == 2 && backend.added.allSatisfy { $0.visit == replacement }, "Reprogram both alerts after authorization")
            scheduler.refresh(); await scheduler.waitUntilIdle()
            check(backend.added.count == 2, "Foreground refresh is idempotent")
        }

        // A request already inside add() may finish after deletion or another edit.
        for cancel in [true, false] {
            let backend = NotificationBackend(), gate = Gate()
            backend.addGate = gate
            let scheduler = VisitNotificationScheduler(backend: backend, now: { clock.date })
            scheduler.replace([future]); await until { gate.entered }
            let replacement = visit(54_000, notify: 50_000)
            scheduler.replace(cancel ? [] : [replacement]); gate.release()
            await scheduler.waitUntilIdle()
            let expected = cancel ? [:] : Dictionary(uniqueKeysWithValues: replacement.notifications(at: clock.date).map { ($0.id, $0.fingerprint) })
            check(backend.requests == expected, "In-flight add must not survive cancellation/reprogramming")
        }

        // T−5h passing during authorization must not be shifted into the future.
        do {
            let backend = NotificationBackend(), gate = Gate()
            backend.permissionGate = gate
            let scheduler = VisitNotificationScheduler(backend: backend, now: { clock.date })
            let nearBoundary = visit(18_001, notify: 100)
            scheduler.replace([nearBoundary]); await until { gate.entered }
            clock.date.addTimeInterval(2); gate.release()
            await scheduler.waitUntilIdle()
            check(backend.added.count == 1 && backend.added[0].kind == .reminder, "Recompute dates after permission")
            check(nearBoundary.needsActivity(at: clock.date), "Crossing boundary qualifies for immediate activity")
            clock.date.addTimeInterval(-2)
        }

        // Denied permission still removes both old alerts and their delivered banners.
        do {
            let backend = NotificationBackend()
            let scheduler = VisitNotificationScheduler(backend: backend, now: { clock.date })
            scheduler.replace([future]); await scheduler.waitUntilIdle()
            backend.delivered = future.notificationIDs; backend.allowed = false
            scheduler.replace([visit(completed: true)]); await scheduler.waitUntilIdle()
            check(backend.requests.isEmpty && backend.delivered.isEmpty, "Selling cancels all alerts even when permission is denied")
            scheduler.replace([future]); await scheduler.waitUntilIdle()
            check(backend.requests.isEmpty, "Denied permission cannot enqueue alerts")
            backend.allowed = true; scheduler.refresh(); await scheduler.waitUntilIdle()
            check(backend.requests.count == 2, "Retry after enabling permission in Settings")
            let orphan = UUID().uuidString
            backend.requests[orphan] = "2.7"; backend.delivered = [orphan]
            scheduler.refresh(); await scheduler.waitUntilIdle()
            check(backend.requests[orphan] == nil && backend.delivered.isEmpty, "Clean legacy/orphan requests on launch")
        }

        // A reminder scheduled at the visit time must still appear in the foreground.
        do {
            let backend = NotificationBackend()
            let scheduler = VisitNotificationScheduler(backend: backend, now: { clock.date })
            let soon = visit(60, notify: 60)
            scheduler.replace([soon]); await scheduler.waitUntilIdle()
            let request = soon.notifications(at: clock.date)[0]
            clock.date.addTimeInterval(60)
            check(scheduler.isCurrent(id: request.id, fingerprint: request.fingerprint), "Allow foreground delivery at visit time")
            scheduler.replace([visit(3600, notify: 3500)])
            check(!scheduler.isCurrent(id: request.id, fingerprint: request.fingerprint), "Suppress stale delivered payloads")
            await scheduler.waitUntilIdle(); clock.date.addTimeInterval(-60)
        }

        // Failed registration is reported, then retried on a later refresh.
        do {
            let backend = NotificationBackend()
            backend.failNextAdd = true
            var errors: [String] = []
            let scheduler = VisitNotificationScheduler(backend: backend, now: { clock.date }, report: { errors.append($0) })
            scheduler.replace([future]); await scheduler.waitUntilIdle()
            check(!errors.isEmpty && backend.requests.count == 1, "Do not swallow notification registration errors")
            scheduler.refresh(); await scheduler.waitUntilIdle()
            check(backend.requests.count == 2, "Repair a failed registration on foreground refresh")
        }

        // Activity transitions, duplicate cleanup, and end-before-start ordering.
        do {
            let backend = ActivityBackend()
            let scheduler = VisitActivityScheduler(backend: backend, now: { clock.date })
            scheduler.replace([visit(3600, notify: 3000)]); await scheduler.waitUntilIdle()
            check(backend.running.count == 1, "Start without waiting for notification permission")
            scheduler.refresh(); await scheduler.waitUntilIdle()
            check(backend.events == ["start"], "Do not duplicate an unchanged activity")
            scheduler.replace([visit(7200, notify: 7000)]); await scheduler.waitUntilIdle()
            check(backend.events == ["start", "end", "start"] && backend.running.count == 1, "Await old activity termination before replacement")
            scheduler.replace([future]); await scheduler.waitUntilIdle()
            check(backend.running.isEmpty, "Rescheduling beyond five hours ends the old activity")
            let nearBoundary = visit(18_001, notify: 100)
            scheduler.replace([nearBoundary]); await scheduler.waitUntilIdle()
            check(backend.running.isEmpty, "Do not start early")
            clock.date.addTimeInterval(1); scheduler.refresh(); await scheduler.waitUntilIdle()
            check(backend.running.count == 1, "Foreground boundary refresh starts exactly at five hours")
            clock.date.addTimeInterval(-1)
            scheduler.replace([visit(60, notify: 60)]); await scheduler.waitUntilIdle()
            clock.date.addTimeInterval(60); scheduler.refresh(); await scheduler.waitUntilIdle()
            check(backend.running.isEmpty, "End expired activity when executing")
            clock.date.addTimeInterval(-60)
            for removed in [[], [visit(completed: true)], [visit(nil)]] {
                scheduler.replace([visit(3600, notify: 3000)]); await scheduler.waitUntilIdle()
                scheduler.replace(removed); await scheduler.waitUntilIdle()
                check(backend.running.isEmpty, "Delete, sell and disable all end the activity")
            }
            backend.canStart = false
            scheduler.replace([visit(3600, notify: 3000)]); await scheduler.waitUntilIdle()
            check(backend.running.isEmpty, "Respect background/disabled ActivityKit")
            backend.canStart = true; scheduler.refresh(); await scheduler.waitUntilIdle()
            check(backend.running.count == 1, "Start on returning to foreground")
            let current = backend.running[0]
            backend.running.append(RunningVisitActivity(id: "duplicate", recordID: current.recordID, name: current.name, address: current.address, visitDate: current.visitDate))
            scheduler.refresh(); await scheduler.waitUntilIdle()
            check(backend.running.count == 1, "Remove duplicate activities left by older versions")
            let gate = Gate(); backend.endGate = gate
            scheduler.replace([visit(7200, notify: 7000)]); await until { gate.entered }
            scheduler.replace([]); gate.release(); await scheduler.waitUntilIdle()
            check(backend.running.isEmpty && backend.events.last == "end", "Cancellation during end cannot start an obsolete replacement")
        }
        // iOS 26 registers a pending system activity long before the five-hour boundary.
        do {
            let backend = ActivityBackend()
            backend.supportsScheduling = true
            backend.now = { clock.date }
            let scheduler = VisitActivityScheduler(backend: backend, now: { clock.date })
            let future = visit(24 * 3600, notify: 23 * 3600)
            scheduler.replace([future]); await scheduler.waitUntilIdle()
            check(backend.running.count == 1 && backend.running[0].isPending, "Schedule a future activity with iOS 26")
            scheduler.refresh(); await scheduler.waitUntilIdle()
            check(backend.events == ["start"], "Keep unchanged pending activities across refreshes")
            backend.canStart = false
            clock.date.addTimeInterval(19 * 3600)
            scheduler.refresh(); await scheduler.waitUntilIdle()
            check(backend.running.count == 1 && backend.events == ["start"], "The pending system request survives the boundary without app foreground")
            backend.running[0].isPending = false // iOS starts it independently at T-5h.
            scheduler.refresh(); await scheduler.waitUntilIdle()
            check(backend.events == ["start"], "Adopt the activity started by iOS without creating a duplicate")
            clock.date.addTimeInterval(-19 * 3600)
            backend.canStart = true
            scheduler.replace([visit(30 * 3600)]); await scheduler.waitUntilIdle()
            check(backend.events.suffix(2) == ["end", "start"] && backend.running[0].isPending, "End old activity before scheduling a new date")
            for removed in [[], [visit(completed: true)], [visit(nil)]] {
                scheduler.replace([future]); await scheduler.waitUntilIdle()
                scheduler.replace(removed); await scheduler.waitUntilIdle()
                check(backend.running.isEmpty, "Delete, sale or disabled visit cancels a pending scheduled activity")
            }
            scheduler.replace([visit(3600)]); await scheduler.waitUntilIdle()
            check(backend.running.count == 1 && !backend.running[0].isPending, "Within five hours, start immediately instead of scheduling in the past")
            scheduler.replace([visit(-1)]); await scheduler.waitUntilIdle()
            check(backend.running.isEmpty, "Do not schedule expired visits")
            let gate = Gate(); backend.endGate = gate
            scheduler.replace([future]); await scheduler.waitUntilIdle()
            scheduler.replace([visit(30 * 3600)]); await until { gate.entered }
            scheduler.replace([]); gate.release(); await scheduler.waitUntilIdle()
            check(backend.running.isEmpty, "Deletion during cancellation cannot recreate a pending activity")
        }
        print("PASS: \(checks) scheduling and concurrency checks")
    }
}
