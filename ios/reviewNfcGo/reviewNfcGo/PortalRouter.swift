import SwiftUI

/// Keep a cold-launch route until authentication and saved records are ready.
@MainActor
final class PortalRouter: ObservableObject {
    static let shared = PortalRouter()
    @Published private(set) var pendingRecordID: UUID?

    func open(recordID: UUID) { pendingRecordID = recordID }

    func open(url: URL) {
        guard let id = PortalLink.recordID(from: url) else { return }
        open(recordID: id)
    }

    func consume() { pendingRecordID = nil }
}
