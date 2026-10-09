import SwiftUI
import Charts
import CoreLocation

#if os(iOS)
typealias WorkspaceStore = AppStore
#else
typealias WorkspaceStore = MacStore
#endif
private func suiteEuro(_ cents: Int64) -> String { (Double(cents) / 100).formatted(.currency(code: "EUR")) }

struct BusinessHubView: View {
    var body: some View {
        List {
            Section("Tu actividad") {
                NavigationLink { QuickSaleView() } label: { Label("Registrar venta", systemImage: "plus.circle.fill") }
                NavigationLink { ClientFollowUpView() } label: { Label("Seguimiento de clientes", systemImage: "person.2") }
                NavigationLink { WorkspaceRouteView() } label: { Label("Ruta del día", systemImage: "map") }
            }
            Section("Resultados") {
                NavigationLink { WeeklyGoalsView() } label: { Label("Objetivos semanales", systemImage: "target") }
                NavigationLink { SaleProfitView() } label: { Label("Ventas y beneficio", systemImage: "chart.bar") }
            }
            Section("Tu cuenta") {
                NavigationLink { CloudHistoryView() } label: { Label("Recuperar versiones de la nube", systemImage: "clock.arrow.circlepath") }
            }
        }.navigationTitle("Actividad")
    }
}

struct QuickSaleView: View {
    @EnvironmentObject private var store: WorkspaceStore
    @Environment(\.dismiss) private var dismiss
    var initialBusinessID: UUID? = nil
    @State private var businessID: UUID?
    @State private var productID: UUID?
    @State private var quantity = 1
    @State private var price = "10"
    @State private var items: [QuickSaleInput] = []
    @State private var payment = "Efectivo"
    @State private var error: String?
    private var total: Int64 { items.reduce(0) { $0 + (MoneyLedger.cents($1.unitPrice) ?? 0) * Int64($1.quantity) } }
    private var cost: Int64? {
        guard items.allSatisfy({ store.money.averageCostCents($0.productID) != nil }) else { return nil }
        return items.reduce(0) { $0 + Int64(((store.money.averageCostCents($1.productID) ?? 0) * Double($1.quantity)).rounded()) }
    }
    var body: some View {
        Form {
            Section("Negocio") {
                Picker("Cliente", selection: $businessID) {
                    Text("Seleccionar negocio").tag(nil as UUID?)
                    ForEach(store.records) { Text($0.place.name).tag(Optional($0.id)) }
                }
                if store.records.isEmpty { Text("Guarda primero un negocio en Sitios.").foregroundStyle(.secondary) }
            }
            Section("Tarjetas, stands y productos") {
                Picker("Producto", selection: $productID) {
                    Text("Seleccionar producto").tag(nil as UUID?)
                    ForEach(store.money.products.filter { product in store.money.stock(product.id) > 0 && !items.contains { $0.productID == product.id } }) { product in
                        Text("\(product.displayName) · \(store.money.stock(product.id)) disponibles").tag(Optional(product.id))
                    }
                }
                Stepper("Cantidad: \(quantity)", value: $quantity, in: 1...100_000)
                TextField("Precio por unidad (€)", text: $price)
                Button("Añadir a la venta") { addItem() }.disabled(productID == nil || items.count >= 20)
                ForEach(items) { item in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(store.money.products.first { $0.id == item.productID }?.displayName ?? "Producto")
                            Text("\(item.quantity) × \(suiteEuro(MoneyLedger.cents(item.unitPrice) ?? 0))").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button(role: .destructive) { items.removeAll { $0.id == item.id } } label: { Image(systemName: "minus.circle") }.buttonStyle(.borderless).accessibilityLabel("Quitar producto")
                    }
                }
                if store.money.products.isEmpty { Text("Añade existencias en Dinero → Inventario antes de vender.").foregroundStyle(.secondary) }
            }
            Section("Cobro") {
                Picker("Forma de pago", selection: $payment) { ForEach(["Efectivo", "Tarjeta", "Bizum", "Transferencia", "Otro"], id: \.self) { Text($0) } }
                LabeledContent("Total", value: suiteEuro(total))
                if let cost { LabeledContent("Coste de productos", value: suiteEuro(cost)); LabeledContent("Beneficio", value: suiteEuro(total - cost)) }
                else { Text("Coste pendiente: faltan compras registradas.").foregroundStyle(.secondary) }
                Button("Guardar venta") {
                    guard let businessID else { return }
                    do { try store.registerQuickSale(recordID: businessID, items: items, payment: payment); dismiss() }
                    catch { self.error = error.localizedDescription }
                }.buttonStyle(.borderedProminent).disabled(businessID == nil || items.isEmpty || total <= 0)
            }
        }.navigationTitle("Nueva venta")
            .onAppear { if businessID == nil { businessID = initialBusinessID } }
            .alert("No se pudo guardar", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) { Button("Aceptar") { error = nil } } message: { Text(error ?? "") }
    }
    private func addItem() {
        guard let productID, let amount = Double(price.replacingOccurrences(of: ",", with: ".")), let cents = MoneyLedger.cents(amount), cents >= 0 else { error = "Introduce un precio válido."; return }
        guard quantity <= store.money.stock(productID) else { error = MoneyError.insufficientStock.localizedDescription; return }
        guard !items.contains(where: { $0.productID == productID }) else { return }
        items.append(QuickSaleInput(productID: productID, quantity: quantity, unitPrice: amount)); self.productID = nil; quantity = 1
    }
}

