// SPDX-License-Identifier: MIT
// Native account/data/device services only. Every application screen is built by Day in Rust.
import Foundation
import Combine
import UIKit
import CoreLocation
import PhotosUI

@MainActor final class DayServices: NSObject, PHPickerViewControllerDelegate {
    static let shared = DayServices()
    let auth = AuthStore()
    let store = AppStore.shared
    let cloud = CloudBackupController()
    let photos = ProfilePhotoStore()
    let finder = PlaceFinder()
    let notifications = AppDelegate()
    var revision: UInt64 = 1
    var busy = false
    var error: String?
    var completed = ""
    var completedAction = ""
    var preparedRecord: UUID?
    var succeeded = false
    var handoff: NFCSaleHandoff?
    var salePrompt: UUID?
    var subscriptions = Set<AnyCancellable>()
    var observers: [NSObjectProtocol] = []

    override init() {
        super.init()
        _ = notifications.application(UIApplication.shared, didFinishLaunchingWithOptions: nil)
        configureAccount()
        for publisher in [auth.objectWillChange, store.objectWillChange, cloud.objectWillChange,
                          photos.objectWillChange, finder.objectWillChange, PortalRouter.shared.objectWillChange,
                          AlertHistoryStore.shared.objectWillChange] {
            publisher.receive(on: RunLoop.main).sink { [weak self] _ in self?.revision &+= 1 }.store(in: &subscriptions)
        }
        auth.$currentUser.dropFirst().receive(on: RunLoop.main).sink { [weak self] _ in self?.configureAccount() }.store(in: &subscriptions)
        for name in [UIApplication.didBecomeActiveNotification, UIApplication.willResignActiveNotification, UIApplication.didEnterBackgroundNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] notification in
                Task { @MainActor in self?.lifecycle(active: notification.name == UIApplication.didBecomeActiveNotification) }
            })
        }
        handoff = UserDefaults.standard.data(forKey: "resenago.nfc.pending-sale-question").flatMap { try? JSONDecoder().decode(NFCSaleHandoff.self, from: $0) }
        lifecycle(active: true)
        PhoneWatchCompanion.shared.start(store: store)
        Task { await auth.validateServerSession() }
    }

    func configureAccount() {
        cloud.connect(owner: nil, transport: auth.accountService, read: { try self.store.backup(photo: self.photos.backupData) }, apply: { _ in })
        store.switchUser(auth.currentUser?.email)
        photos.switchUser(auth.currentUser?.email)
        store.restorePhoto = { [weak self] data in try? self?.photos.restoreBackupData(data) }
        store.didChange = { [weak self] in self?.cloud.localChanged() }
        photos.didChange = { [weak self] in self?.cloud.localChanged() }
        cloud.connect(owner: auth.currentUser?.email, transport: auth.accountService,
            read: { try self.store.backup(photo: self.photos.backupData) }, apply: { value in
                try ProfilePhotoStore.validateBackupPhoto(value.photo)
                try self.store.restore(value, previousPhoto: self.photos.backupData)
                try self.photos.restoreBackupData(value.photo)
            })
        if auth.currentUser != nil { finder.start() }
        revision &+= 1
    }

    func lifecycle(active: Bool) {
        cloud.requestSync(immediate: true)
        if active {
            store.refreshWidgets(); ReminderCoordinator.refresh(); AlertHistoryStore.shared.refresh()
            if let handoff, handoff.shouldPrompt(owner: store.loadedUserEmail, recordIDs: Set(store.records.map(\.id))) {
                salePrompt = handoff.recordID
            }
        } else { handoff?.leftApp = true; ReminderCoordinator.suspendTimer() }
        persistHandoff()
        revision &+= 1
    }

    func persistHandoff() {
        let key = "resenago.nfc.pending-sale-question"
        if let handoff, let data = try? JSONEncoder().encode(handoff) { UserDefaults.standard.set(data, forKey: key) }
        else { UserDefaults.standard.removeObject(forKey: key) }
    }

    func encoded<T: Encodable>(_ value: T) -> Any {
        guard let data = try? JSONEncoder().encode(value), let object = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) else { return NSNull() }
        return object
    }

    func state() -> String {
        let user = auth.currentUser
        let ready = user != nil && store.hasLoadedRecords && store.loadedUserEmail == user?.email
        let defaults = Dictionary(uniqueKeysWithValues: EasySaleLine.make(money: store.money).map { ($0.productID, $0) })
        let products: [[String: Any]] = ready ? store.money.products.map {
            ["id": $0.id.uuidString, "name": $0.displayName, "kind": $0.kind.rawValue,
             "stock": store.money.stock($0.id), "minimumStock": $0.minimumStock ?? 0,
             "defaultSelected": defaults[$0.id]?.selected ?? false, "defaultPrice": defaults[$0.id]?.price ?? "0",
             "unitCostCents": store.money.averageCostCents($0.id).map { $0 as Any } ?? NSNull()]
        } : []
        let records: [[String: Any]] = ready ? store.records.map {
            ["id": $0.id.uuidString, "place": encoded($0.place), "notes": $0.notes,
             "status": $0.status.rawValue, "stage": $0.trackingStage.rawValue,
             "earnings": $0.earnings, "cardsSold": $0.cardsSold,
             "contactName": $0.contactName ?? "", "contactEmail": $0.contactEmail ?? "", "contactPhone": $0.contactPhone ?? "",
             "reminderDate": $0.reminderDate?.timeIntervalSince1970 ?? 0,
             "reminderLabel": $0.reminderDate?.formatted(date: .abbreviated, time: .shortened) ?? ""]
        } : []
        let value: [String: Any] = [
            "user": user.map { ["name": $0.name, "email": $0.email] } ?? [:],
            "ready": ready, "busy": busy || auth.isAuthenticating,
            "error": error ?? auth.errorMessage ?? "",
            "locationError": finder.errorMessage ?? "",
            "nearbyCount": finder.nearbyCount, "nearbyPosition": finder.nearbyPosition,
            "saveProblem": cloud.hasSaveProblem ? cloud.message : "", "conflict": cloud.state == .conflict,
            "completed": completed, "succeeded": succeeded, "completedAction": completedAction,
            "preparedRecord": preparedRecord?.uuidString ?? "",
            "records": records, "products": products,
            "transactions": ready ? encoded(store.money.transactions) : [],
            "balanceCents": ready ? store.money.balanceCents : 0,
            "incomeCents": ready ? store.money.incomeCents : 0,
            "expenseCents": ready ? store.money.expenseCents : 0,
            "cardsSold": ready ? store.totalCardsSold : 0,
            "undoTitle": store.undoTitle ?? "",
            "photo": ready ? photos.backupData?.base64EncodedString() ?? "" : "",
            "signOutNeedsConfirmation": cloud.shouldConfirmSignOut,
            "nfcPromptToken": salePrompt == nil ? "" : handoff?.id.uuidString ?? "",
            "alerts": ready ? encoded(AlertHistoryStore.shared.ledger.entries) : [],
            "selectedPlace": finder.selectedPlace.map { encoded($0) } ?? NSNull(),
            "choices": encoded(finder.nearbyChoices), "candidates": encoded(finder.nearbyCandidates),
            "searchResults": encoded(finder.searchResults), "searchBusy": finder.isLoading || finder.isFindingNearby,
            "locationStatus": finder.status,
            "latitude": finder.userLocation?.latitude ?? 40.4168, "longitude": finder.userLocation?.longitude ?? -3.7038,
            "salePrompt": salePrompt?.uuidString ?? "",
            "routeRecord": PortalRouter.shared.pendingRecordID?.uuidString ?? "",
            "routeSection": PortalRouter.shared.pendingWidgetSection?.rawValue ?? ""
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]),
              let text = String(data: data, encoding: .utf8) else { return "{}" }
        return text
    }

    func submit(_ data: Data) {
        guard let message = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let action = message["action"] as? String, let request = message["request"] as? String else { return }
        let values = message["values"] as? [String: String] ?? [:]
        let rows = message["rows"] as? [[String: String]] ?? []
        if action == "clearError" { error = nil; auth.errorMessage = nil; revision &+= 1; return }
        if action == "dismissKeyboard" { UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil); return }
        if action == "openURL" { if let url = values["url"].flatMap(URL.init(string:)) { PortalRouter.shared.open(url: url); revision &+= 1 }; return }
        if action == "consumeRoute" { PortalRouter.shared.consume(); PortalRouter.shared.consumeWidgetSection(); revision &+= 1; return }
        guard !busy else { return }
        busy = true; error = nil; auth.errorMessage = nil; preparedRecord = nil; revision &+= 1
        Task { @MainActor in
            defer { busy = false; completed = request; completedAction = action; revision &+= 1 }
            succeeded = false
            do {
                func value(_ key: String) -> String { values[key] ?? "" }
                func uuid(_ key: String) throws -> UUID {
                    guard let id = UUID(uuidString: value(key)) else { throw BackupError.invalid }; return id
                }
                @MainActor func record() throws -> VisitRecord {
                    let id = try uuid("record"); guard let r = store.records.first(where: { $0.id == id }) else { throw BackupError.invalid }; return r
                }
                @MainActor func selectedRecord() throws -> VisitRecord {
                    guard let place = finder.selectedPlace else { throw BackupError.invalid }
                    store.addOrUpdatePlace(place)
                    guard let result = store.records.first(where: { $0.place.id == place.id }) else { throw BackupError.invalid }
                    return result
                }
                func amount(_ key: String) throws -> Double {
                    guard let n = SaleAmountFormatting.parse(value(key)), MoneyLedger.cents(n) != nil else { throw MoneyError.invalidAmount }; return n
                }
                func date(_ key: String) throws -> Date {
                    let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX")
                    formatter.dateFormat = "yyyy-MM-dd HH:mm"; formatter.timeZone = .current
                    guard let result = formatter.date(from: value(key)) else { throw BackupError.invalid }; return result
                }
                switch action {
                case "login", "register":
                    await auth.authenticate(name: action == "register" ? value("name") : nil, email: value("email"), password: value("password"))
                    if let failure = auth.errorMessage { throw NSError(domain: "Account", code: 1, userInfo: [NSLocalizedDescriptionKey: failure]) }
                case "google":
                    await auth.authenticateWithGoogle()
                    if let failure = auth.errorMessage { throw NSError(domain: "Account", code: 1, userInfo: [NSLocalizedDescriptionKey: failure]) }
                case "openURL":
                    if let url = URL(string: value("url")) { PortalRouter.shared.open(url: url) }
                case "consumeRoute": PortalRouter.shared.consume(); PortalRouter.shared.consumeWidgetSection()
                case "dismissKeyboard": UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                default:
                    guard let owner = auth.currentUser?.email, store.hasLoadedRecords, store.loadedUserEmail == owner else { throw BackupError.wrongAccount }
                    switch action {
                    case "logout": cloud.connect(owner: nil, transport: auth.accountService, read: { try self.store.backup() }, apply: { _ in }); auth.logout()
                    case "password": try await auth.accountService.updatePassword(value("password"))
                    case "locate": finder.start(); finder.focusOnUserLocation(); await finder.useMyLocation()
                    case "search": await finder.searchByName(value("query"), saved: store.records.map(\.place))
                    case "searchAt": if let lat = Double(value("latitude")), let lon = Double(value("longitude")) { await finder.searchNearest(to: CLLocationCoordinate2D(latitude: lat, longitude: lon)) }
                    case "choose":
                        let all = finder.searchResults + finder.nearbyCandidates + finder.nearbyChoices
                        if let p = all.first(where: { $0.id == value("place") }) { finder.chooseSearchResult(p) }
                    case "savePlace": if let p = finder.selectedPlace { store.addOrUpdatePlace(p) }
                    case "copySelectedLink": UIPasteboard.general.string = try selectedRecord().place.reviewURL
                    case "prepareReminder": preparedRecord = try selectedRecord().id
                    case "editRecord":
                        var r = try record(); r.notes = value("notes"); r.contactName = value("contactName"); r.contactEmail = value("contactEmail"); r.contactPhone = value("contactPhone")
                        if let s = VisitStatus(rawValue: value("status")) { r.status = s }
                        guard store.update(r) else { throw BackupError.invalid }
                    case "deleteRecord": let r = try record(); if let i = store.records.firstIndex(where: { $0.id == r.id }) { store.delete(at: IndexSet(integer: i)) }
                    case "sale":
                        let r = try record()
                        let draft = try rows.map { item -> EasySaleLine in
                            guard let product = item["product"].flatMap(UUID.init(uuidString:)), let quantity = item["quantity"].flatMap(Int.init) else { throw MoneyError.invalidAmount }
                            return EasySaleLine(productID: product, selected: true, quantity: quantity, price: item["price"] ?? "")
                        }
                        let items = try EasySaleLine.inputs(draft, money: store.money)
                        guard items.reduce(Int64(0), { $0 + (MoneyLedger.cents($1.unitPrice) ?? 0) * Int64($1.quantity) }) > 0 else { throw EasySaleError.zeroTotal }
                        try store.registerQuickSale(recordID: r.id, items: items, payment: value("payment")); salePrompt = nil; handoff = nil; persistHandoff()
                    case "expense", "product":
                        let quantity = Int(value("quantity")) ?? 0
                        var productID = UUID(uuidString: value("product"))
                        var product: InventoryProduct?
                        if action == "product" { product = InventoryProduct(name: value("name"), kind: ProductKind(rawValue: value("kind")) ?? .nfcCard); productID = product?.id }
                        try store.addExpense(title: value("name"), amount: try amount("amount"), quantity: quantity, productID: productID, newProduct: product, date: Date(), merchant: value("merchant"), method: value("payment"), url: value("url"), notes: value("notes"))
                    case "stock": try store.adjustStock(try uuid("product"), quantity: Int(value("quantity")) ?? 0, reason: value("notes"))
                    case "reverseExpense": try store.reverseExpense(try uuid("transaction"))
                    case "reminder": let r = try record(); _ = store.saveReminder(for: r.place, visitDate: try date("visit"), notificationDate: try date("notification"), notes: value("notes"))
                    case "clearReminder": var r = try record(); r.reminderDate = nil; r.notificationDate = nil; guard store.update(r) else { throw BackupError.invalid }
                    case "tracking": try store.updateTracking(recordID: try uuid("record"), stage: ContactStage(rawValue: value("stage")) ?? .pending, note: value("notes"), visited: value("visited") == "true")
                    case "undo": store.undoLastChange()
                    case "sync": cloud.requestSync(immediate: true)
                    case "resolveCloud": await cloud.resolve(useCloud: value("remote") == "true")
                    case "directions": MapLauncher.openAppleMaps(place: try record().place)
                    case "writeNFC", "writeSelectedNFC":
                        let r = action == "writeSelectedNFC" ? try selectedRecord() : try record(); handoff = NFCSaleHandoff(owner: owner, recordID: r.id); salePrompt = nil
                        ExternalNFCWriter.write(reviewURL: r.place.reviewURL) { [weak self] launched in self?.handoff?.launched = launched; self?.persistHandoff(); self?.revision &+= 1 }
                    case "finishNFC": handoff = nil; salePrompt = nil; persistHandoff()
                    case "photo": var config = PHPickerConfiguration(); config.filter = .images; config.selectionLimit = 1
                        let picker = PHPickerViewController(configuration: config); picker.delegate = self
                        UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows).first(where: \.isKeyWindow)?.rootViewController?.present(picker, animated: true)
                    case "removePhoto": photos.remove()
                    default: throw BackupError.invalid
                    }
                }
                succeeded = true
            } catch { self.error = error.localizedDescription }
        }
    }

    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true)
        guard let provider = results.first?.itemProvider, provider.canLoadObject(ofClass: UIImage.self) else { return }
        provider.loadObject(ofClass: UIImage.self) { [weak self] image, _ in
            Task { @MainActor in
                guard let self, let image = image as? UIImage, let owner = self.auth.currentUser?.email else { return }
                do { try self.photos.save(image, for: owner) } catch { self.error = error.localizedDescription }
                self.revision &+= 1
            }
        }
    }
}

