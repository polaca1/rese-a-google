import Foundation
import WidgetKit

// AltStore rewrites App Group IDs when signing with the user's own Apple ID.
// It publishes the provisioned IDs in ALTAppGroups in BOTH bundle Info.plists.
enum WidgetSharedStore {
    static let baseGroup = "group.com.pablo.resenagoogle.20261004.widgets"
    static var groupIdentifiers: [String] {
        let provisioned = Bundle.main.object(forInfoDictionaryKey: "ALTAppGroups") as? [String] ?? []
        return provisioned.filter { $0 == baseGroup || $0.hasPrefix(baseGroup + ".") } + [baseGroup]
    }
    static var container: URL? {
        for group in groupIdentifiers {
            if let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group) { return url }
        }
        return nil
    }
    static func load() -> WidgetSnapshot {
        guard let url = container?.appendingPathComponent("widget-snapshot.json"),
              let data = try? Data(contentsOf: url), let snapshot = try? JSONDecoder().decode(WidgetSnapshot.self, from: data) else { return .empty }
        return snapshot
    }
    @discardableResult
    static func publish(_ snapshot: WidgetSnapshot) -> Bool {
        guard let folder = container, let data = try? JSONEncoder().encode(snapshot) else { return false }
        do {
            try data.write(to: folder.appendingPathComponent("widget-snapshot.json"), options: .atomic)
            WidgetCenter.shared.reloadAllTimelines()
            return true
        } catch { return false }
    }
}
