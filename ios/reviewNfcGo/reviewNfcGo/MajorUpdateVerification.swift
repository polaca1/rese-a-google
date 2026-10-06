#if DEBUG
import SwiftUI
import UIKit

@MainActor
enum MajorUpdateVerification {
    static let searchPlaces = [
        PlaceResult(id: "cafe-plaza", name: "Café de la Plaza", address: "Plaza Mayor, Madrid", latitude: 40.415, longitude: -3.707),
        PlaceResult(id: "cafe-central", name: "Café Central", address: "Plaza del Ángel, Madrid", latitude: 40.414, longitude: -3.703),
        PlaceResult(id: "cafe-real", name: "Café Real", address: "Calle Mayor, Madrid", latitude: 40.416, longitude: -3.709)
    ]
    static func run(store: AppStore, photos: ProfilePhotoStore) async {
        let output = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("major-update-verification.json")
        let originalUser = store.loadedUserEmail
        let owner = "money-verification@example.invalid"
        var checks: [String] = []
        func check(_ value: Bool, _ title: String) throws {
            guard value else { throw NSError(domain: "MajorVerification", code: 1, userInfo: [NSLocalizedDescriptionKey: title]) }
            checks.append(title)
        }
        do {
            UserDefaults.standard.removeObject(forKey: "resenago.records.\(owner)")
            UserDefaults.standard.removeObject(forKey: MoneyLedger.storageKey(owner))
            store.switchUser(owner); photos.switchUser(owner); photos.remove()
            let place = searchPlaces[0]
            store.addOrUpdatePlace(place)
            var record = store.records[0]
            record.cardsSold = 3; record.unitEarnings = 20; record.earnings = 60; record.status = .completed
            try check(store.update(record) && store.money.balanceCents == 6000, "Ventas suman automáticamente al saldo")
            let count = store.money.transactions.count
            store.update(record)
            try check(store.money.transactions.count == count, "Guardar la misma venta no duplica ingresos")
            let card = InventoryProduct(name: "Tarjeta NFC", kind: .nfcCard, color: "Negro", purchaseURL: "https://example.org/cards")
            try store.addExpense(title: card.displayName, amount: 80, quantity: 20, productID: card.id, newProduct: card, date: Date(), merchant: "Proveedor", method: "Tarjeta", url: card.purchaseURL, notes: "Lote de tarjetas")
            try check(store.money.balanceCents == -2000 && store.money.stock(card.id) == 20, "Compras descuentan dinero y permiten saldo negativo")
            record.inventoryProductID = card.id; store.update(record)
            try check(store.money.stock(card.id) == 17 && store.money.balanceCents == -2000, "Asignar color descuenta tarjetas sin duplicar ingresos")
            record.cardsSold = 5; store.update(record)
            try check(store.money.incomeCents == 10000 && store.money.stock(card.id) == 15, "Editar tarjetas ajusta ingreso y existencias")
            var tooMany = record; tooMany.cardsSold = 21
            let before = store.money
            try check(!store.update(tooMany) && store.money == before, "No permite vender más tarjetas que las disponibles")
            let white = InventoryProduct(name: "Tarjeta NFC", kind: .nfcCard, color: "Blanco")
            try store.addExpense(title: white.displayName, amount: 12, quantity: 2, productID: white.id, newProduct: white, date: Date(), merchant: "Tienda", method: "Efectivo", url: "", notes: "")
            try check(store.money.stock(white.id) == 2 && store.money.stock(card.id) == 15, "Inventario separado por color")
            record.cardsSold = 2; store.update(record)
            let purchase = store.money.transactions.first { $0.kind == .expense && $0.productID == card.id }!
            try store.addExpense(title: card.displayName, amount: 70, quantity: 20, productID: card.id, newProduct: nil, date: Date(), merchant: "Proveedor", method: "Tarjeta", url: card.purchaseURL, notes: "Precio corregido", replacing: purchase.id)
            try check(store.money.expenseCents == 8200 && store.money.stock(card.id) == 18 && store.money.purchased(card.id) == 20 && store.money.isReversed(purchase.id), "Corregir gasto conserva original y no duplica unidades")
            let whitePurchase = store.money.transactions.first { $0.kind == .expense && $0.productID == white.id }!
            try store.reverseExpense(whitePurchase.id)
            try check(store.money.expenseCents == 7000 && store.money.stock(white.id) == 0, "Devolución concilia dinero e inventario")
            let persisted = store.money
            store.switchUser("another-verification@example.invalid")
            try check(store.money.transactions.isEmpty, "Datos de dinero aislados entre cuentas")
            store.switchUser(owner)
            try check(store.money == persisted, "Historial y existencias se recuperan al volver a la cuenta")
            store.delete(at: IndexSet(integer: 0))
            try check(store.money.incomeCents == 4000 && store.money.sold(card.id) == 2 && store.totalCardsSold == 2, "Eliminar negocio conserva ingresos e inventario vendido")
            let finder = PlaceFinder(); finder.prepareMapVerification()
            finder.beginNameSearch("café", saved: searchPlaces)
            try check(finder.searchResults.count == 3 && finder.selectedPlace == nil && finder.mapFocus == nil, "Búsqueda presenta coincidencias sin seleccionar una automáticamente")
            finder.chooseSearchResult(searchPlaces[1])
            try check(finder.selectedPlace == searchPlaces[1] && finder.mapFocus?.coordinate.latitude == searchPlaces[1].latitude && finder.searchResults.isEmpty, "Elegir recomendación enfoca el negocio")
            let format = UIGraphicsImageRendererFormat(); format.scale = 1
            let image = UIGraphicsImageRenderer(size: CGSize(width: 800, height: 800), format: format).image { context in
                UIColor.systemBlue.setFill(); context.fill(CGRect(x: 0, y: 0, width: 800, height: 800))
                ("PC" as NSString).draw(at: CGPoint(x: 150, y: 220), withAttributes: [.font: UIFont.boldSystemFont(ofSize: 300), .foregroundColor: UIColor.white])
            }
            try photos.save(image, for: owner)
            let reloaded = ProfilePhotoStore(); reloaded.switchUser(owner)
            try check(reloaded.image != nil && reloaded.image!.size.width == 640, "Foto elegida se normaliza y persiste")
            photos.switchUser("another-verification@example.invalid")
            try photos.save(image, for: owner)
            try check(photos.image == nil, "Carga de foto pendiente no invade otra cuenta")
            photos.switchUser(owner); photos.remove(); reloaded.switchUser(owner)
            try check(reloaded.image == nil, "Foto de perfil puede eliminarse")
            store.switchUser(originalUser); photos.switchUser(originalUser)
            // A reproducible UI fixture after functional assertions, in the simulator's own validation account.
            if store.money.products.isEmpty {
                let black = InventoryProduct(name: "Tarjetas NFC", kind: .nfcCard, color: "Negro", purchaseURL: "https://example.org/tarjetas")
                let stand = InventoryProduct(name: "Stand de sobremesa", kind: .stand, purchaseURL: "https://example.org/stands")
                try store.addExpense(title: black.displayName, amount: 80, quantity: 20, productID: black.id, newProduct: black, date: Date().addingTimeInterval(-600), merchant: "Proveedor NFC", method: "Tarjeta", url: black.purchaseURL, notes: "Primer lote de tarjetas")
                try store.addExpense(title: stand.displayName, amount: 60, quantity: 3, productID: stand.id, newProduct: stand, date: Date().addingTimeInterval(-300), merchant: "Tienda de soportes", method: "Transferencia", url: stand.purchaseURL, notes: "Stands para los negocios")
                try store.addExpense(title: "Envío de material", amount: 15, quantity: 1, productID: nil, newProduct: nil, date: Date(), merchant: "Mensajería", method: "Tarjeta", url: "", notes: "Entrega de tarjetas")
                if var displayRecord = store.records.first { displayRecord.inventoryProductID = black.id; store.update(displayRecord) }
            }
            if let originalUser { try photos.save(image, for: originalUser) }
            try check(WidgetSharedStore.load().moneyBalance == Double(store.money.balanceCents) / 100 && WidgetSharedStore.load().moneyOperations?.contains(where: { $0.amount < 0 }) == true, "Widget recibe saldo y gastos reales")
            let entry = DashboardEntry(date: Date(), snapshot: WidgetSharedStore.load())
            let folder = output.deletingLastPathComponent()
            for scheme in [ColorScheme.light, .dark] {
                let renderer = ImageRenderer(content: EarningsSummaryWidgetView(entry: entry, familyOverride: .systemMedium)
                    .padding(14).frame(width: 360, height: 170).background(scheme == .dark ? Color.black : Color.white).environment(\.colorScheme, scheme))
                renderer.scale = 2
                guard let png = renderer.uiImage?.pngData() else { throw ProfilePhotoStore.PhotoError.invalid }
                try png.write(to: folder.appendingPathComponent(scheme == .dark ? "widget-money-real-dark.png" : "widget-money-real-light.png"))
            }
            try JSONSerialization.data(withJSONObject: ["passed": true, "checks": checks, "balanceCents": store.money.balanceCents], options: .prettyPrinted).write(to: output)
        } catch {
            store.switchUser(originalUser); photos.switchUser(originalUser)
            try? JSONSerialization.data(withJSONObject: ["passed": false, "checks": checks, "error": error.localizedDescription], options: .prettyPrinted).write(to: output)
        }
    }
}
#endif