@MainActor @_cdecl("review_day_revision") public func reviewDayRevision() -> UInt64 { DayServices.shared.revision }
@MainActor @_cdecl("review_day_state") public func reviewDayState() -> UnsafeMutablePointer<CChar>? { strdup(DayServices.shared.state()) }
@_cdecl("review_day_free") public func reviewDayFree(_ pointer: UnsafeMutablePointer<CChar>?) { free(pointer) }
@MainActor @_cdecl("review_day_command") public func reviewDayCommand(_ text: UnsafePointer<CChar>?) {
    guard let text else { return }; let data = Data(String(cString: text).utf8)
    guard data.count <= 1_000_000 else { return }; DayServices.shared.submit(data)
}

@MainActor @_cdecl("review_day_sale_preview") public func reviewDaySalePreview(_ text: UnsafePointer<CChar>?) -> UnsafeMutablePointer<CChar>? {
    let service = DayServices.shared
    guard service.auth.currentUser?.email == service.store.loadedUserEmail,
          service.auth.currentUser != nil, let text,
          let rows = try? JSONSerialization.jsonObject(with: Data(String(cString: text).utf8)) as? [[String: String]] else { return nil }
    do {
        let draft = try rows.map { row -> EasySaleLine in
            guard let product = row["product"].flatMap(UUID.init(uuidString:)), let quantity = row["quantity"].flatMap(Int.init) else { throw MoneyError.invalidQuantity }
            return EasySaleLine(productID: product, selected: true, quantity: quantity, price: row["price"] ?? "")
        }
        let input = try EasySaleLine.inputs(draft, money: service.store.money)
        let total = input.reduce(Int64(0)) { $0 + (MoneyLedger.cents($1.unitPrice) ?? 0) * Int64($1.quantity) }
        var value: [String: Any] = ["total": total]
        if input.allSatisfy({ service.store.money.averageCostCents($0.productID) != nil }) {
            let cost = input.reduce(Int64(0)) { $0 + Int64(((service.store.money.averageCostCents($1.productID) ?? 0) * Double($1.quantity)).rounded()) }
            value["cost"] = cost; value["profit"] = total - cost
        }
        let data = try JSONSerialization.data(withJSONObject: value)
        return String(data: data, encoding: .utf8).flatMap { strdup($0) }
    } catch { return strdup("{}") }
}
