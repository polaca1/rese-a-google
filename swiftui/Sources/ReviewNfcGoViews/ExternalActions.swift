import SwiftUI
import MapKit
import CoreLocation
import UserNotifications
import UIKit
import ActivityKit

// MARK: - NFC handoff (sin entitlement Core NFC)

enum ExternalNFCWriter {
    private static let appStoreURL = URL(string: "https://apps.apple.com/es/app/simply-nfc-tag-writer-reader/id1262550712")!

    /// Simply NFC expone simplynfc://writer. Se conserva la dirección completa
    /// en el portapapeles por si el escritor necesita que se pegue manualmente.
    static func write(reviewURL: String, completion: @escaping (Bool) -> Void = { _ in }) {
        guard let writerURL = NFCWriterLink.handoff(for: reviewURL) else { completion(false); return }
        UIPasteboard.general.string = reviewURL
        UIApplication.shared.open(writerURL, options: [:]) { success in
            Task { @MainActor in
                completion(success)
                if !success { UIApplication.shared.open(appStoreURL) }
            }
        }
    }
}


// MARK: - Directions

enum MapLauncher {
    static func openAppleMaps(place: PlaceResult) {
        var components = URLComponents(string: "https://maps.apple.com/")!
        components.queryItems = [
            URLQueryItem(name: "daddr", value: "\(place.latitude),\(place.longitude)"),
            URLQueryItem(name: "q", value: place.name),
            URLQueryItem(name: "dirflg", value: "d")
        ]
        if let url = components.url { UIApplication.shared.open(url) }
    }

    static func openGoogleMaps(place: PlaceResult) {
        var components = URLComponents(string: "https://www.google.com/maps/dir/")!
        components.queryItems = [
            URLQueryItem(name: "api", value: "1"),
            URLQueryItem(name: "destination", value: "\(place.latitude),\(place.longitude)"),
            URLQueryItem(name: "destination_place_id", value: place.id),
            URLQueryItem(name: "travelmode", value: "driving")
        ]
        if let url = components.url { UIApplication.shared.open(url) }
    }

    static func openAppleMaps(latitude: Double, longitude: Double, name: String?) {
        let place = PlaceResult(id: "", name: name ?? "Destino", address: "", latitude: latitude, longitude: longitude)
        openAppleMaps(place: place)
    }

    static func openGoogleMaps(latitude: Double, longitude: Double, name: String?, placeID: String?) {
        var components = URLComponents(string: "https://www.google.com/maps/dir/")!
        var items = [
            URLQueryItem(name: "api", value: "1"),
            URLQueryItem(name: "destination", value: "\(latitude),\(longitude)"),
            URLQueryItem(name: "travelmode", value: "driving")
        ]
        if let placeID, !placeID.isEmpty { items.append(URLQueryItem(name: "destination_place_id", value: placeID)) }
        components.queryItems = items
        if let url = components.url { UIApplication.shared.open(url) }
    }
}

// La vuelta del escritor no demuestra una escritura física ni crea una venta.
@MainActor final class NFCSaleFollowUp: ObservableObject {
    static let shared = NFCSaleFollowUp()
    struct Prompt: Identifiable { let id: UUID; let recordID: UUID }
    @Published var prompt: Prompt?
    @Published private(set) var saleSaved = false
    private var handoff: NFCSaleHandoff?
    private let key = "resenago.nfc.pending-sale-question"
    init() {
        handoff = UserDefaults.standard.data(forKey: key).flatMap { try? JSONDecoder().decode(NFCSaleHandoff.self, from: $0) }
    }
    func begin(recordID: UUID, store: AppStore) {
        guard let owner = store.loadedUserEmail, let record = store.records.first(where: { $0.id == recordID }) else { return }
        handoff = NFCSaleHandoff(owner: owner, recordID: recordID); prompt = nil; saleSaved = false; persist()
        let id = handoff!.id
        ExternalNFCWriter.write(reviewURL: record.place.reviewURL) { [weak self] success in
            guard let self, self.handoff?.id == id else { return }
            if success {
                self.handoff?.launched = true; self.persist()
                if UIApplication.shared.applicationState == .active { self.sceneChanged(.active, store: store) }
            }
            else { self.finish() }
        }
    }
    func sceneChanged(_ phase: ScenePhase, store: AppStore) {
        guard let handoff else { return }
        guard handoff.owner == store.loadedUserEmail, store.records.contains(where: { $0.id == handoff.recordID }) else { finish(); return }
        if phase == .active {
            if handoff.shouldPrompt(owner: store.loadedUserEmail, recordIDs: Set(store.records.map(\.id))) {
                prompt = Prompt(id: handoff.id, recordID: handoff.recordID)
            }
        } else { self.handoff?.leftApp = true; persist() }
    }
    func markSaleSaved() { handoff = nil; saleSaved = true; UserDefaults.standard.removeObject(forKey: key) }
    func finish() { handoff = nil; prompt = nil; saleSaved = false; UserDefaults.standard.removeObject(forKey: key) }
    private func persist() {
        if let handoff, let data = try? JSONEncoder().encode(handoff) { UserDefaults.standard.set(data, forKey: key) }
    }
    #if DEBUG
    func prepareVerification(recordID: UUID, owner: String) {
        handoff = NFCSaleHandoff(owner: owner, recordID: recordID, launched: true, leftApp: true)
        prompt = Prompt(id: handoff!.id, recordID: recordID)
    }
    #endif
}
struct NFCSaleQuestionView: View {
    let recordID: UUID
    @EnvironmentObject private var store: AppStore
    @ObservedObject private var flow = NFCSaleFollowUp.shared
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Image(systemName: "creditcard.and.123").font(.system(size: 44)).foregroundStyle(.blue)
            Text("¿Has hecho una venta?").font(.title.bold())
            Text(store.records.first(where: { $0.id == recordID })?.place.name ?? "Negocio").font(.headline).foregroundStyle(.secondary)
            Text("Registra las tarjetas, stands u otros productos que has entregado y el precio cobrado.").foregroundStyle(.secondary)
            NavigationLink {
                QuickSaleView(initialBusinessID: recordID, onSaved: { flow.finish() }, didSave: { flow.markSaleSaved() })
            } label: { Text("Sí, registrar venta").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 8) }.buttonStyle(.borderedProminent).disabled(flow.saleSaved)
            if flow.saleSaved { Label("Venta guardada", systemImage: "checkmark.circle.fill").foregroundStyle(.green) }
            Button(flow.saleSaved ? "Listo" : "No he vendido") { flow.finish() }.buttonStyle(.bordered).frame(maxWidth: .infinity)
            Text("Volver de Simply NFC no confirma que la etiqueta se haya grabado. Solo se registra una venta cuando la guardas.").font(.caption).foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }.padding(24).navigationTitle("Después de escribir NFC")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cerrar") { flow.finish() } } }
    }
}
