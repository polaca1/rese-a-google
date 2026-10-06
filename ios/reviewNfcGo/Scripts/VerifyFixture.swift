import Foundation

@main
struct VerifyFixture {
    static func main() throws {
        let data = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
        let preferences = try PropertyListSerialization.propertyList(from: data, format: nil) as! [String: Any]
        let decoder = JSONDecoder()
        let records = try decoder.decode([VisitRecord].self, from: preferences["resenago.records.validation@example.invalid"] as! Data)
        let history = try decoder.decode(AlertHistoryLedger.self, from: preferences["resenago.alertHistory.validation@example.invalid"] as! Data)
        precondition(records.count == 1 && records[0].id.uuidString == CommandLine.arguments[2])
        precondition(records[0].status == .completed && records[0].cardsSold == 2 && records[0].earnings == 100)
        precondition(history.entries.count == 2 && history.entries.allSatisfy { $0.recordID == records[0].id })
        print("Datos de simulador decodificados por los modelos de la app: 1 negocio, 2 tarjetas, 100 € y 2 registros de historial")
    }
}
