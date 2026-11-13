// SPDX-License-Identifier: MIT
import SwiftUI
import UIKit
import UserNotifications

extension Notification.Name {
    static let reviewNfcGoOpenURL = Notification.Name("org.appfair.app.ReviewNfcGo.openURL")
}

/// Day owns UIApplicationDelegate. Keep the existing notification delegate alive separately.
@MainActor
enum ReviewNfcGoLifecycle {
    private static let delegate = AppDelegate()
    private static var started = false

    static func start() {
        guard !started else { return }
        started = true
        _ = delegate.application(UIApplication.shared, didFinishLaunchingWithOptions: nil)
    }
}

/// Day delivers cold and warm links after mounting, on its UI thread.
/// Do not pass tokens to logging, preferences, or the website.
@_cdecl("reviewnfcgo_open_url")
public func reviewNfcGoOpenURL(_ value: UnsafePointer<CChar>?) {
    guard let value, let url = URL(string: String(cString: value)),
          url.scheme?.lowercased() == "reviewnfcgo" else { return }
    Task { @MainActor in
        NotificationCenter.default.post(name: .reviewNfcGoOpenURL, object: url)
    }
}
