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

@main
struct ReviewNfcGoApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var auth = AuthStore()
    @StateObject private var store = AppStore()
    @StateObject private var photos = ProfilePhotoStore()
    @StateObject private var portalRouter = PortalRouter.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(auth)
                .environmentObject(store)
                .environmentObject(photos)
                .environmentObject(portalRouter)
                .tint(AppTheme.blue)
                .onOpenURL { url in
                    portalRouter.open(url: url)
                    if let id = PortalLink.recordID(from: url) { AlertHistoryStore.shared.openActivityPortal(recordID: id) }
                }
                .onAppear {
                    store.switchUser(auth.currentUser?.email)
                    photos.switchUser(auth.currentUser?.email)
                    #if DEBUG
                    // Simulator verification enters the same validated route without
                    // SpringBoard's external-URL consent dialog. Absent from the IPA.
                    let arguments = ProcessInfo.processInfo.arguments
                    if arguments.contains("--verification-money") { Task { await MajorUpdateVerification.run(store: store, photos: photos) } }
                    if let index = arguments.firstIndex(of: "--verification-portal"),
                       arguments.indices.contains(index + 1),
                       let url = URL(string: arguments[index + 1]) {
                        portalRouter.open(url: url)
                    }
                    #endif
                }
                .onChange(of: auth.currentUser?.email) { email in
                    store.switchUser(email)
                    photos.switchUser(email)
                }
                .onChange(of: scenePhase) { phase in
                    if phase == .active {
                        ReminderCoordinator.refresh()
                        AlertHistoryStore.shared.refresh()
                    } else {
                        ReminderCoordinator.suspendTimer()
                    }
                }
        }
    }
}
