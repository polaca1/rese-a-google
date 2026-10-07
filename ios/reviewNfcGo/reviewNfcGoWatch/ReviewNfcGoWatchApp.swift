import SwiftUI
import MapKit

@main struct ReviewNfcGoWatchApp: App {
    @StateObject private var store = WatchStore()
    var body: some Scene { WindowGroup { WatchRootView().environmentObject(store) } }
}
private enum WatchDestination: Hashable { case business(UUID), sale(UUID) }
struct WatchRootView: View {
    @EnvironmentObject private var store: WatchStore
    @Environment(\.scenePhase) private var phase
    @State private var path: [WatchDestination] = []
    @State private var selectedTab = 0
    @State private var didVerify = false
    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack(path: $path) {
                WatchNextVisitView()
                    .navigationDestination(for: WatchDestination.self) { destination in
                        switch destination {
                        case .business(let id): WatchBusinessView(businessID: id)
                        case .sale(let id): WatchSaleView(businessID: id)
                        }
                    }
            }.tag(0)
            NavigationStack { WatchBusinessesView() }.tag(1)
            NavigationStack { WatchDayView() }.tag(2)
        }.tabViewStyle(.verticalPage).tint(.blue)
            .onOpenURL { url in
                if url.scheme == "reviewnfcgo-watch", url.host == "business", let id = UUID(uuidString: url.lastPathComponent) {
                    selectedTab = 0; path = [.business(id)]
                }
            }
            .onChange(of: phase) { _, value in if value == .active { store.refresh() } }
            #if DEBUG
            .task {
                let args = ProcessInfo.processInfo.arguments
                guard args.contains("--verification-watch"), !didVerify else { return }
                didVerify = true
                WatchVerification.run(store: store)
                // Navigate once the NavigationStack has entered the view hierarchy.
                await Task.yield()
                if args.contains("--verification-watch-business") { path = [.business(WatchVerification.businessID)] }
                if args.contains("--verification-watch-sale") { path = [.sale(WatchVerification.businessID)] }
                if args.contains("--verification-watch-summary") { selectedTab = 2 }
            }
            #endif
    }
}

