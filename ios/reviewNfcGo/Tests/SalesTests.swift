import Foundation

@main
struct SalesTests {
    static func main() throws {
        for amount in [0.0, 25.5, 50.0, 100.0, 1000.0, 1250.75] {
            precondition(SaleAmountFormatting.parse(SaleAmountFormatting.text(for: amount)) == amount,
                "Editar una venta de varias tarjetas no puede cambiar la cantidad por los separadores")
        }
        precondition(SaleAmountFormatting.parse("1.250,75 €") == 1250.75)
        precondition(SaleAmountFormatting.parse("25.50") == 25.5)
        precondition(SaleAmountFormatting.parse("-1") == nil && SaleAmountFormatting.parse("nan") == nil)
        let place = PlaceResult(id: "test", name: "Negocio", address: "Madrid", latitude: 40, longitude: -3)
        var sale = VisitRecord(place: place, earnings: 50, cardsSold: 1, status: .completed)
        precondition(sale.maximumEarnings == 50)
        sale.normalizeSales()
        precondition(sale.earnings == 50)
        sale.earnings = 60
        sale.normalizeSales()
        precondition(sale.earnings == 50)
        sale.cardsSold = 3
        sale.earnings = 150
        sale.normalizeSales()
        precondition(sale.earnings == 150 && sale.maximumEarnings == 150)
        sale.cardsSold = 2
        sale.normalizeSales()
        precondition(sale.earnings == 100)
        sale.status = .contacted
        sale.cardsSold = 0
        sale.normalizeSales()
        precondition(sale.earnings == 0)
        sale.earnings = -10
        sale.normalizeSales()
        precondition(sale.earnings == 0)

        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        let existing = VisitRecord(place: place, earnings: 75, cardsSold: 2, notes: "Conservar", status: .pending, reminderDate: Date(timeIntervalSince1970: 1900000000), notificationDate: Date(timeIntervalSince1970: 1899990000))
        let restored = try decoder.decode(VisitRecord.self, from: encoder.encode(existing))
        precondition(restored == existing)
        var oldJSON = try JSONSerialization.jsonObject(with: encoder.encode(existing)) as! [String: Any]
        oldJSON.removeValue(forKey: "cardsSold")
        let migrated = try decoder.decode(VisitRecord.self, from: JSONSerialization.data(withJSONObject: oldJSON))
        precondition(migrated == existing, "La migración debe preservar cantidades, notas y recordatorios")
        for (amount, expectedCount) in [(0.0, 0), (25.0, 1), (50.0, 1), (50.01, 2), (150.0, 3)] {
            oldJSON["earnings"] = amount
            let decoded = try decoder.decode(VisitRecord.self, from: JSONSerialization.data(withJSONObject: oldJSON))
            precondition(decoded.cardsSold == expectedCount && decoded.earnings == amount)
        }
        oldJSON["earnings"] = 0
        oldJSON["status"] = VisitStatus.completed.rawValue
        let sold = try decoder.decode(VisitRecord.self, from: JSONSerialization.data(withJSONObject: oldJSON))
        precondition(sold.cardsSold == 1 && sold.earnings == 0)
        oldJSON["cardsSold"] = -3
        let corrected = try decoder.decode(VisitRecord.self, from: JSONSerialization.data(withJSONObject: oldJSON))
        precondition(corrected.cardsSold == 1)
        print("Ventas: límites de 0/1/varias tarjetas, reducción, persistencia y migración correctos")
    }
}