struct ClientFollowUpView: View {
    @EnvironmentObject private var store: WorkspaceStore
    @State private var search = ""
    @State private var stage: ContactStage?
    var body: some View {
        List {
            Picker("Estado", selection: $stage) {
                Text("Todos").tag(nil as ContactStage?)
                ForEach(ContactStage.allCases) { Text($0.rawValue).tag(Optional($0)) }
            }
            ForEach(store.records.filter { (stage == nil || $0.trackingStage == stage) && (search.isEmpty || $0.place.name.localizedCaseInsensitiveContains(search)) }) { record in
                NavigationLink { ClientTimelineView(recordID: record.id) } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(record.place.name).font(.headline)
                        Text(record.trackingStage.rawValue).foregroundStyle(.secondary)
                        if let event = record.followUp?.last { Text(event.text).font(.caption).lineLimit(2) }
                    }
                }
            }
            if store.records.isEmpty { Text("Tus negocios guardados aparecerán aquí.").foregroundStyle(.secondary) }
        }.navigationTitle("Clientes").searchable(text: $search, prompt: "Buscar negocio")
    }
}
struct ClientTimelineView: View {
    @EnvironmentObject private var store: WorkspaceStore
    let recordID: UUID
    @State private var stage = ContactStage.pending
    @State private var note = ""
    @State private var error: String?
    private var record: VisitRecord? { store.records.first { $0.id == recordID } }
    var body: some View {
        List {
            if let record {
                Section("Seguimiento") {
                    Picker("Estado", selection: $stage) { ForEach(ContactStage.allCases) { Text($0.rawValue).tag($0) } }
                    TextField("Añadir nota al historial", text: $note, axis: .vertical).lineLimit(3...8)
                    Button("Guardar seguimiento") { save(visited: false) }
                    Button("Registrar visita realizada") { save(visited: true) }
                    if let date = record.reminderDate { LabeledContent("Próxima visita", value: date.formatted(date: .abbreviated, time: .shortened)) }
                }
                Section("Ventas") {
                    LabeledContent("Ingresos", value: suiteEuro(store.money.businessIncome(recordID)))
                    LabeledContent("Tarjetas vendidas", value: "\(store.money.businessCards(recordID))")
                    NavigationLink("Registrar venta") { QuickSaleView(initialBusinessID: recordID) }
                }
                Section("Historial") {
                    if !record.notes.isEmpty { Text(record.notes).foregroundStyle(.secondary) }
                    ForEach((record.followUp ?? []).sorted { $0.date > $1.date }) { event in
                        VStack(alignment: .leading, spacing: 5) {
                            Label(event.text, systemImage: event.isVisit ? "checkmark.circle" : "text.bubble")
                            Text(event.date.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    if (record.followUp ?? []).isEmpty { Text("Añade una nota o registra tu primera visita.").foregroundStyle(.secondary) }
                }
            } else { Text("Este negocio ya no está disponible.") }
        }.navigationTitle(record?.place.name ?? "Seguimiento")
            .onAppear { stage = record?.trackingStage ?? .pending }
            .alert("No se pudo guardar", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) { Button("Aceptar") { error = nil } } message: { Text(error ?? "") }
    }
    private func save(visited: Bool) {
        do { try store.updateTracking(recordID: recordID, stage: stage, note: note, visited: visited); note = "" }
        catch { self.error = error.localizedDescription }
    }
}

struct WeeklyGoalsView: View {
    @EnvironmentObject private var store: WorkspaceStore
    @State private var date = Date()
    @State private var cards = 25
    @State private var visits = 10
    @State private var profit = "100"
    @State private var message: String?
    private var progress: WeeklyProgress { WeeklyProgress(records: store.records, money: store.money, date: date) }
    private var goals: WeeklyGoals { store.money.weeklyGoals ?? WeeklyGoals() }
    var body: some View {
        List {
            Section("Esta semana") {
                DatePicker("Semana de", selection: $date, displayedComponents: .date)
                goal("Tarjetas", value: Double(progress.cards), target: Double(goals.cards), label: "\(progress.cards) / \(goals.cards)")
                goal("Negocios visitados", value: Double(progress.visits), target: Double(goals.visits), label: "\(progress.visits) / \(goals.visits)")
                goal("Beneficio", value: Double(progress.profit), target: Double(goals.profitCents), label: "\(suiteEuro(progress.profit)) / \(suiteEuro(goals.profitCents))")
                if progress.unknownCosts { Text("Beneficio parcial: algunas ventas antiguas no tienen coste registrado.").font(.footnote).foregroundStyle(.orange) }
            }
            Section("Ingresos y beneficio diario") {
                Chart {
                    ForEach(progress.days, id: \.date) { day in
                        BarMark(x: .value("Día", day.date, unit: .day), y: .value("Euros", Double(day.income) / 100)).foregroundStyle(by: .value("Tipo", "Ingresos")).position(by: .value("Tipo", "Ingresos"))
                        BarMark(x: .value("Día", day.date, unit: .day), y: .value("Euros", Double(day.profit) / 100)).foregroundStyle(by: .value("Tipo", "Beneficio")).position(by: .value("Tipo", "Beneficio"))
                    }
                }.chartForegroundStyleScale(["Ingresos": Color.blue, "Beneficio": Color.green]).frame(height: 220)
            }
            Section("Tus objetivos") {
                Stepper("\(cards) tarjetas", value: $cards, in: 1...100_000)
                Stepper("\(visits) negocios visitados", value: $visits, in: 1...100_000)
                TextField("Beneficio semanal (€)", text: $profit)
                Button("Guardar objetivos") {
                    guard let amount = Double(profit.replacingOccurrences(of: ",", with: ".")), let cents = MoneyLedger.cents(amount), cents > 0 else { message = "Introduce un beneficio mayor que cero."; return }
                    do { try store.setWeeklyGoals(WeeklyGoals(cards: cards, visits: visits, profitCents: cents)); message = "Objetivos guardados." }
                    catch { message = error.localizedDescription }
                }
                if let message { Text(message).font(.footnote) }
                Text("Se cuenta cada negocio visitado una vez por semana. El beneficio resta el coste de los productos vendidos; el saldo incluye todos los gastos.").font(.footnote).foregroundStyle(.secondary)
            }
        }.navigationTitle("Objetivos semanales").onAppear { cards = goals.cards; visits = goals.visits; profit = String(Double(goals.profitCents) / 100) }
    }
    private func goal(_ title: String, value: Double, target: Double, label: String) -> some View {
        VStack(alignment: .leading) { LabeledContent(title, value: label); ProgressView(value: min(max(value, 0), target), total: target) }.padding(.vertical, 4)
    }
}
struct SaleProfitView: View {
    @EnvironmentObject private var store: WorkspaceStore
    var body: some View {
        List {
            Section { Text("El beneficio resta el coste medio de tarjetas, stands y productos en el momento de vender. Las compras ya figuran como gastos en el saldo; no se descuentan dos veces.").font(.footnote).foregroundStyle(.secondary) }
            Section("Por negocio") {
                ForEach(store.records.filter { store.money.businessIncome($0.id) != 0 }) { record in
                    NavigationLink { ClientTimelineView(recordID: record.id) } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(record.place.name).font(.headline)
                            LabeledContent("Ingresos", value: suiteEuro(store.money.businessIncome(record.id)))
                            LabeledContent("Beneficio", value: store.money.businessProfit(record.id).map(suiteEuro) ?? "Coste pendiente")
                        }
                    }
                }
            }
            Section("Detalle de ventas") {
                ForEach(store.money.activeQuickSales.sorted { $0.date > $1.date }) { sale in
                    DisclosureGroup {
                        ForEach(Array(sale.items.enumerated()), id: \.offset) { _, line in
                            VStack(alignment: .leading) {
                                Text("\(line.quantity) × \(line.title)")
                                Text("Ingreso: \(suiteEuro(line.incomeCents)) · Coste: \(line.costCents.map(suiteEuro) ?? "pendiente")").font(.caption)
                            }
                        }
                        LabeledContent("Beneficio", value: sale.profitCents.map(suiteEuro) ?? "Coste pendiente")
                    } label: {
                        VStack(alignment: .leading) {
                            Text(store.records.first { $0.id == sale.businessID }?.place.name ?? "Negocio eliminado")
                            Text("\(suiteEuro(sale.incomeCents)) · \(sale.paymentMethod) · \(sale.date.formatted(date: .abbreviated, time: .shortened))").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                if store.money.activeQuickSales.isEmpty { Text("Las nuevas ventas mostrarán aquí el desglose de productos y costes.").foregroundStyle(.secondary) }
            }
        }.navigationTitle("Ventas y beneficio")
    }
}

struct WorkspaceRouteView: View {
    @EnvironmentObject private var store: WorkspaceStore
    @StateObject private var location = WorkspaceLocation()
    @State private var day = Date()
    @State private var walking = true
    private var stops: [RouteStop] { DailyRoute.stops(records: store.records, day: day, origin: location.origin) }
    var body: some View {
        List {
            Section {
                DatePicker("Día", selection: $day, displayedComponents: .date)
                Button("Ordenar desde mi ubicación") { location.request() }
                if let message = location.message { Text(message).font(.footnote).foregroundStyle(.secondary) }
                Toggle("A pie", isOn: $walking)
                Text("Primero las citas por hora; después, los pendientes por cercanía. El trayecto no garantiza llegar a tiempo: revisa las duraciones en Mapas.").font(.footnote).foregroundStyle(.secondary)
            }
            Section("Abrir recorrido") {
                ForEach(Array(stride(from: 0, to: stops.count, by: 4)), id: \.self) { start in
                    if let url = DailyRoute.mapURL(stops: Array(stops[start..<min(start + 4, stops.count)]), walking: walking) {
                        Link("Google Maps · paradas \(start + 1)–\(min(start + 4, stops.count))", destination: url)
                    }
                }
                Text("El recorrido se divide en tramos de hasta cuatro paradas para abrirlo desde el móvil.").font(.caption).foregroundStyle(.secondary)
            }
            ForEach(Array(stops.enumerated()), id: \.element.id) { index, stop in
                NavigationLink { ClientTimelineView(recordID: stop.id) } label: {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("\(index + 1). \(stop.record.place.name)").font(.headline)
                        Text(stop.record.place.address).font(.caption).foregroundStyle(.secondary)
                        if let time = stop.record.reminderDate { Text(time.formatted(date: .omitted, time: .shortened)) }
                        if let distance = stop.distanceMeters { Text("\(Int(distance)) m en línea recta").font(.caption) }
                    }
                }
            }
            if stops.isEmpty { Text("No hay visitas para este día ni negocios pendientes sin cita.").foregroundStyle(.secondary) }
        }.navigationTitle("Ruta del día")
    }
}
@MainActor private final class WorkspaceLocation: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var origin: PlaceResult?
    @Published var message: String?
    private let manager = CLLocationManager()
    override init() { super.init(); manager.delegate = self; manager.desiredAccuracy = kCLLocationAccuracyHundredMeters }
    private var authorized: Bool {
        #if os(macOS)
        return manager.authorizationStatus == .authorizedAlways
        #else
        return [.authorizedAlways, .authorizedWhenInUse].contains(manager.authorizationStatus)
        #endif
    }
    func request() {
        if manager.authorizationStatus == .notDetermined { manager.requestWhenInUseAuthorization() }
        else if authorized { message = "Buscando ubicación…"; manager.requestLocation() }
        else { message = "Permite la ubicación en los ajustes de privacidad." }
    }
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) { if authorized { manager.requestLocation() } }
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let value = locations.last else { return }
        origin = PlaceResult(id: "route-origin", name: "Mi ubicación", address: "", latitude: value.coordinate.latitude, longitude: value.coordinate.longitude); message = "Ruta ordenada desde tu ubicación."
    }
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) { message = "No se pudo obtener la ubicación. Vuelve a intentarlo." }
}

