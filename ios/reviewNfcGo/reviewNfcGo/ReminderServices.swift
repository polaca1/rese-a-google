import Foundation
import UserNotifications
import ActivityKit
import UIKit

extension ScheduledVisit {
    init(_ record: VisitRecord) {
        self.init(id: record.id, name: record.place.name, address: record.place.address,
                  placeID: record.place.id, latitude: record.place.latitude, longitude: record.place.longitude,
                  notes: record.notes, visitDate: record.reminderDate,
                  reminderDate: record.notificationDate, completed: record.status == .completed)
    }
}

@MainActor
enum NotificationManager {
    static let categoryID = "RESENAGO_RETURN"
    static let appleMapsAction = "RESENAGO_APPLE_MAPS"
    static let googleMapsAction = "RESENAGO_GOOGLE_MAPS"
    static let fingerprintKey = "resenago.schedule"
    private static var permissionTask: Task<Bool, Never>?

    static func registerCategories() {
        let apple = UNNotificationAction(identifier: appleMapsAction, title: "Apple Maps", options: [.foreground])
        let google = UNNotificationAction(identifier: googleMapsAction, title: "Google Maps", options: [.foreground])
        let category = UNNotificationCategory(identifier: categoryID, actions: [apple, google], intentIdentifiers: [], options: [])
        UNUserNotificationCenter.current().setNotificationCategories([category])
    }

    static func requestPermission() {
        Task {
            _ = await authorizationAllowed()
            ReminderCoordinator.refresh()
        }
    }

    static func authorizationAllowed() async -> Bool {
        if let permissionTask { return await permissionTask.value }
        let task = Task { @MainActor in
            registerCategories()
            let center = UNUserNotificationCenter.current()
            let settings = await center.notificationSettings()
            switch settings.authorizationStatus {
            case .authorized, .provisional, .ephemeral: return true
            case .notDetermined:
                do { return try await center.requestAuthorization(options: [.alert, .sound, .badge]) }
                catch { print("No se pudo pedir permiso de notificaciones: \(error)"); return false }
            default: return false
            }
        }
        permissionTask = task
        let allowed = await task.value
        permissionTask = nil
        return allowed
    }

    static func scheduleTest() {
        Task {
            guard await authorizationAllowed() else { return }
            let content = UNMutableNotificationContent()
            content.title = "reviewNfcGo funciona"
            content.body = "Las notificaciones están activadas correctamente."
            content.sound = .default
            let request = UNNotificationRequest(identifier: "resenago.test", content: content,
                trigger: UNTimeIntervalNotificationTrigger(timeInterval: 5, repeats: false))
            do { try await UNUserNotificationCenter.current().add(request) }
            catch { print("No se pudo programar la notificación de prueba: \(error)") }
        }
    }
}

@MainActor
final class SystemVisitNotifications: VisitNotificationBackend {
    private let center = UNUserNotificationCenter.current()

    func authorizationAllowed() async -> Bool { await NotificationManager.authorizationAllowed() }

    func pending() async -> [String: String] {
        let requests = await center.pendingNotificationRequests()
        return Dictionary(uniqueKeysWithValues: requests.filter { VisitNotification.owns($0.identifier) }.map {
            ($0.identifier, $0.content.userInfo[NotificationManager.fingerprintKey] as? String ?? "")
        })
    }

    func deliveredIDs() async -> [String] {
        await center.deliveredNotifications().map(\.request.identifier).filter(VisitNotification.owns)
    }

    func remove(ids: [String]) {
        guard !ids.isEmpty else { return }
        center.removePendingNotificationRequests(withIdentifiers: ids)
        center.removeDeliveredNotifications(withIdentifiers: ids)
    }

    func add(_ notification: VisitNotification) async throws {
        let visit = notification.visit
        let content = UNMutableNotificationContent()
        content.title = "Volver a \(visit.name)"
        let note = visit.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        let dateText = visit.visitDate?.formatted(date: .abbreviated, time: .shortened) ?? ""
        content.body = note.isEmpty ? "Visita: \(dateText) · \(visit.address)" : "\(note) · Visita: \(dateText)"
        content.sound = .default
        content.categoryIdentifier = NotificationManager.categoryID
        content.userInfo = [
            "latitude": visit.latitude, "longitude": visit.longitude,
            "placeName": visit.name, "placeID": visit.placeID, "recordID": visit.id.uuidString,
            "kind": notification.kind.rawValue, NotificationManager.fingerprintKey: notification.fingerprint
        ]
        // Compute only after permission and immediately before submission. Never clamp
        // a past T−5h to a new time; the activity coordinator handles that case instead.
        let interval = notification.fireDate.timeIntervalSinceNow
        guard interval > 0 else { return }
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        try await center.add(UNNotificationRequest(identifier: notification.id, content: content, trigger: trigger))
    }
}

