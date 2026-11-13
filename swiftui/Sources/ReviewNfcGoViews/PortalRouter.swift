import SwiftUI

/// Keep a cold-launch route until authentication and saved records are ready.
@MainActor
final class PortalRouter: ObservableObject {
    static let shared = PortalRouter()
    @Published private(set) var pendingRecordID: UUID?

    @Published private(set) var pendingWidgetSection: WidgetSection?
    func open(recordID: UUID) { pendingWidgetSection = nil; pendingRecordID = recordID }

    func open(url: URL) {
        if let id = PortalLink.recordID(from: url) { open(recordID: id) }
        else if let section = WidgetSection.parse(url) { pendingRecordID = nil; pendingWidgetSection = section }
    }

    func consume() { pendingRecordID = nil }
    func consumeWidgetSection() { pendingWidgetSection = nil }
}
