import SwiftUI
import UIKit
import UserNotifications

@MainActor
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        NotificationManager.registerCategories()
        return true
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        Task { @MainActor in
            let current = ReminderCoordinator.received(notification.request)
            completionHandler(current ? [.banner, .sound, .list] : [])
        }
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        Task { @MainActor in
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

@main
struct ReviewNfcGoApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var auth = AuthStore()
    @StateObject private var store = AppStore()
    @StateObject private var portalRouter = PortalRouter.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(auth)
                .environmentObject(store)
                .environmentObject(portalRouter)
                .tint(AppTheme.blue)
                .onOpenURL { portalRouter.open(url: $0) }
                .onAppear {
                    store.switchUser(auth.currentUser?.email)
                }
                .onChange(of: auth.currentUser?.email) { email in
                    store.switchUser(email)
                }
                .onChange(of: scenePhase) { phase in
                    if phase == .active {
                        ReminderCoordinator.refresh()
                    } else {
                        ReminderCoordinator.suspendTimer()
                    }
                }
        }
    }
}
