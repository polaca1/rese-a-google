import Foundation
import WidgetKit

// SideStore rewrites the group when signing, but newer versions no longer add
// ALTAppGroups to Info.plist. Read the installed profile in each process instead.
// This only discovers identifiers: containerURL still enforces the sandbox.
enum WidgetAppGroupConfiguration {
    static let baseGroup = "group.com.pablo.resenagoogle.20261004.widgets"
    static func identifiers(metadata: [String: Any], profileData: Data?) -> [String] {
        let profile = profileData.flatMap(profileDictionary)
        let entitlements = profile?["Entitlements"] as? [String: Any]
        let provisioned = entitlements?["com.apple.security.application-groups"] as? [String] ?? []
        let legacy = metadata["ALTAppGroups"] as? [String] ?? []
        var seen = Set<String>()
        return (provisioned + legacy + [baseGroup]).filter {
            ($0 == baseGroup || $0.hasPrefix(baseGroup + ".")) && seen.insert($0).inserted
        }
    }
    private static func profileDictionary(_ data: Data) -> [String: Any]? {
        guard !data.isEmpty, data.count <= 2_000_000 else { return nil }
        if let raw = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] { return raw }
        // A mobileprovision is CMS with an XML plist payload, not a UTF-8 file.
        guard let start = data.range(of: Data("<plist".utf8)),
              let end = data.range(of: Data("</plist>".utf8), in: start.lowerBound..<data.endIndex) else { return nil }
        return try? PropertyListSerialization.propertyList(from: Data(data[start.lowerBound..<end.upperBound]), format: nil) as? [String: Any]
    }
    static func container(identifiers: [String], lookup: (String) -> URL?) -> URL? {
        for group in identifiers {
            if let url = lookup(group) { return url }
        }
        return nil
    }
}

enum WidgetSharedStore {
    static let baseGroup = WidgetAppGroupConfiguration.baseGroup
    static let groupIdentifiers: [String] = {
        let profile = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision")
            .flatMap { try? Data(contentsOf: $0, options: .mappedIfSafe) }
        return WidgetAppGroupConfiguration.identifiers(metadata: Bundle.main.infoDictionary ?? [:], profileData: profile)
    }()
    static var container: URL? {
        WidgetAppGroupConfiguration.container(identifiers: groupIdentifiers) {
            FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: $0)
        }
    }
    static func load() -> WidgetSnapshot {
        load(from: container)
    }
    static func load(from folder: URL?) -> WidgetSnapshot {
        guard let url = folder?.appendingPathComponent("widget-snapshot.json"),
              let data = try? Data(contentsOf: url), let snapshot = try? JSONDecoder().decode(WidgetSnapshot.self, from: data) else { return .unavailable }
        return snapshot
    }
    @discardableResult
    static func publish(_ snapshot: WidgetSnapshot) -> Bool {
        publish(snapshot, to: container) { WidgetCenter.shared.reloadAllTimelines() }
    }
    @discardableResult
    static func publish(_ snapshot: WidgetSnapshot, to folder: URL?, reload: () -> Void) -> Bool {
        guard let folder, let data = try? JSONEncoder().encode(snapshot) else { return false }
        do {
            let url = folder.appendingPathComponent("widget-snapshot.json")
            try data.write(to: url, options: .atomic)
            #if os(iOS)
            try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: url.path)
            #endif
            reload()
            return true
        } catch { return false }
    }
}
