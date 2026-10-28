
import SwiftUI
import WatchConnectivity
import Network

@main
struct SideStoreWatchApp: App {
    @StateObject private var store = WatchStore()
    var body: some Scene {
        WindowGroup {
            NavigationStack {
                List {
                    Section {
                        Label("SideStore", systemImage: "shippingbox.fill")
                            .font(.headline).foregroundStyle(.purple)
                        Text("watchOS 10 · beta de instalación").font(.caption)
                    }
                    Section("Comprobación real") {
                        LabeledContent("iPhone", value: store.phone)
                        LabeledContent("Servicio local", value: store.localService)
                        Text(store.delivery).font(.footnote)
                    }
                    Section {
                        Text("Esta fase verifica que la app se instala, abre y puede acceder al servicio local del reloj. El motor autónomo de firma aún no está implementado.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }.navigationTitle("SideStore")
                    .task { store.start() }
            }
        }
    }
}