@MainActor
final class SystemVisitActivities: VisitActivityBackend {
    var supportsScheduling: Bool {
        if #available(iOS 26.0, *) { return true }
        return false
    }

    var canStart: Bool {
        guard #available(iOS 16.1, *) else { return false }
        return UIApplication.shared.applicationState == .active && ActivityAuthorizationInfo().areActivitiesEnabled
    }

    func activities() -> [RunningVisitActivity] {
        guard #available(iOS 16.1, *) else { return [] }
        return Activity<ReminderActivityAttributes>.activities
            .filter { $0.activityState != .ended && $0.activityState != .dismissed }
            .map {
                let pending: Bool
                if #available(iOS 26.0, *) {
                    pending = $0.activityState == .pending
                } else {
                    pending = false
                }
                return RunningVisitActivity(id: $0.id, recordID: $0.attributes.recordID, name: $0.attributes.placeName,
                    address: $0.attributes.address, visitDate: $0.contentState.visitDate, isPending: pending)
            }
    }

    func end(id: String) async {
        guard #available(iOS 16.1, *), let activity = Activity<ReminderActivityAttributes>.activities.first(where: { $0.id == id }) else { return }
        if #available(iOS 16.2, *) {
            await activity.end(nil, dismissalPolicy: .immediate)
        } else {
            await activity.end(dismissalPolicy: .immediate)
        }
    }

    func start(_ visit: ScheduledVisit) throws {
        guard #available(iOS 16.1, *), canStart, let date = visit.visitDate, visit.isUpcoming(at: Date()) else { return }
        let attributes = ReminderActivityAttributes(recordID: visit.id.uuidString, placeName: visit.name, address: visit.address)
        let state = ReminderActivityAttributes.ContentState(visitDate: date)
        let start = date.addingTimeInterval(-ScheduledVisit.leadTime)
        if #available(iOS 26.0, *), start > Date() {
            // iOS owns this pending activity and starts it even when our process isn't running.
            let alert = AlertConfiguration(title: "Próxima visita",
                body: "Faltan 5 horas para visitar \(visit.name)", sound: .default)
            _ = try Activity<ReminderActivityAttributes>.request(attributes: attributes,
                content: ActivityContent(state: state, staleDate: date), pushType: nil,
                style: .standard, alertConfiguration: alert, start: start)
        } else if #available(iOS 16.2, *), visit.needsActivity(at: Date()) {
            _ = try Activity<ReminderActivityAttributes>.request(attributes: attributes,
                content: ActivityContent(state: state, staleDate: date), pushType: nil)
        } else if visit.needsActivity(at: Date()) {
            _ = try Activity<ReminderActivityAttributes>.request(attributes: attributes, contentState: state, pushType: nil)
        }
    }
}

/// The saved records are the source of truth; notification payloads never create visits.
/// iOS 26 schedules the activity with ActivityKit itself; earlier systems use foreground starts.
@MainActor
enum ReminderCoordinator {
    private static let notifications = VisitNotificationScheduler(backend: SystemVisitNotifications())
    private static let activities = VisitActivityScheduler(backend: SystemVisitActivities())
    private static var visits: [ScheduledVisit] = []
    private static var hasLoadedRecords = false
    private static var boundaryTimer: Timer?

    static func replaceRecords(_ records: [VisitRecord]) {
        hasLoadedRecords = true
        visits = records.map(ScheduledVisit.init)
        notifications.replace(visits)
        activities.replace(visits) // Independent of the notification permission dialog.
        armBoundaryTimer()
    }

    static func refresh() {
        // Scene/delegate callbacks can precede the first persisted-record load.
        guard hasLoadedRecords else { return }
        notifications.refresh()
        activities.refresh()
        armBoundaryTimer()
    }

    static func suspendTimer() {
        boundaryTimer?.invalidate()
        boundaryTimer = nil
    }

    static func received(_ request: UNNotificationRequest) -> Bool {
        refresh()
        guard hasLoadedRecords else { return true }
        guard VisitNotification.owns(request.identifier) else { return true } // Test notification.
        return notifications.isCurrent(id: request.identifier,
            fingerprint: request.content.userInfo[NotificationManager.fingerprintKey] as? String ?? "")
    }

    private static func armBoundaryTimer() {
        suspendTimer()
        guard UIApplication.shared.applicationState == .active else { return }
        let now = Date()
        let boundaries = visits.filter { $0.isUpcoming(at: now) }.flatMap { visit -> [Date] in
            guard let date = visit.visitDate else { return [] }
            return [date.addingTimeInterval(-ScheduledVisit.leadTime), date].filter { $0 > now }
        }
        guard let next = boundaries.min() else { return }
        let timer = Timer(fire: next, interval: 0, repeats: false) { _ in
            Task { @MainActor in refresh() }
        }
        boundaryTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }
}
