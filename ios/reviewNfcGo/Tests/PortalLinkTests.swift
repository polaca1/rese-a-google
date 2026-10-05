import Foundation

@main
struct PortalLinkTests {
    static func main() {
        let id = UUID(uuidString: "E686DAE0-73ED-4A82-B1D9-A2062F2EACB4")!
        precondition(PortalLink.recordID(from: PortalLink.url(recordID: id)) == id)
        precondition(PortalLink.recordID(from: ["recordID": id.uuidString]) == id)
        precondition(PortalLink.recordID(from: ["placeID": "some-google-place"]) == nil)
        precondition(PortalLink.recordID(from: ["recordID": "invalid"]) == nil)
        precondition(PortalLink.recordID(from: ["recordID": 42]) == nil)
        let invalid = [
            "https://business/\(id)",
            "reviewnfcgo://other/\(id)",
            "reviewnfcgo://business/not-a-uuid",
            "reviewnfcgo://business/\(id)/extra",
            "reviewnfcgo://business/\(id)/",
            "reviewnfcgo://business/\(id)?account=other",
            "reviewnfcgo://business/\(id)#fragment",
            "reviewnfcgo://someone@business/\(id)",
            "reviewnfcgo://business:123/\(id)",
            "reviewnfcgo://business/"
        ]
        for value in invalid {
            precondition(PortalLink.recordID(from: URL(string: value)!) == nil, value)
        }
        print("PortalLink: \(invalid.count + 5) comprobaciones correctas")
    }
}