struct WatchNextVisitView: View {
    @EnvironmentObject private var store: WatchStore
    var body: some View {
        List {
            if let visit = store.snapshot.nextVisit(at: Date()) {
                Section {
                    NavigationLink { WatchBusinessView(businessID: visit.id) } label: {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(visit.name).font(.headline)
                            if let date = visit.visitDate {
                                Text(date, format: .dateTime.day().month(.abbreviated).hour().minute()).font(.caption).foregroundStyle(.secondary)
                                Text(timerInterval: min(Date(), date)...date, countsDown: true).font(.title2.bold().monospacedDigit())
                            }
                        }.padding(.vertical, 4)
                    }
                }
                Section {
                    Button("Cómo llegar", systemImage: "location") { WatchMap.open(visit) }
                }
            } else {
                Section { VStack(alignment: .leading, spacing: 8) { Image(systemName: "calendar").font(.title2); Text("Sin próximas visitas").font(.headline); Text("Programa una visita desde el iPhone.").font(.caption).foregroundStyle(.secondary) } }
            }
            Section {
                Text(store.message).font(.caption).foregroundStyle(.secondary)
                if !store.pending.isEmpty { Label("\(store.pending.count) cambios pendientes", systemImage: "arrow.triangle.2.circlepath").font(.caption) }
                Button("Sincronizar") { store.refresh() }
            }
        }.navigationTitle("Próxima visita")
    }
}
struct WatchBusinessesView: View {
    @EnvironmentObject private var store: WatchStore
    var body: some View {
        List {
            if store.snapshot.businesses.isEmpty { Text("Guarda negocios en el iPhone para verlos aquí.").foregroundStyle(.secondary) }
            ForEach(store.snapshot.businesses) { business in
                NavigationLink { WatchBusinessView(businessID: business.id) } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(business.name).font(.headline)
                        if store.isPending(business.id) { Label("Pendiente de sincronizar", systemImage: "clock").font(.caption).foregroundStyle(.secondary) }
                        else if business.completed { Text("\(business.cardsSold) tarjetas vendidas").font(.caption).foregroundStyle(.secondary) }
                        else if let date = business.visitDate { Text(date, format: .dateTime.day().month(.abbreviated).hour().minute()).font(.caption).foregroundStyle(.secondary) }
                    }
                }
            }
            Text("Los negocios más próximos se sincronizan primero.").font(.caption2).foregroundStyle(.secondary)
        }.navigationTitle("Negocios")
    }
}
struct WatchBusinessView: View {
    let businessID: UUID
    @EnvironmentObject private var store: WatchStore
    @State private var tomorrow = false
    var body: some View {
        if let business = store.snapshot.businesses.first(where: { $0.id == businessID }) {
            List {
                Section {
                    Text(business.name).font(.headline)
                    Text(business.address).font(.caption).foregroundStyle(.secondary)
                    if let date = business.visitDate { Text(date, format: .dateTime.day().month(.abbreviated).hour().minute()) }
                    if business.arrivedAt != nil { Label("Llegada registrada", systemImage: "checkmark.circle") }
                }
                Section {
                    Button("He llegado", systemImage: "checkmark.circle") { store.enqueue(.arrive, business: business) }
                    Button("Volver mañana", systemImage: "calendar.badge.plus") { tomorrow = true }
                    NavigationLink("Registrar venta") { WatchSaleView(businessID: business.id) }
                    Button("Preparar NFC en iPhone", systemImage: "iphone") { store.enqueue(.prepareNFC, business: business) }
                }.disabled(store.isPending(business.id))
                Section { Button("Cómo llegar", systemImage: "location") { WatchMap.open(business) }; Text(store.message).font(.caption).foregroundStyle(.secondary) }
            }.navigationTitle("Visita")
                .confirmationDialog("¿Volver mañana a la misma hora?", isPresented: $tomorrow, titleVisibility: .visible) {
                    Button("Programar mañana") { store.enqueue(.tomorrow, business: business) }
                }
        } else { Text("Sincroniza el iPhone para actualizar este negocio.").padding() }
    }
}
struct WatchSaleView: View {
    let businessID: UUID
    @EnvironmentObject private var store: WatchStore
    @Environment(\.dismiss) private var dismiss
    @State private var cards = 1
    @State private var unitPrice = 10.0
    @State private var productID: UUID?
    @State private var confirming = false
    var body: some View {
        if let business = store.snapshot.businesses.first(where: { $0.id == businessID }) {
            List {
                Section {
                    Text(business.name).font(.headline)
                    WatchValueControl(title: "Tarjetas nuevas", value: cards.formatted(), canDecrease: cards > 1, canIncrease: cards < 100_000,
                        decrease: { cards -= 1 }, increase: { cards += 1 })
                    WatchValueControl(title: "Por tarjeta", value: unitPrice.formatted(.currency(code: "EUR")), canDecrease: unitPrice > 0, canIncrease: unitPrice < 50,
                        decrease: { unitPrice = max(0, unitPrice - 0.5) }, increase: { unitPrice = min(50, unitPrice + 0.5) })
                    Picker("Color / producto", selection: $productID) {
                        Text("Sin asignar").tag(Optional<UUID>.none)
                        ForEach(store.snapshot.products) { product in Text("\(product.name) · \(product.stock)").tag(Optional(product.id)) }
                    }.disabled(business.productID != nil)
                    LabeledContent("Ingreso nuevo", value: (Double(cards) * unitPrice).formatted(.currency(code: "EUR")))
                }
                Section {
                    Button("Guardar venta") { confirming = true }.buttonStyle(.borderedProminent).disabled(store.isPending(business.id))
                    Text("Se suma a las ventas del negocio. El iPhone confirma el stock y el importe.").font(.caption).foregroundStyle(.secondary)
                    Text(store.message).font(.caption).foregroundStyle(.secondary)
                }
            }.navigationTitle("Vendido")
                .onAppear { productID = business.productID; unitPrice = business.unitEarnings > 0 ? business.unitEarnings : 10 }
                .confirmationDialog("Registrar \(cards) tarjetas por \((Double(cards) * unitPrice).formatted(.currency(code: "EUR")))", isPresented: $confirming, titleVisibility: .visible) {
                    Button("Confirmar venta") {
                        if store.enqueue(.sale, business: business, cards: cards, unitCents: Int64((unitPrice * 100).rounded()), productID: productID) { dismiss() }
                    }
                }
        }
    }
}
private struct WatchValueControl: View {
    let title: String
    let value: String
    let canDecrease: Bool
    let canIncrease: Bool
    let decrease: () -> Void
    let increase: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 8) {
                Button(action: decrease) { Image(systemName: "minus") }
                    .disabled(!canDecrease).accessibilityLabel("Reducir " + title)
                Text(value).font(.headline.monospacedDigit()).lineLimit(1).minimumScaleFactor(0.5).frame(maxWidth: .infinity)
                Button(action: increase) { Image(systemName: "plus") }
                    .disabled(!canIncrease).accessibilityLabel("Aumentar " + title)
            }.buttonStyle(.bordered).buttonBorderShape(.circle).controlSize(.small)
        }.padding(.vertical, 4)
    }
}
struct WatchDayView: View {
    @EnvironmentObject private var store: WatchStore
    var body: some View {
        List {
            Section("Hoy") {
                LabeledContent("Ingresos", value: (Double(store.snapshot.dayIncomeCents) / 100).formatted(.currency(code: "EUR")))
                LabeledContent("Gastos", value: (Double(store.snapshot.dayExpenseCents) / 100).formatted(.currency(code: "EUR")))
                LabeledContent("Tarjetas", value: "\(store.snapshot.dayCards)")
            }
            Section("Saldo") {
                Text(Double(store.snapshot.balanceCents) / 100, format: .currency(code: "EUR")).font(.title2.bold()).minimumScaleFactor(0.6)
                Text("Última actualización: " + store.snapshot.generatedAt.formatted(date: .abbreviated, time: .shortened)).font(.caption2).foregroundStyle(.secondary)
            }
            if !store.errors.isEmpty {
                Section("Cambios sin aplicar") {
                    ForEach(store.errors, id: \.id) { Text($0.message).font(.caption) }
                    Button("Quitar avisos") { store.clearErrors() }
                }
            }
            Button("Sincronizar") { store.refresh() }
        }.navigationTitle("Resumen")
    }
}
enum WatchMap {
    static func open(_ business: WatchBusiness) {
        let item = MKMapItem(placemark: MKPlacemark(coordinate: CLLocationCoordinate2D(latitude: business.latitude, longitude: business.longitude)))
        item.name = business.name
        item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeWalking])
    }
}
