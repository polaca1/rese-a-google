import Foundation
import Combine
import UIKit
import UserNotifications

@MainActor
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        NotificationManager.registerCategories()
        AppStore.shared.switchUser(AuthStore().currentUser?.email)
        return true
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        Task { @MainActor in
            if notification.request.identifier.hasPrefix("stock.") {
                AlertHistoryStore.shared.observe(notification.request, deliveredAt: notification.date)
                completionHandler([.banner, .sound, .list]); return
            }
            let current = ReminderCoordinator.received(notification.request)
            if current { AlertHistoryStore.shared.observe(notification.request, deliveredAt: notification.date) }
            completionHandler(current ? [.banner, .sound, .list] : [])
        }
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        Task { @MainActor in
            AlertHistoryStore.shared.observe(response.notification.request, deliveredAt: response.notification.date, opened: true)
            _ = ReminderCoordinator.received(response.notification.request)
            let info = response.notification.request.content.userInfo
            let latitude = info["latitude"] as? Double
            let longitude = info["longitude"] as? Double
            let name = info["placeName"] as? String
            let placeID = info["placeID"] as? String

            if response.actionIdentifier == UNNotificationDefaultActionIdentifier,
               let recordID = PortalLink.recordID(from: info) {
                PortalRouter.shared.open(recordID: recordID)
            }

            if let latitude, let longitude {
                if response.actionIdentifier == NotificationManager.appleMapsAction {
                    MapLauncher.openAppleMaps(latitude: latitude, longitude: longitude, name: name)
                } else if response.actionIdentifier == NotificationManager.googleMapsAction {
                    MapLauncher.openGoogleMaps(latitude: latitude, longitude: longitude, name: name, placeID: placeID)
                }
            }
            completionHandler()
        }
    }
}

