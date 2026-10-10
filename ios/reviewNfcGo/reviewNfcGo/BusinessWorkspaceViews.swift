import SwiftUI
import Charts
import CoreLocation
import CoreText
import UniformTypeIdentifiers
#if os(iOS)
import UIKit
#endif

#if os(iOS)
typealias WorkspaceStore = AppStore
#else
typealias WorkspaceStore = MacStore
#endif
private func suiteEuro(_ cents: Int64) -> String { (Double(cents) / 100).formatted(.currency(code: "EUR").locale(Locale(identifier: "es_ES"))) }

struct BusinessHubView: View {
    var body: some View {
        List {
            Section("Tu actividad") {
                NavigationLink { TodayWorkspaceView() } label: { Label("Hoy", systemImage: "sun.max") }
                NavigationLink { QuotesWorkspaceView() } label: { Label("Presupuestos", systemImage: "doc.text") }
                NavigationLink { InventoryLevelsView() } label: { Label("Stock mínimo", systemImage: "shippingbox") }
                NavigationLink { QuickSaleView() } label: { Label("Registrar venta", systemImage: "plus.circle.fill") }
                NavigationLink { ClientFollowUpView() } label: { Label("Seguimiento de clientes", systemImage: "person.2") }
                NavigationLink { WorkspaceRouteView() } label: { Label("Ruta del día", systemImage: "map") }
            }
            Section("Resultados") {
                NavigationLink { MajorAnalyticsView() } label: { Label("Análisis del negocio", systemImage: "chart.bar.xaxis") }
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
                LabeledContent("Precio por unidad (€)") { TextField("0,00", text: $price).multilineTextAlignment(.trailing) }
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
        guard let productID, let amount = SaleAmountFormatting.parse(price), let cents = MoneyLedger.cents(amount), cents >= 0 else { error = "Introduce un precio válido."; return }
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
                Section("Contacto") {
                    if let name = record.contactName, !name.isEmpty { LabeledContent("Nombre", value: name) }
                    if let email = record.contactEmail, !email.isEmpty { Text(email).textSelection(.enabled) }
                    if let phone = record.contactPhone, !phone.isEmpty { Text(phone).textSelection(.enabled) }
                    NavigationLink("Editar contacto") { ClientContactView(recordID: recordID) }
                    NavigationLink("Presupuestos de este cliente") { QuotesWorkspaceView(businessID: recordID) }
                    NavigationLink("Enlace de tarjeta actualizable") { EditableReviewLinkView(recordID: recordID) }
                }
                Section("Seguimiento") {
                    Picker("Estado", selection: $stage) { ForEach(ContactStage.allCases) { Text($0.rawValue).tag($0) } }
                    TextField("Añadir nota al historial", text: $note, axis: .vertical).lineLimit(3...8)
                    Button("Guardar seguimiento") { save(visited: false) }
                    Button("Registrar visita realizada") { save(visited: true) }
                    #if os(iOS)
                    NavigationLink("Programar próxima visita") { QuickReminderView(place: record.place) }
                    #else
                    NavigationLink("Programar próxima visita") { MacBusinessEditor(record: record) }
                    #endif
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

struct TodayWorkspaceView: View {
    @EnvironmentObject private var store: WorkspaceStore
    @EnvironmentObject private var cloud: CloudBackupController
    private var today: TodaySummary { TodaySummary(records: store.records, money: store.money) }
    var body: some View {
        List {
            Section {
                #if os(iOS)
                NavigationLink { HomeView(showsNavigation: true) } label: { Label("Buscar negocio y escribir NFC", systemImage: "magnifyingglass") }
                #endif
                HStack { Label("Ventas de hoy", systemImage: "eurosign.circle"); Spacer(); Text(suiteEuro(today.salesCents)).font(.title3.bold()) }
                NavigationLink { QuickSaleView() } label: { Label("Registrar venta", systemImage: "plus.circle.fill") }
                NavigationLink { QuotesWorkspaceView() } label: { Label("Presupuestos", systemImage: "doc.text") }
            }
            Section("Tu cuenta") { CloudBackupStatusView() }
            Section("Objetivo de la semana") {
                let goals = store.money.weeklyGoals ?? WeeklyGoals()
                ProgressView(value: min(Double(today.weekly.cards), Double(goals.cards)), total: Double(goals.cards)) { Text("\(today.weekly.cards) de \(goals.cards) tarjetas") }
                NavigationLink { WeeklyGoalsView() } label: { Label("Ver objetivos y beneficio", systemImage: "target") }
            }
            Section("Visitas de hoy") {
                if today.visits.isEmpty { Text("No tienes visitas programadas para hoy.").foregroundStyle(.secondary) }
                ForEach(today.visits) { record in
                    NavigationLink { ClientTimelineView(recordID: record.id) } label: {
                        VStack(alignment: .leading) { Text(record.place.name); if let date = record.reminderDate { Text(date, style: .time).foregroundStyle(.secondary) } }
                    }
                }
                NavigationLink { WorkspaceRouteView() } label: { Label("Organizar ruta", systemImage: "map") }
            }
            Section("Clientes pendientes") {
                if today.followUps.isEmpty { Text("El seguimiento está al día.").foregroundStyle(.secondary) }
                ForEach(Array(today.followUps.prefix(10))) { record in
                    NavigationLink { ClientTimelineView(recordID: record.id) } label: { VStack(alignment: .leading) { Text(record.place.name); Text(record.trackingStage.rawValue).font(.caption).foregroundStyle(.secondary) } }
                }
                NavigationLink { ClientFollowUpView() } label: { Label("Todos los clientes", systemImage: "person.2") }
            }
            if !store.money.lowStockProducts.isEmpty {
                Section("Reponer inventario") {
                    ForEach(store.money.lowStockProducts) { product in
                        NavigationLink { StockMinimumView(productID: product.id) } label: {
                            LabeledContent(product.displayName, value: "\(store.money.stock(product.id)) disponibles")
                        }
                    }
                }
            }
            Section("Herramientas") {
                NavigationLink { BusinessHubView() } label: { Label("Actividad y herramientas", systemImage: "square.grid.2x2") }
                NavigationLink { MajorAnalyticsView() } label: { Label("Análisis del negocio", systemImage: "chart.bar.xaxis") }
            }
        }.navigationTitle("Hoy")
    }
}

struct ClientContactView: View {
    @EnvironmentObject private var store: WorkspaceStore
    let recordID: UUID
    @State private var name = ""
    @State private var email = ""
    @State private var phone = ""
    @State private var error: String?
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        Form {
            Section("Persona de contacto") {
                TextField("Nombre", text: $name)
                TextField("Correo electrónico", text: $email)
                TextField("Teléfono", text: $phone)
            }
            Button("Guardar contacto") {
                guard var record = store.records.first(where: { $0.id == recordID }) else { return }
                record.contactName = name.trimmingCharacters(in: .whitespacesAndNewlines)
                record.contactEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
                record.contactPhone = phone.trimmingCharacters(in: .whitespacesAndNewlines)
                do { try store.saveClient(record); dismiss() } catch { self.error = error.localizedDescription }
            }.buttonStyle(.borderedProminent)
        }.navigationTitle("Contacto").onAppear {
            guard let record = store.records.first(where: { $0.id == recordID }) else { return }
            name = record.contactName ?? ""; email = record.contactEmail ?? ""; phone = record.contactPhone ?? ""
        }.alert("No se pudo guardar", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) { Button("Aceptar") { error = nil } } message: { Text(error ?? "") }
    }
}

struct QuotesWorkspaceView: View {
    @EnvironmentObject private var store: WorkspaceStore
    var businessID: UUID? = nil
    var body: some View {
        List {
            NavigationLink { QuoteEditorView(initialBusinessID: businessID) } label: { Label("Crear presupuesto", systemImage: "plus.circle") }
            ForEach((store.money.quotations ?? []).filter { businessID == nil || $0.businessID == businessID }.sorted { $0.createdAt > $1.createdAt }) { quote in
                NavigationLink { QuoteDetailView(quoteID: quote.id) } label: {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(quote.businessName).font(.headline)
                        HStack { Text(quote.number + " · " + quote.status.rawValue); Spacer(); Text(suiteEuro(quote.totalCents)) }.font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            if (store.money.quotations ?? []).isEmpty { Text("Prepara una propuesta y compártela en PDF. Convertirla en venta descontará las unidades del inventario.").foregroundStyle(.secondary) }
        }.navigationTitle("Presupuestos")
    }
}
struct QuoteEditorView: View {
    @EnvironmentObject private var store: WorkspaceStore
    @Environment(\.dismiss) private var dismiss
    var initialBusinessID: UUID? = nil
    @State private var businessID: UUID?
    @State private var productID: UUID?
    @State private var quantity = 1
    @State private var price = "10"
    @State private var discount = 0
    @State private var validity = 30
    @State private var notes = ""
    @State private var items: [QuoteLine] = []
    @State private var error: String?
    private var subtotal: Int64 { items.reduce(0) { $0 + $1.totalCents } }
    var body: some View {
        Form {
            Section("Cliente") {
                Picker("Negocio", selection: $businessID) { Text("Seleccionar").tag(nil as UUID?); ForEach(store.records) { Text($0.place.name).tag(Optional($0.id)) } }
            }
            Section("Productos") {
                Picker("Producto", selection: $productID) { Text("Seleccionar").tag(nil as UUID?); ForEach(store.money.products.filter { p in !items.contains { $0.productID == p.id } }) { Text($0.displayName).tag(Optional($0.id)) } }
                Stepper("Cantidad: \(quantity)", value: $quantity, in: 1...100_000)
                LabeledContent("Precio por unidad (€)") { TextField("0,00", text: $price).multilineTextAlignment(.trailing) }
                Button("Añadir producto") {
                    guard let product = store.money.products.first(where: { $0.id == productID }), let value = SaleAmountFormatting.parse(price), let cents = MoneyLedger.cents(value), cents >= 0 else { error = "Selecciona un producto e introduce un precio válido."; return }
                    items.append(QuoteLine(productID: product.id, title: product.displayName, quantity: quantity, unitPriceCents: cents)); productID = nil; quantity = 1
                }.disabled(productID == nil || items.count >= 20)
                ForEach(items) { item in
                    HStack { Text("\(item.quantity) × \(item.title)"); Spacer(); Text(suiteEuro(item.totalCents)); Button(role: .destructive) { items.removeAll { $0.id == item.id } } label: { Image(systemName: "minus.circle") }.buttonStyle(.borderless).accessibilityLabel("Quitar producto") }
                }
                Text("El presupuesto no reserva stock. Se comprobarán las existencias al convertirlo en venta.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Condiciones") {
                Stepper("Descuento: \(discount)%", value: $discount, in: 0...100)
                Stepper("Validez: \(validity) días", value: $validity, in: 1...365)
                TextField("Notas y condiciones", text: $notes, axis: .vertical)
                LabeledContent("Total", value: suiteEuro(subtotal - (subtotal * Int64(discount) + 50) / 100))
                Button("Guardar presupuesto") {
                    guard let record = store.records.first(where: { $0.id == businessID }) else { return }
                    let now = Date()
                    let quote = BusinessQuote(businessID: record.id, businessName: record.place.name, createdAt: now, expiresAt: Calendar.current.date(byAdding: .day, value: validity, to: now)!, items: items, discountPercent: discount, notes: notes)
                    do { try store.saveQuote(quote); dismiss() } catch { self.error = error.localizedDescription }
                }.buttonStyle(.borderedProminent).disabled(businessID == nil || items.isEmpty)
            }
        }.navigationTitle("Nuevo presupuesto").onAppear { businessID = initialBusinessID }
            .alert("No se pudo guardar", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) { Button("Aceptar") { error = nil } } message: { Text(error ?? "") }
    }
}
struct QuoteDetailView: View {
    @EnvironmentObject private var store: WorkspaceStore
    let quoteID: UUID
    @State private var payment = "Transferencia"
    @State private var error: String?
    @State private var pdfURL: URL?
    @State private var confirm = false
    private var quote: BusinessQuote? { store.money.quotations?.first { $0.id == quoteID } }
    var body: some View {
        List {
            if let quote {
                Section(quote.businessName) {
                    LabeledContent("Presupuesto", value: quote.number)
                    LabeledContent("Estado", value: quote.status.rawValue)
                    LabeledContent("Válido hasta", value: quote.expiresAt.formatted(date: .abbreviated, time: .omitted))
                    ForEach(quote.items) { line in LabeledContent("\(line.quantity) × \(line.title)", value: suiteEuro(line.totalCents)) }
                    LabeledContent("Descuento", value: "\(quote.discountPercent)% · \(suiteEuro(quote.discountCents))")
                    LabeledContent("Total", value: suiteEuro(quote.totalCents))
                    if !quote.notes.isEmpty { Text(quote.notes) }
                }
                Section("Compartir") {
                    Button("Preparar PDF", systemImage: "doc.richtext") {
                        do { pdfURL = try QuotePDF.create(quote, owner: storeOwner) } catch { self.error = error.localizedDescription }
                    }
                    if let pdfURL { ShareLink("Compartir presupuesto PDF", item: pdfURL) }
                    if quote.saleID == nil {
                        Button("Marcar como enviado") { var next = quote; next.status = .sent; save(next) }
                        Button("Marcar como rechazado") { var next = quote; next.status = .declined; save(next) }
                    }
                }
                if quote.saleID == nil && quote.status != .declined {
                    Section("Aceptar y registrar venta") {
                        Picker("Forma de pago", selection: $payment) { ForEach(["Efectivo", "Tarjeta", "Bizum", "Transferencia", "Otro"], id: \.self) { Text($0) } }
                        Button("Convertir en venta") { confirm = true }.buttonStyle(.borderedProminent).disabled(quote.expiresAt < Date() || quote.totalCents <= 0)
                        Text("Registra \(suiteEuro(quote.totalCents)) de ingreso y descuenta las unidades del inventario.").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }.navigationTitle("Presupuesto")
            .confirmationDialog("¿Registrar esta venta?", isPresented: $confirm, titleVisibility: .visible) { Button("Registrar venta") { do { try store.convertQuote(quoteID, payment: payment) } catch { self.error = error.localizedDescription } } }
            .alert("No se pudo completar", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) { Button("Aceptar") { error = nil } } message: { Text(error ?? "") }
    }
    private var storeOwner: String {
        #if os(iOS)
        return RemoteAuthClient.shared.session?.user.email ?? ""
        #else
        return store.owner ?? ""
        #endif
    }
    private func save(_ value: BusinessQuote) { do { try store.saveQuote(value) } catch { self.error = error.localizedDescription } }
}

struct StockMinimumView: View {
    @EnvironmentObject private var store: WorkspaceStore
    let productID: UUID
    @State private var minimum = 5
    @State private var error: String?
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        Form {
            if let product = store.money.products.first(where: { $0.id == productID }) {
                LabeledContent("Producto", value: product.displayName)
                LabeledContent("Disponibles", value: "\(store.money.stock(productID))")
                Stepper("Avisar con \(minimum) unidades o menos", value: $minimum, in: 0...100_000)
                Button("Guardar mínimo") { do { try store.setMinimumStock(productID, quantity: minimum); dismiss() } catch { self.error = error.localizedDescription } }.buttonStyle(.borderedProminent)
                Text("Las unidades fabricadas siguen registrándose como entradas de inventario de cero euros.").foregroundStyle(.secondary)
            }
        }.navigationTitle("Stock mínimo").onAppear { minimum = store.money.products.first { $0.id == productID }?.minimumStock ?? 5 }
            .alert("No se pudo guardar", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) { Button("Aceptar") { error = nil } } message: { Text(error ?? "") }
    }
}

struct MajorAnalyticsView: View {
    @EnvironmentObject private var store: WorkspaceStore
    @State private var month = Date()
    private var current: DateInterval { Calendar.current.dateInterval(of: .month, for: month)! }
    private var previous: DateInterval { Calendar.current.dateInterval(of: .month, for: Calendar.current.date(byAdding: .month, value: -1, to: month)!)! }
    private func entries(_ range: DateInterval) -> [MoneyTransaction] { store.money.transactions.filter { $0.date >= range.start && $0.date < range.end } }
    private func income(_ range: DateInterval) -> Int64 { entries(range).filter { $0.kind.isIncome }.reduce(0) { $0 + $1.cents } }
    private func expense(_ range: DateInterval) -> Int64 { -entries(range).filter { $0.kind == .expense || $0.kind == .refund }.reduce(0) { $0 + $1.cents } }
    var body: some View {
        List {
            Section("Comparar meses") {
                DatePicker("Mes", selection: $month, displayedComponents: .date)
                LabeledContent("Ingresos de este mes", value: suiteEuro(income(current)))
                LabeledContent("Ingresos del mes anterior", value: suiteEuro(income(previous)))
                LabeledContent("Variación de ingresos", value: suiteEuro(income(current) - income(previous)))
                Chart {
                    BarMark(x: .value("Mes", previous.start, unit: .month), y: .value("Euros", Double(income(previous)) / 100)).foregroundStyle(by: .value("Tipo", "Ingresos"))
                    BarMark(x: .value("Mes", current.start, unit: .month), y: .value("Euros", Double(income(current)) / 100)).foregroundStyle(by: .value("Tipo", "Ingresos"))
                    BarMark(x: .value("Mes", previous.start, unit: .month), y: .value("Euros", Double(expense(previous)) / 100)).foregroundStyle(by: .value("Tipo", "Gastos"))
                    BarMark(x: .value("Mes", current.start, unit: .month), y: .value("Euros", Double(expense(current)) / 100)).foregroundStyle(by: .value("Tipo", "Gastos"))
                }.frame(height: 220)
                LabeledContent("Flujo neto del mes", value: suiteEuro(income(current) - expense(current)))
            }
            Section("Resultados por producto · histórico") {
                ForEach(store.money.productPerformance) { result in
                    VStack(alignment: .leading, spacing: 5) {
                        Text(result.product.displayName).font(.headline)
                        Text("\(result.quantity) vendidos · Ingresos \(suiteEuro(result.revenue))")
                        Text(result.profit.map { "Beneficio: " + suiteEuro($0) } ?? "Coste pendiente de registrar").foregroundStyle(.secondary)
                    }
                }
            }
            Section("Clientes por beneficio · histórico") {
                ForEach(store.records.sorted { (store.money.businessProfit($0.id) ?? Int64.min) > (store.money.businessProfit($1.id) ?? Int64.min) }) { record in
                    NavigationLink { ClientTimelineView(recordID: record.id) } label: { LabeledContent(record.place.name, value: store.money.businessProfit(record.id).map(suiteEuro) ?? "Coste pendiente") }
                }
            }
            #if os(macOS)
            Section("Exportar") {
                Button("Exportar operaciones para Excel (CSV)") { MacFiles.export(store: store, csv: true) }
            }
            #endif
        }.navigationTitle("Análisis del negocio")
    }
}

struct InventoryLevelsView: View {
    @EnvironmentObject private var store: WorkspaceStore
    var body: some View {
        List {
            ForEach(store.money.products) { product in
                NavigationLink { StockMinimumView(productID: product.id) } label: {
                    VStack(alignment: .leading) {
                        Text(product.displayName)
                        Text("Disponibles: \(store.money.stock(product.id)) · Mínimo: \(product.minimumStock ?? 5)").font(.caption).foregroundStyle(store.money.stock(product.id) <= (product.minimumStock ?? 5) ? Color.orange : Color.secondary)
                    }
                }
            }
            if store.money.products.isEmpty { Text("Añade productos al inventario para configurar sus avisos.").foregroundStyle(.secondary) }
        }.navigationTitle("Stock mínimo")
    }
}
@MainActor enum QuotePDF {
    static func create(_ quote: BusinessQuote, owner: String) throws -> URL {
        try quote.validate()
        let lines = quote.items.map { "\($0.quantity) × \($0.title)\nPrecio unidad: \(suiteEuro($0.unitPriceCents))    Importe: \(suiteEuro($0.totalCents))" }.joined(separator: "\n\n")
        let text = "PRESUPUESTO \(quote.number)\nreviewNfcGo · \(owner)\n\nCliente: \(quote.businessName)\nFecha: \(quote.createdAt.formatted(date: .abbreviated, time: .omitted))\nVálido hasta: \(quote.expiresAt.formatted(date: .abbreviated, time: .omitted))\n\n\(lines)\n\nSubtotal: \(suiteEuro(quote.subtotalCents))\nDescuento: \(quote.discountPercent)% (\(suiteEuro(quote.discountCents)))\nTOTAL: \(suiteEuro(quote.totalCents))\n\n\(quote.notes)\n\nPresupuesto comercial. No es una factura ni un justificante de pago."
        let font = CTFontCreateWithName("Helvetica" as CFString, 12, nil)
        let attributes: [NSAttributedString.Key: Any] = [NSAttributedString.Key(kCTFontAttributeName as String): font]
        let content = NSAttributedString(string: text, attributes: attributes)
        let framesetter = CTFramesetterCreateWithAttributedString(content as CFAttributedString)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(quote.number + "-" + UUID().uuidString + ".pdf")
        var page = CGRect(x: 0, y: 0, width: 595, height: 842)
        guard let context = CGContext(url as CFURL, mediaBox: &page, nil) else { throw CocoaError(.fileWriteUnknown) }
        var offset = 0
        while offset < content.length {
            context.beginPDFPage(nil)
            let path = CGPath(rect: CGRect(x: 40, y: 50, width: 515, height: 742), transform: nil)
            let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: offset, length: 0), path, nil)
            CTFrameDraw(frame, context)
            let visible = CTFrameGetVisibleStringRange(frame)
            context.endPDFPage()
            guard visible.length > 0 else { context.closePDF(); throw CocoaError(.fileWriteUnknown) }
            offset += visible.length
        }
        context.closePDF()
        return url
    }
}

struct EditableReviewLinkView: View {
    @EnvironmentObject private var store: WorkspaceStore
    let recordID: UUID
    @State private var target = ""
    @State private var active = true
    @State private var busy = false
    @State private var message: String?
    private var record: VisitRecord? { store.records.first { $0.id == recordID } }
    var body: some View {
        Form {
            if let record {
                Section("Destino de la tarjeta") {
                    TextField("Dirección HTTPS", text: $target, axis: .vertical).lineLimit(2...5)
                    Toggle("Tarjeta activa", isOn: $active)
                    Button(record.reviewLinkID == nil ? "Crear enlace" : "Guardar nuevo destino") { publish() }
                        .buttonStyle(.borderedProminent).disabled(busy || !ReviewLinkAddress.validTarget(target))
                    if busy { ProgressView() }
                    if let message { Text(message).foregroundStyle(.secondary) }
                }
                if let id = record.reviewLinkID {
                    Section("Escribir una sola vez") {
                        Text(ReviewLinkAddress.permanent(id)).font(.caption).textSelection(.enabled)
                        #if os(iOS)
                        Button("Escribir NFC") { ExternalNFCWriter.write(reviewURL: ReviewLinkAddress.permanent(id)) }.buttonStyle(.borderedProminent)
                        Button("Copiar enlace de tarjeta") { UIPasteboard.general.string = ReviewLinkAddress.permanent(id) }
                        #else
                        Button("Copiar enlace de tarjeta") { MacFiles.copy(ReviewLinkAddress.permanent(id)) }
                        #endif
                        Link("Probar tarjeta", destination: URL(string: ReviewLinkAddress.permanent(id))!)
                        Text("Cambia el destino desde aquí sin volver a escribir la tarjeta. Las tarjetas que ya contienen un enlace directo a Google deben regrabarse una vez.").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Section {
                    Text("El destino es accesible para quien tenga el enlace de la tarjeta. Tus datos de cuenta siguen privados. Para abrirlo y cambiarlo se necesita conexión.").font(.caption).foregroundStyle(.secondary)
                }
            }
        }.navigationTitle("Tarjeta actualizable").onAppear {
            target = record?.reviewLinkTarget ?? record?.place.reviewURL ?? ""; active = record?.reviewLinkActive ?? true
        }
    }
    private func publish() {
        guard let initial = record else { return }
        let owner = RemoteAuthClient.shared.session?.user.id
        let id = initial.reviewLinkID ?? UUID()
        let destination = target, enabled = active
        busy = true; message = nil
        Task { @MainActor in
            defer { busy = false }
            do {
                try await RemoteAuthClient.shared.publishReviewLink(id: id, target: destination, active: enabled)
                guard owner == RemoteAuthClient.shared.session?.user.id, var current = record else { throw CancellationError() }
                current.reviewLinkID = id; current.reviewLinkTarget = destination; current.reviewLinkActive = enabled
                try store.saveClient(current); message = "Destino guardado. La tarjeta abrirá este enlace."
            } catch is CancellationError { message = "El acceso ha cambiado. Vuelve a intentarlo." }
            catch { message = error.localizedDescription }
        }
    }
}
