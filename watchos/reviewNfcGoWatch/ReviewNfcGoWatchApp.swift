import SwiftUI

private func euros(_ cents: Int64) -> String { (Double(cents) / 100).formatted(.currency(code: "EUR").locale(Locale(identifier: "es_ES"))) }
@main struct ReviewNfcGoWatchApp: App {
    @StateObject private var store = WatchStore()
    var body: some Scene { WindowGroup { WatchRootView().environmentObject(store).tint(.blue) } }
}
struct WatchRootView: View {
    @EnvironmentObject private var store: WatchStore
    @Environment(\.scenePhase) private var phase
    @State private var tab: Int = {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        if args.contains("--verification-watch-money") { return 2 }
        if args.contains("--verification-watch-businesses") { return 1 }
        #endif
        return 0
    }()
    var body: some View {
        TabView(selection: $tab) {
            NavigationStack { WatchVisitView() }.tag(0)
            NavigationStack { WatchBusinessesView() }.tag(1)
            NavigationStack { WatchMoneyView() }.tag(2)
        }.tabViewStyle(.verticalPage)
            .onChange(of: phase) { _, value in if value == .active { store.refresh() } }
            .task {
                #if DEBUG
                if ProcessInfo.processInfo.arguments.contains("--verification-watch") {
                    store.verify()
                    return
                }
                #endif
                store.refresh()
            }
    }
}
private struct WatchFooter: View {
    @EnvironmentObject private var store: WatchStore
    var body: some View {
        Section {
            if store.snapshot.isAvailable { Text("Actualizado " + store.snapshot.generatedAt.formatted(date: .abbreviated, time: .shortened)).font(.caption2).foregroundStyle(.secondary) }
            if !store.message.isEmpty { Text(store.message).font(.caption).foregroundStyle(.secondary) }
            Button("Actualizar") { store.refresh() }
        }
    }
}
struct WatchVisitView: View {
    @EnvironmentObject private var store: WatchStore
    var body: some View {
        List {
            if let visit = store.snapshot.nextVisit {
                Section {
                    Text(visit.name).font(.headline)
                    Text(visit.address).font(.caption).foregroundStyle(.secondary)
                    if let date = visit.visitDate { Label(date.formatted(date: .abbreviated, time: .shortened), systemImage: "calendar") }
                    if let url = visit.mapsURL { Link("Cómo llegar", destination: url) }
                }
            } else { Section { Label(store.snapshot.isAvailable ? "Sin visitas pendientes" : "Conecta tu iPhone", systemImage: "calendar") } }
            WatchFooter()
        }.navigationTitle("Próxima visita")
    }
}
struct WatchBusinessesView: View {
    @EnvironmentObject private var store: WatchStore
    var body: some View {
        List {
            ForEach(store.snapshot.businesses) { business in
                NavigationLink {
                    List {
                        Text(business.name).font(.headline)
                        Text(business.address).font(.caption).foregroundStyle(.secondary)
                        if business.completed { Label("Cliente", systemImage: "checkmark.circle") }
                        LabeledContent("Ingresos", value: euros(business.incomeCents))
                        if let url = business.mapsURL { Link("Cómo llegar", destination: url) }
                    }.navigationTitle("Negocio")
                } label: {
                    VStack(alignment: .leading, spacing: 4) { Text(business.name); Text(business.completed ? "Cliente" : "Pendiente").font(.caption).foregroundStyle(.secondary) }
                }
            }
            if store.snapshot.businesses.isEmpty { Text("Tus negocios aparecerán al conectar con el iPhone.").font(.caption) }
            WatchFooter()
        }.navigationTitle("Mis sitios")
    }
}
struct WatchMoneyView: View {
    @EnvironmentObject private var store: WatchStore
    var body: some View {
        List {
            if let balance = store.snapshot.balanceCents, let day = store.snapshot.dayIncomeCents, let cards = store.snapshot.cardsSold {
                Section {
                    Label("Saldo", systemImage: "eurosign.circle.fill").foregroundStyle(.green)
                    Text(euros(balance)).font(.title2.bold()).minimumScaleFactor(0.7)
                }
                Section {
                    LabeledContent("Ingresos de hoy", value: euros(day))
                    LabeledContent("Tarjetas vendidas", value: String(cards))
                }
            } else { Text("Abre reviewNfcGo en el iPhone para recibir tu saldo.") }
            WatchFooter()
        }.navigationTitle("Dinero")
    }
}
