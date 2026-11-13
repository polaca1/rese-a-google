import Foundation

@main struct WidgetDataTests {
    static func main() throws {
        let now = Date(timeIntervalSince1970: 1900000000)
        func record(_ name: String, _ lat: Double, _ lon: Double, _ hours: Double, _ status: VisitStatus = .pending) -> VisitRecord {
            VisitRecord(place: PlaceResult(id: name, name: name, address: name, latitude: lat, longitude: lon),
                createdAt: now.addingTimeInterval(hours), status: status, reminderDate: now.addingTimeInterval(hours * 3600))
        }
        let madrid = record("Madrid", 40.4168, -3.7038, 1)
        let a = record("Badajoz 1", 38.8782, -6.9721, 4), b = record("Badajoz 2", 38.8794, -6.9708, 2), c = record("Badajoz 3", 38.8775, -6.9699, 3)
        var sold = record("Venta", 38.878, -6.97, 0, .completed)
        sold.cardsSold = 3; sold.unitEarnings = 20; sold.normalizeSales()
        var noDate = record("Pendiente sin fecha", 38.878, -6.97, 0); noDate.reminderDate = nil
        let records = [madrid, a, b, c, sold, noDate]
        let snapshot = WidgetSnapshot(records: records, isSignedIn: true, now: now)
        precondition(snapshot.pending.count == 5 && snapshot.nextVisits.count == 4)
        precondition(snapshot.nextVisits.map(\.name) == ["Madrid", "Badajoz 2", "Badajoz 3", "Badajoz 1"])
        precondition(snapshot.densePlaces.count == 4 && !snapshot.densePlaces.contains(where: { $0.id == madrid.id }))
        precondition(snapshot.totalEarnings == 60 && snapshot.totalCards == 3 && snapshot.operations.count == 1)
        let decoded = try JSONDecoder().decode(WidgetSnapshot.self, from: JSONEncoder().encode(snapshot))
        precondition(decoded == snapshot)
        let loggedOut = WidgetSnapshot(records: records, isSignedIn: false, now: now)
        precondition(loggedOut.pending.isEmpty && loggedOut.operations.isEmpty && loggedOut.totalEarnings == 0)
        let secondAccount = WidgetSnapshot(records: [madrid], isSignedIn: true, now: now)
        precondition(secondAccount.pending.count == 1 && secondAccount.totalEarnings == 0)
        let invalid = record("Inválido", .nan, -6.97, 0)
        precondition(WidgetSnapshot(records: [invalid], isSignedIn: true).validMapPlaces.isEmpty)
        let wrap = WidgetSnapshot(records: [record("Este", 10, 179.999, 0), record("Oeste", 10, -179.999, 1)], isSignedIn: true)
        precondition(wrap.densePlaces.count == 2)
        for section in [WidgetSection.visits, .earnings] { precondition(WidgetSection.parse(section.url) == section) }
        for url in ["reviewnfcgo://widgets/visits?x=1", "reviewnfcgo://widgets/earnings/other", "https://widgets/visits", "reviewnfcgo://widgets/unknown"] {
            precondition(WidgetSection.parse(URL(string: url)!) == nil)
        }
        print("Widgets: filtros, fechas, zona más densa, ganancias, cuentas, persistencia y rutas correctos")
    }
}
