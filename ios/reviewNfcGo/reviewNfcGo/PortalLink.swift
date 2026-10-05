import Foundation

/// Shared by the app and the widget so every entry point uses the same route.
enum PortalLink {
    static func url(recordID: UUID) -> URL {
        URL(string: "reviewnfcgo://business/\(recordID.uuidString)")!
    }

    static func recordID(from url: URL) -> UUID? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme?.lowercased() == "reviewnfcgo",
              components.host?.lowercased() == "business",
              components.user == nil, components.password == nil, components.port == nil,
              components.query == nil, components.fragment == nil else { return nil }
        let segments = components.path.split(separator: "/", omittingEmptySubsequences: false)
        guard segments.count == 2, segments[0].isEmpty else { return nil }
        return UUID(uuidString: String(segments[1]))
    }

    static func recordID(from userInfo: [AnyHashable: Any]) -> UUID? {
        guard let value = userInfo["recordID"] as? String else { return nil }
        return UUID(uuidString: value)
    }
}
