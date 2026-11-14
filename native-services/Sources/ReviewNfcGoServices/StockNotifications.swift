import Foundation
import UserNotifications
import CryptoKit

enum StockNotifications {
    @MainActor private static var task: Task<Void, Never>?
    @MainActor static func refresh(money: MoneyLedger, owner: String?) {
        task?.cancel()
        guard let owner else {
            task = Task {
                let center = UNUserNotificationCenter.current()
                let pending = await center.pendingNotificationRequests()
                guard !Task.isCancelled else { return }
                center.removePendingNotificationRequests(withIdentifiers: pending.filter { $0.identifier.hasPrefix("stock.") }.map(\.identifier))
                let delivered = await center.deliveredNotifications()
                guard !Task.isCancelled else { return }
                center.removeDeliveredNotifications(withIdentifiers: delivered.filter { $0.request.identifier.hasPrefix("stock.") }.map { $0.request.identifier })
            }
            return
        }
        let low = Set(money.lowStockProducts.map { $0.id.uuidString })
        let key = "resenago.lowStock." + owner
        let previous = Set(UserDefaults.standard.stringArray(forKey: key) ?? [])
        let ownerToken = SHA256.hash(data: Data(owner.utf8)).map { String(format: "%02x", $0) }.joined()
        let center = UNUserNotificationCenter.current()
        for id in previous.subtracting(low) { center.removePendingNotificationRequests(withIdentifiers: ["stock." + ownerToken + "." + id]) }
        let newlyLow = money.lowStockProducts.filter { !previous.contains($0.id.uuidString) }
        task = Task {
            let pending = await center.pendingNotificationRequests()
            guard !Task.isCancelled else { return }
            center.removePendingNotificationRequests(withIdentifiers: pending.filter { $0.identifier.hasPrefix("stock.") && !$0.identifier.hasPrefix("stock." + ownerToken + ".") }.map(\.identifier))
            let settings = await center.notificationSettings()
            guard !Task.isCancelled, [.authorized, .provisional, .ephemeral].contains(settings.authorizationStatus) else { return }
            for product in newlyLow {
                guard !Task.isCancelled else { return }
                let content = UNMutableNotificationContent()
                content.title = "Quedan pocas tarjetas"
                content.body = "\(product.displayName): \(money.stock(product.id)) disponibles. Revisa tu inventario para reponerlas."
                content.sound = .default
                let identifier = "stock." + ownerToken + "." + product.id.uuidString
                let fingerprint = identifier + "." + UUID().uuidString
                let entry = AlertHistoryStore.shared.register(scope: owner, systemID: identifier, fingerprint: fingerprint, kind: .stock,
                    recordID: nil, businessName: nil, title: content.title, body: content.body, scheduledDate: Date().addingTimeInterval(1), startsNewPlan: true)
                content.userInfo = [AlertHistoryStore.accountKey: owner, AlertHistoryStore.entryKey: entry.uuidString, NotificationManager.fingerprintKey: fingerprint]
                do {
                    try await center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)))
                    if Task.isCancelled { center.removePendingNotificationRequests(withIdentifiers: [identifier]); AlertHistoryStore.shared.transition(scope: owner, id: entry, to: .cancelled); return }
                } catch { AlertHistoryStore.shared.transition(scope: owner, id: entry, to: .failed) }
            }
            guard !Task.isCancelled else { return }
            UserDefaults.standard.set(Array(low), forKey: key)
        }
    }
}

