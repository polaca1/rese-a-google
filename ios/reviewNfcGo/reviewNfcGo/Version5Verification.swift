#if DEBUG
import SwiftUI
import UIKit

@MainActor enum Version5Verification {
    static func run(store: AppStore, photos: ProfilePhotoStore) {
        let original = store.loadedUserEmail, owner = "version5@example.invalid"
        let output = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("version5-verification.json")
        var checks: [String] = []
        func check(_ value: Bool, _ name: String) throws {
            guard value else { throw NSError(domain: "V5", code: 1, userInfo: [NSLocalizedDescriptionKey: name]) }
            checks.append(name)
        }
        do {
            for key in ["resenago.records." + owner, MoneyLedger.storageKey(owner), "resenago.undo." + owner] { UserDefaults.standard.removeObject(forKey: key) }
            store.switchUser(owner); photos.switchUser(owner)
            let place = PlaceResult(id: "v5", name: "Café de la Plaza", address: "Plaza Mayor, Madrid", latitude: 40.415, longitude: -3.707)
            let card = InventoryProduct(name: "Tarjetas NFC", kind: .nfcCard, color: "Azul")
            store.addOrUpdatePlace(place)
            try store.addExpense(title: card.displayName, amount: 30, quantity: 10, productID: card.id, newProduct: card, date: Date(), merchant: "Proveedor", method: "Tarjeta", url: "https://example.org/tarjetas", notes: "")
            var record = store.records[0]; record.cardsSold = 6; record.unitEarnings = 10; record.inventoryProductID = card.id
            record.status = .completed
            try check(store.update(record), "Venta con stock asignado")
            try check(store.money.profitCents(record.id) == 4200 && store.money.lowStockProducts.count == 1, "Beneficio y aviso de stock")
            store.undoLastChange()
            try check(store.money.balanceCents == -3000 && store.money.stock(card.id) == 10 && store.records[0].cardsSold == 0, "Deshacer venta conserva auditoría y existencias")
            store.undoLastChange()
            try check(store.money.balanceCents == 0 && store.money.stock(card.id) == 0 && store.money.transactions.count >= 4, "Deshacer compra después de una venta deshecha")
            let date = Date().addingTimeInterval(3600)
            _ = store.saveReminder(for: place, visitDate: date, notificationDate: date.addingTimeInterval(-1800), notes: "Hablar con el encargado")
            let before = try store.backup(photo: photos.backupData)
            let data = try before.encoded()
            let decoded = try BusinessBackup.decode(data, for: owner)
            try check(decoded.money == before.money && decoded.records.count == 1, "Copia completa validada")
            store.delete(at: IndexSet(integer: 0))
            try store.restore(decoded)
            try check(store.records.count == 1 && store.records[0].notes == "Hablar con el encargado", "Restauración recupera visita y notas")
            try check(try store.recoveryBackup()?.records.isEmpty == true, "Copia anterior a restauración disponible")
            let count = store.money.transactions.count
            store.switchUser(owner)
            try check(store.money.transactions.count == count, "Restaurar y reiniciar no duplica dinero")
            PhoneWatchBridge.shared.attach(store)
            let snapshot = PhoneWatchBridge.shared.snapshot()
            try check(snapshot.owner == WatchIdentity.token(owner) && snapshot.nextVisit(at: Date()) != nil, "Snapshot del iPhone contiene próxima visita")
            let business = snapshot.businesses[0]
            let action = WatchAction(owner: snapshot.owner!, sessionID: snapshot.sessionID!, businessID: business.id, revision: business.revision, kind: .arrive)
            let receipt = PhoneWatchBridge.shared.verificationReceive(action)
            try check(receipt?.accepted == true && store.records[0].arrivedAt != nil, "Acción He llegado aplicada por puente nativo")
            let arrived = store.records[0].arrivedAt
            _ = PhoneWatchBridge.shared.verificationReceive(action)
            try check(store.records[0].arrivedAt == arrived, "Reenvío de Watch no repite cambios")
            let next = PhoneWatchBridge.shared.snapshot().businesses[0]
            let tomorrow = WatchAction(owner: snapshot.owner!, sessionID: snapshot.sessionID!, businessID: next.id, revision: next.revision, kind: .tomorrow)
            try check(PhoneWatchBridge.shared.verificationReceive(tomorrow)?.accepted == true && Calendar.current.isDateInTomorrow(store.records[0].reminderDate!), "Volver mañana desde Watch")
            let image = UIGraphicsImageRenderer(size: CGSize(width: 32, height: 32)).image { context in UIColor.systemBlue.setFill(); context.fill(CGRect(x: 0, y: 0, width: 32, height: 32)) }
            try photos.save(image, for: owner)
            let photo = photos.backupData
            let photoBackup = try store.backup(photo: photo)
            try ProfilePhotoStore.validateBackupPhoto(photoBackup.photo)
            photos.remove(); try photos.restoreBackupData(photoBackup.photo)
            try check(photos.image != nil, "Foto incluida en copia y restauración")
            try JSONSerialization.data(withJSONObject: ["passed": true, "checks": checks], options: .prettyPrinted).write(to: output)
        } catch { try? JSONSerialization.data(withJSONObject: ["passed": false, "checks": checks, "error": error.localizedDescription], options: .prettyPrinted).write(to: output) }
        store.switchUser(original); photos.switchUser(original); PhoneWatchBridge.shared.attach(store)
    }
}
#endif