struct CloudHistoryView: View {
    @EnvironmentObject private var cloud: CloudBackupController
    @State private var copies: [CloudBackupRecord] = []
    @State private var loading = false
    @State private var selected: Int64?
    @State private var message: String?
    var body: some View {
        List {
            Section {
                Text("Recupera una de las tres versiones anteriores conservadas en tu cuenta. Restaurar sustituye los datos actuales y sincroniza la copia con tus dispositivos.").font(.footnote).foregroundStyle(.secondary)
                if loading { ProgressView("Consultando la nube…") }
                Button("Actualizar versiones") { Task { await load() } }.disabled(loading)
                if let message { Text(message).font(.footnote) }
            }
            ForEach(copies, id: \.revision) { copy in
                Section("Versión \(copy.revision)") {
                    Text(copy.updated_at.flatMap { ISO8601DateFormatter().date(from: $0) }?.formatted(date: .abbreviated, time: .shortened) ?? copy.payload.createdAt.formatted(date: .abbreviated, time: .shortened))
                    LabeledContent("Negocios", value: "\(copy.payload.records.count)")
                    LabeledContent("Productos", value: "\(copy.payload.money.products.count)")
                    LabeledContent("Saldo", value: suiteEuro(copy.payload.money.balanceCents))
                    Button("Restaurar esta versión", role: .destructive) { selected = copy.revision }.disabled(loading)
                }
            }
            if !loading && copies.isEmpty { Text("Todavía no hay versiones anteriores disponibles.").foregroundStyle(.secondary) }
        }.navigationTitle("Versiones de la nube").task { await load() }
            .confirmationDialog("¿Restaurar esta versión?", isPresented: Binding(get: { selected != nil }, set: { if !$0 { selected = nil } }), titleVisibility: .visible) {
                Button("Restaurar y sincronizar", role: .destructive) {
                    guard let copy = copies.first(where: { $0.revision == selected }) else { return }; selected = nil
                    Task {
                        loading = true
                        do { try await cloud.restorePrevious(copy); message = cloud.state == .saved ? "Versión restaurada y guardada en la nube." : "Revisa el estado de sincronización en Perfil." }
                        catch { message = error.localizedDescription }
                        loading = false; await load()
                    }
                }
                Button("Cancelar", role: .cancel) { selected = nil }
            } message: { Text("Se conservará el estado actual como copia de recuperación antes de sustituirlo.") }
    }
    private func load() async {
        guard !loading else { return }; loading = true
        do { copies = try await cloud.previousCopies() }
        catch { message = error.localizedDescription }
        loading = false
    }
}
