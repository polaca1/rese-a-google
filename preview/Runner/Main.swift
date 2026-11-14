// SPDX-License-Identifier: MIT
import SwiftUI
import ReviewNfcGoViews

/// Installable preview of the adapted SwiftUI package, without the Day host.
@main
struct ReviewNfcGoPreviewApp: App {
    var body: some Scene {
        WindowGroup {
            ReviewNfcGoView()
                .onOpenURL { url in
                    url.absoluteString.withCString { reviewNfcGoOpenURL($0) }
                }
        }
    }
}
