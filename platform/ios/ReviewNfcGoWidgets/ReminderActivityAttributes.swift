import Foundation
import ActivityKit

@available(iOS 16.1, *)
struct ReminderActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var visitDate: Date
    }

    var recordID: String
    var placeName: String
    var address: String
    var historyAccount: String? = nil
}
