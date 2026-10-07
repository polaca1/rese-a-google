import Foundation
import WidgetKit

enum WatchSharedStore {
    static let group = "group.com.pablo.resenagoogle.20261004.watch"
    static var url: URL? { FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group)?.appendingPathComponent("watch-snapshot.json") }
    static func load() -> WatchSnapshot {
        guard let url, let data = try? Data(contentsOf: url), let value = try? JSONDecoder().decode(WatchSnapshot.self, from: data), value.schema == 1 else { return .empty }
        return value
    }
    static func save(_ snapshot: WatchSnapshot) {
        guard let url, let data = try? JSONEncoder().encode(snapshot) else { return }
        try? data.write(to: url, options: .atomic)
        WidgetCenter.shared.reloadAllTimelines()
    }
}
