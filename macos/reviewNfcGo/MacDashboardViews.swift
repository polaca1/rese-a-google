import SwiftUI
import Charts
import MapKit

struct MacDashboardView: View {
    @EnvironmentObject private var store: MacStore
    @EnvironmentObject private var navigation: MacNavigation
    private var upcoming: [VisitRecord] { store.upcoming.filter { ($0.reminderDate ?? .distantPast) >= Date() } }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Resumen de tu actividad").font(.largeTitle.bold())
                    Text(Date.now.formatted(.dateTime.weekday(.wide).day().month(.wide))).foregroundStyle(.secondary)
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 175), spacing: 14)], spacing: 14) {
                    metric("Saldo disponible", value: euro(store.money.balanceCents), symbol: "eurosign.circle", negative: store.money.balanceCents < 0)
                    metric("Ingresos", value: euro(store.money.incomeCents), symbol: "arrow.down.left")
                    metric("Gastos", value: euro(store.money.expenseCents), symbol: "arrow.up.right")
                    metric("Tarjetas vendidas", value: String(store.soldCards), symbol: "creditcard")
                }
                MacCard(title: "Ingresos y gastos · últimos 14 días") {
                    if store.money.transactions.isEmpty {
                        Text("Registra tu primera venta o compra para ver la evolución.").foregroundStyle(.secondary).frame(height: 170)
                    } else {
                        Chart(DesktopAnalytics.days(store.money)) { day in
                            BarMark(x: .value("Día", day.date, unit: .day), y: .value("Euros", Double(day.income) / 100))
                                .foregroundStyle(by: .value("Tipo", "Ingresos")).position(by: .value("Tipo", "Ingresos"))
                            BarMark(x: .value("Día", day.date, unit: .day), y: .value("Euros", Double(day.expenses) / 100))
                                .foregroundStyle(by: .value("Tipo", "Gastos")).position(by: .value("Tipo", "Gastos"))
                        }
                        .chartForegroundStyleScale(["Ingresos": Color.blue, "Gastos": Color.orange])
                        .chartXAxis { AxisMarks(values: .stride(by: .day, count: 2)) { AxisValueLabel(format: .dateTime.day().month(.abbreviated)); AxisTick() } }
                        .frame(height: 180)
                    }
                }
                HStack(alignment: .top, spacing: 18) {
                    MacCard(title: "Próximas visitas") {
                        if upcoming.isEmpty { Text("No tienes próximas visitas programadas.").foregroundStyle(.secondary) }
                        ForEach(upcoming.prefix(4)) { record in
                            Button { navigation.openBusiness(record.id, store: store) } label: {
                                HStack(alignment: .top, spacing: 12) {
                                    Image(systemName: "calendar").foregroundStyle(Color.accentColor).frame(width: 24)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(record.place.name).font(.headline).foregroundStyle(.primary)
                                        Text(record.reminderDate!, format: .dateTime.day().month(.abbreviated).hour().minute()).foregroundStyle(.secondary)
                                    }
                                    Spacer(minLength: 0)
                                }.contentShape(Rectangle())
                            }.buttonStyle(.plain)
                        }
                        Button("Ver todas las visitas") { navigation.section = .visits }
                    }
                    MacCard(title: "Inventario a revisar") {
                        if store.money.lowStockProducts.isEmpty {
                            Label("Sin tarjetas con existencias bajas", systemImage: "checkmark.circle").foregroundStyle(.secondary)
                        }
                        ForEach(store.money.lowStockProducts.prefix(4)) { product in
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(product.displayName).font(.headline)
                                    Text("\(store.money.stock(product.id)) disponibles").foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange).accessibilityLabel("Existencias bajas")
                            }
                        }
                        Button("Abrir inventario") { navigation.section = .inventory }
                    }
                }
                MacCard(title: "Últimas operaciones") {
                    if store.money.history.isEmpty { Text("Aquí aparecerán tus ingresos y gastos.").foregroundStyle(.secondary) }
                    ForEach(store.money.history.prefix(5)) { item in
                        Button {
                            if let id = item.businessID, store.records.contains(where: { $0.id == id }) { navigation.openBusiness(id, store: store) }
                            else { navigation.sheet = .transaction(item.id) }
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: item.kind.isIncome ? "arrow.down.left.circle" : "arrow.up.right.circle").foregroundStyle(.secondary)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(item.title).foregroundStyle(.primary)
                                    Text(item.typeTitle + " · " + item.date.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(euro(item.cents)).monospacedDigit().foregroundStyle(.primary)
                            }.contentShape(Rectangle())
                        }.buttonStyle(.plain)
                    }
                }
            }.padding(28)
        }.background(Color(nsColor: .windowBackgroundColor))
    }
    private func metric(_ title: String, value: String, symbol: String, negative: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: symbol).font(.callout).foregroundStyle(.secondary)
            Text(value).font(.system(size: 27, weight: .semibold, design: .rounded)).monospacedDigit()
                .foregroundStyle(negative ? Color.red : Color.primary).minimumScaleFactor(0.8).lineLimit(1)
        }.padding(18).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.primary.opacity(0.07)))
    }
}

struct MacBusinessesView: View {
    @EnvironmentObject private var store: MacStore
    @EnvironmentObject private var navigation: MacNavigation
    @State private var query = ""
    @State private var status = "Todos"
    @State private var sorting = [KeyPathComparator(\VisitRecord.place.name)]
    private var rows: [VisitRecord] {
        store.records.filter { record in
            (status == "Todos" || record.status.rawValue == status) &&
            (query.isEmpty || (record.place.name + " " + record.place.address + " " + record.notes).localizedStandardContains(query))
        }.sorted(using: sorting)
    }
    var body: some View {
        HSplitView {
            VStack(spacing: 0) {
                HStack {
                    TextField("Buscar negocio, dirección o nota", text: $query).textFieldStyle(.roundedBorder)
                    Picker("Estado", selection: $status) {
                        Text("Todos").tag("Todos")
                        ForEach(VisitStatus.allCases, id: \.rawValue) { Text($0.displayName).tag($0.rawValue) }
                    }.labelsHidden().frame(width: 155)
                }.padding(16)
                if store.records.isEmpty {
                    MacEmptyView(title: "Tus negocios", symbol: "building.2", detail: "Añade un negocio o importa una copia del iPhone.")
                } else if rows.isEmpty {
                    MacEmptyView(title: "Sin coincidencias", symbol: "magnifyingglass", detail: "Prueba otro nombre o cambia el filtro de estado.")
                } else {
                    Table(rows, selection: $navigation.selectedBusiness, sortOrder: $sorting) {
                        TableColumn("Negocio", value: \.place.name).width(min: 145, ideal: 210)
                        TableColumn("Estado", value: \.status.rawValue) { Text($0.status.displayName) }.width(min: 100, ideal: 130)
                        TableColumn("Tarjetas") { Text(String(store.money.businessCards($0.id))).monospacedDigit() }.width(65)
                        TableColumn("Ingreso") { Text(euro(store.money.businessIncome($0.id))).monospacedDigit() }.width(95)
                    }
                    .contextMenu(forSelectionType: UUID.self) { ids in
                        if let id = ids.first { Button("Editar negocio") { navigation.sheet = .business(id) } }
                    } primaryAction: { ids in if let id = ids.first { navigation.sheet = .business(id) } }
                }
                HStack { Text("\(rows.count) negocios").font(.caption).foregroundStyle(.secondary); Spacer() }.padding(12)
            }.frame(minWidth: 355, maxWidth: .infinity, maxHeight: .infinity)
            if let id = navigation.selectedBusiness, let record = store.records.first(where: { $0.id == id }) {
                MacBusinessInspector(record: record).frame(minWidth: 270, idealWidth: 310, maxWidth: 380)
            }
        }
    }
}

struct MacBusinessInspector: View {
    let record: VisitRecord
    @EnvironmentObject private var store: MacStore
    @EnvironmentObject private var navigation: MacNavigation
    @State private var deleteConfirmation = false
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Label("Ficha del negocio", systemImage: "building.2").foregroundStyle(.secondary)
                Text(record.place.name).font(.title2.bold()).textSelection(.enabled)
                Text(record.place.address).foregroundStyle(.secondary).textSelection(.enabled)
                Button("Editar negocio") { navigation.sheet = .business(record.id) }.buttonStyle(.borderedProminent)
                Divider()
                LabeledContent("Estado", value: record.trackingStage.rawValue)
                LabeledContent("Tarjetas", value: String(store.money.businessCards(record.id)))
                LabeledContent("Ingreso", value: euro(store.money.businessIncome(record.id)))
                LabeledContent("Beneficio", value: store.money.businessProfit(record.id).map(euro) ?? "Coste sin asignar")
                if let visit = record.reminderDate {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("Visita", systemImage: "calendar").font(.headline)
                        Text(visit, format: .dateTime.day().month(.wide).year().hour().minute())
                        if let notice = record.notificationDate { Text("Aviso: " + notice.formatted(date: .abbreviated, time: .shortened)).font(.callout).foregroundStyle(.secondary) }
                        if record.arrivedAt != nil { Label("Visita realizada", systemImage: "checkmark.circle") }
                        else if record.status != .completed { Button("He llegado") { store.run { try store.arrive(record.id) } } }
                    }
                }
                if !record.notes.isEmpty { VStack(alignment: .leading, spacing: 8) { Text("Notas").font(.headline); Text(record.notes).textSelection(.enabled) } }
                Divider()
                Button("Abrir indicaciones", systemImage: "arrow.triangle.turn.up.right.diamond") { MacFiles.maps(record.place) }
                if reviewAvailable(record.place) {
                    Button("Copiar enlace de reseña", systemImage: "doc.on.doc") { MacFiles.copy(record.place.reviewURL) }
                    Link("Abrir reseña de Google", destination: URL(string: record.place.reviewURL)!)
                }
                Button("Volver mañana", systemImage: "calendar.badge.plus") { store.run { try store.tomorrow(record.id) } }
                Button("Eliminar negocio", role: .destructive) { deleteConfirmation = true }
            }.padding(22)
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .confirmationDialog("¿Eliminar \(record.place.name)?", isPresented: $deleteConfirmation, titleVisibility: .visible) {
            Button("Eliminar negocio", role: .destructive) {
                store.run { try store.delete(record.id) }; navigation.selectedBusiness = nil
            }
        } message: { Text("Los movimientos de dinero y las tarjetas vendidas seguirán en el historial. Puedes deshacer este cambio.") }
    }
}

struct MacVisitsView: View {
    @EnvironmentObject private var store: MacStore
    @EnvironmentObject private var navigation: MacNavigation
    @State private var day = Date()
    @State private var onlyDay = false
    private var visits: [VisitRecord] { store.upcoming.filter { !onlyDay || Calendar.current.isDate($0.reminderDate!, inSameDayAs: day) } }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Toggle("Solo este día", isOn: $onlyDay).toggleStyle(.checkbox)
                DatePicker("Día", selection: $day, displayedComponents: .date).labelsHidden().disabled(!onlyDay)
                Spacer()
                Text("\(visits.count) visitas pendientes").foregroundStyle(.secondary)
            }.padding(.horizontal, 24).padding(.top, 20)
            if visits.isEmpty {
                MacEmptyView(title: "Sin visitas pendientes", symbol: "calendar", detail: "Programa una visita desde la ficha de un negocio.")
            } else {
                List(visits) { record in
                    HStack(spacing: 18) {
                        VStack(spacing: 4) {
                            Text(record.reminderDate!, format: .dateTime.day()).font(.title.bold())
                            Text(record.reminderDate!, format: .dateTime.month(.abbreviated)).font(.caption)
                        }.frame(width: 48)
                        VStack(alignment: .leading, spacing: 5) {
                            Text(record.place.name).font(.headline)
                            Text(record.place.address).foregroundStyle(.secondary)
                            Text(record.reminderDate!, format: .dateTime.weekday(.wide).day().month(.wide).hour().minute()).font(.callout)
                            if record.reminderDate! < Date() { Label("Visita pendiente de confirmar", systemImage: "clock.badge.exclamationmark").font(.caption).foregroundStyle(.secondary) }
                        }
                        Spacer()
                        Button("Ficha") { navigation.openBusiness(record.id, store: store) }
                        Button("He llegado") { store.run { try store.arrive(record.id) } }
                        Button { MacFiles.maps(record.place) } label: { Label("Indicaciones", systemImage: "arrow.triangle.turn.up.right.diamond") }.labelStyle(.iconOnly).help("Abrir indicaciones")
                    }.padding(.vertical, 12)
                }
            }
        }
    }
}

struct MacMoneyView: View {
    @EnvironmentObject private var store: MacStore
    @EnvironmentObject private var navigation: MacNavigation
    @State private var filter = "Todos"
    @State private var query = ""
    @State private var selection: UUID?
    private var rows: [MoneyTransaction] {
        store.money.history.filter {
            (filter == "Todos" || (filter == "Ingresos" ? $0.kind.isIncome : !$0.kind.isIncome)) &&
            (query.isEmpty || ($0.title + " " + $0.merchant + " " + $0.notes).localizedStandardContains(query))
        }
    }
    var body: some View {
        VStack(spacing: 16) {
            HStack(spacing: 30) {
                moneyTotal("Saldo disponible", store.money.balanceCents)
                moneyTotal("Ingresos", store.money.incomeCents)
                moneyTotal("Gastos", store.money.expenseCents)
                Spacer()
                Button("Registrar gasto", systemImage: "plus") { navigation.sheet = .expense }.buttonStyle(.borderedProminent)
            }.padding(.horizontal, 24).padding(.top, 24)
            HStack {
                Picker("Operaciones", selection: $filter) { ForEach(["Todos", "Ingresos", "Gastos"], id: \.self) { Text($0) } }.pickerStyle(.segmented).frame(width: 300)
                Spacer()
                TextField("Buscar operación", text: $query).textFieldStyle(.roundedBorder).frame(maxWidth: 300)
                Button("Exportar CSV") { MacFiles.export(store: store, csv: true) }
            }.padding(.horizontal, 24)
            if rows.isEmpty {
                MacEmptyView(title: "Sin operaciones", symbol: "eurosign.circle", detail: "Las ventas de negocios y las compras aparecerán aquí.")
            } else {
                Table(rows, selection: $selection) {
                    TableColumn("Fecha") { Text($0.date, format: .dateTime.day().month(.abbreviated).year().hour().minute()) }.width(min: 140, ideal: 160)
                    TableColumn("Concepto", value: \.title).width(min: 150, ideal: 280)
                    TableColumn("Tipo") { Text($0.typeTitle) }.width(min: 95, ideal: 120)
                    TableColumn("Unidades") { Text(String($0.quantity)).monospacedDigit() }.width(65)
                    TableColumn("Importe") { Text(euro($0.cents)).monospacedDigit() }.width(100)
                }
                .contextMenu(forSelectionType: UUID.self) { ids in
                    if let id = ids.first { Button("Ver movimiento") { navigation.sheet = .transaction(id) } }
                }
                .onChange(of: selection) { _, id in
                    guard let id, let item = rows.first(where: { $0.id == id }) else { return }
                    selection = nil
                    if let businessID = item.businessID, store.records.contains(where: { $0.id == businessID }) { navigation.openBusiness(businessID, store: store) }
                    else { navigation.sheet = .transaction(id) }
                }
            }
        }
    }
    private func moneyTotal(_ title: String, _ cents: Int64) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).foregroundStyle(.secondary)
            Text(euro(cents)).font(.title2.bold()).monospacedDigit().foregroundStyle(cents < 0 ? Color.red : Color.primary)
        }
    }
}

struct MacInventoryView: View {
    @EnvironmentObject private var store: MacStore
    @EnvironmentObject private var navigation: MacNavigation
    @State private var query = ""
    @State private var selection: UUID?
    private var products: [InventoryProduct] { store.money.products.filter { query.isEmpty || $0.displayName.localizedStandardContains(query) }.sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending } }
    var body: some View {
        VStack(spacing: 16) {
            HStack {
                TextField("Buscar producto o color", text: $query).textFieldStyle(.roundedBorder).frame(maxWidth: 340)
                Spacer()
                Button("Registrar compra", systemImage: "plus") { navigation.sheet = .expense }.buttonStyle(.borderedProminent)
            }.padding(.horizontal, 24).padding(.top, 24)
            if products.isEmpty { MacEmptyView(title: "Tu inventario", symbol: "shippingbox", detail: "Registra una compra de tarjetas, stands o un producto personalizado.") }
            else {
                Table(products, selection: $selection) {
                    TableColumn("Producto", value: \.displayName).width(min: 160, ideal: 280)
                    TableColumn("Categoría") { Text($0.kind.title) }.width(min: 105, ideal: 145)
                    TableColumn("Adquiridas") { Text(String(store.money.purchased($0.id))).monospacedDigit() }.width(80)
                    TableColumn("Vendidas") { Text(String(store.money.sold($0.id))).monospacedDigit() }.width(75)
                    TableColumn("Disponibles") { product in
                        HStack { Text(String(store.money.stock(product.id))).monospacedDigit(); if product.kind == .nfcCard && store.money.stock(product.id) <= 5 { Image(systemName: "exclamationmark.triangle").help("Existencias bajas") } }
                    }.width(100)
                    TableColumn("Gastado") { Text(euro(MoneyLedger.cents(store.money.spent($0.id)) ?? 0)).monospacedDigit() }.width(95)
                }
                .contextMenu(forSelectionType: UUID.self) { ids in
                    if let id = ids.first, let product = store.money.products.first(where: { $0.id == id }) {
                        Button("Ajustar existencias") { navigation.sheet = .stock(id) }
                        if let url = ProductMetadataService.purchaseURL(product.purchaseURL) { Link("Volver a comprar", destination: url) }
                    }
                } primaryAction: { ids in if let id = ids.first { navigation.sheet = .stock(id) } }
                if let id = selection, let product = store.money.products.first(where: { $0.id == id }) {
                    HStack {
                        Button("Ajustar existencias") { navigation.sheet = .stock(id) }
                        if let url = ProductMetadataService.purchaseURL(product.purchaseURL) { Link("Volver a comprar", destination: url) }
                        Spacer()
                    }.padding(.horizontal, 24).padding(.bottom, 16)
                }
            }
        }
    }
}

struct MacMapView: View {
    @EnvironmentObject private var store: MacStore
    @EnvironmentObject private var navigation: MacNavigation
    @Environment(\.accessibilityReduceMotion) private var reducedMotion
    @State private var camera: MapCameraPosition = .automatic
    @State private var selection: UUID?
    @State private var onlyPending = true
    private var records: [VisitRecord] { store.records.filter { !onlyPending || ($0.status != .completed && $0.arrivedAt == nil) } }
    var body: some View {
        HSplitView {
            VStack(alignment: .leading, spacing: 14) {
                Toggle("Solo negocios pendientes", isOn: $onlyPending)
                Button("Mostrar todos en el mapa") { withAnimation(reducedMotion ? nil : .easeInOut(duration: 1.2)) { camera = .automatic; selection = nil } }
                List(records, selection: $selection) { record in
                    VStack(alignment: .leading, spacing: 5) { Text(record.place.name).font(.headline); Text(record.place.address).font(.caption).foregroundStyle(.secondary) }.padding(.vertical, 5).tag(record.id)
                }.listStyle(.inset)
                if let id = selection { Button("Abrir ficha") { navigation.openBusiness(id, store: store) } }
            }.padding(16).frame(minWidth: 230, idealWidth: 270, maxWidth: 340)
            Map(position: $camera, selection: $selection) {
                ForEach(records) { record in Marker(record.place.name, coordinate: record.place.coordinate).tag(record.id) }
            }.mapControls { MapCompass(); MapScaleView(); MapZoomStepper() }
                .overlay { if records.isEmpty { MacEmptyView(title: "Sin ubicaciones guardadas", symbol: "map", detail: "Añade negocios o cambia el filtro para verlos aquí.").background(.regularMaterial) } }
        }
        .onChange(of: selection) { _, id in
            if let record = records.first(where: { $0.id == id }) {
                withAnimation(reducedMotion ? nil : .easeInOut(duration: 1.2)) {
                    camera = .region(MKCoordinateRegion(center: record.place.coordinate, latitudinalMeters: 1600, longitudinalMeters: 1600))
                }
            }
        }
        .onChange(of: onlyPending) { camera = .automatic; selection = nil }
    }
}

struct MacAnalyticsView: View {
    @EnvironmentObject private var store: MacStore
    @EnvironmentObject private var navigation: MacNavigation
    @State private var period = "30 días"
    @State private var start = Calendar.current.date(byAdding: .day, value: -29, to: Date())!
    @State private var end = Date()
    @State private var selectedDate: Date?
    @State private var monthlyTarget = 500.0
    @AppStorage("reviewNfcGo.analytics.monthlyTarget") private var savedTarget = 500.0
    private var report: FinanceReport { FinanceReport(money: store.money, records: store.records, start: start, end: end) }
    var body: some View {
        let data = report
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Análisis de tu negocio").font(.largeTitle.bold())
                        Text(data.label).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Menu {
                        Button("Informe PDF…") { MacFinanceExport.save(data, owner: store.owner ?? "", pdf: true, store: store) }
                        Button("Operaciones del periodo en CSV…") { MacFinanceExport.save(data, owner: store.owner ?? "", pdf: false, store: store) }
                    } label: { Label("Exportar informe", systemImage: "square.and.arrow.up") }
                }
                HStack(spacing: 18) {
                    Picker("Periodo", selection: $period) {
                        ForEach(["7 días", "30 días", "90 días", "Este año", "Personalizado"], id: \.self) { Text($0) }
                    }.pickerStyle(.segmented).frame(maxWidth: 620)
                    Spacer(minLength: 0)
                }
                if period == "Personalizado" {
                    HStack {
                        DatePicker("Desde", selection: $start, in: ...end, displayedComponents: .date)
                        DatePicker("Hasta", selection: $end, in: start...Date(), displayedComponents: .date)
                        Spacer()
                    }
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 14)], spacing: 14) {
                    comparison("Ingresos netos", data.totals.income, data.previousTotals.income, color: .blue)
                    comparison("Gastos netos", data.totals.expenses, data.previousTotals.expenses, color: .orange)
                    comparison("Resultado de caja", data.totals.result, data.previousTotals.result, color: data.totals.result < 0 ? .red : .primary)
                    MacCard(title: "Tarjetas vendidas") {
                        Text(String(data.cards)).font(.system(size: 28, weight: .semibold, design: .rounded)).monospacedDigit()
                        Text("\(data.businesses.count) negocios con movimientos").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Text("Comparación con el periodo anterior de igual duración. Los ajustes de venta y las devoluciones se descuentan; el resultado de caja no equivale al beneficio contable.")
                    .font(.caption).foregroundStyle(.secondary)
                MacCard(title: "Ingresos frente a gastos") {
                    if data.transactions.isEmpty { noData }
                    else {
                        Chart {
                            ForEach(data.points) { point in
                                BarMark(x: .value("Fecha", point.date, unit: data.granularity), y: .value("Euros", Double(point.income) / 100))
                                    .foregroundStyle(by: .value("Tipo", "Ingresos")).position(by: .value("Tipo", "Ingresos"))
                                BarMark(x: .value("Fecha", point.date, unit: data.granularity), y: .value("Euros", Double(point.expenses) / 100))
                                    .foregroundStyle(by: .value("Tipo", "Gastos")).position(by: .value("Tipo", "Gastos"))
                            }
                            if let point = selectedPoint(data) { RuleMark(x: .value("Fecha seleccionada", point.date)).foregroundStyle(.secondary.opacity(0.4)) }
                        }
                        .chartForegroundStyleScale(["Ingresos": Color.blue, "Gastos": Color.orange])
                        .chartXSelection(value: $selectedDate)
                        .frame(height: 260)
                        if let point = selectedPoint(data) {
                            Text(point.date.formatted(date: .abbreviated, time: .omitted) + " · Ingresos " + euro(point.income) + " · Gastos " + euro(point.expenses))
                                .font(.callout).monospacedDigit()
                        } else { Text("Selecciona un punto de la gráfica para ver sus importes.").font(.caption).foregroundStyle(.secondary) }
                    }
                }
                MacCard(title: "Evolución del saldo disponible") {
                    if data.transactions.isEmpty { noData }
                    else {
                        Chart(data.points) { point in
                            LineMark(x: .value("Fecha", point.date), y: .value("Saldo EUR", Double(point.balance) / 100)).foregroundStyle(Color.blue)
                        }.frame(height: 190)
                        HStack { Text("Inicial: " + euro(data.openingBalance)); Spacer(); Text("Final: " + euro(data.closingBalance)) }
                            .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                    }
                }
                HStack(alignment: .top, spacing: 18) {
                    MacCard(title: "Dónde se va el dinero") {
                        if data.categories.isEmpty { Text("No hay gastos en este periodo.").foregroundStyle(.secondary) }
                        if !data.positiveCategories.isEmpty {
                            Chart(data.positiveCategories) { category in
                                SectorMark(angle: .value("Gasto EUR", Double(category.cents) / 100), innerRadius: .ratio(0.65), angularInset: 2)
                                    .foregroundStyle(by: .value("Categoría", category.title)).cornerRadius(3)
                            }.frame(height: 220)
                        }
                        ForEach(data.categories) { category in
                            HStack { Text(category.title); Spacer(); Text(euro(category.cents)).monospacedDigit() }.font(.callout)
                        }
                        Text("El gráfico muestra categorías con gasto neto positivo. Las devoluciones también aparecen en sus totales.").font(.caption).foregroundStyle(.secondary)
                    }
                    MacCard(title: "Negocios que más aportan") {
                        if data.businesses.isEmpty { Text("Todavía no hay ingresos de negocios en este periodo.").foregroundStyle(.secondary) }
                        ForEach(data.businesses.prefix(8)) { business in
                            Button {
                                if store.records.contains(where: { $0.id == business.id }) { navigation.openBusiness(business.id, store: store) }
                                else { navigation.sheet = .transaction(business.lastTransactionID) }
                            } label: {
                                HStack(alignment: .top) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(business.title).font(.headline).foregroundStyle(.primary).lineLimit(2)
                                        Text("\(business.cards) tarjetas").font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer(minLength: 10)
                                    Text(euro(business.cents)).monospacedDigit().foregroundStyle(.primary)
                                }.padding(.vertical, 4).contentShape(Rectangle())
                            }.buttonStyle(.plain)
                        }
                        if data.businesses.count > 8 { Text("Y \(data.businesses.count - 8) negocios más.").font(.caption).foregroundStyle(.secondary) }
                    }
                }
                targetCard
                MacCard(title: "El inventario también es dinero") {
                    let known = store.money.products.filter { store.money.averageCostCents($0.id) != nil }
                    let estimate = known.reduce(0.0) { $0 + Double(max(0, store.money.stock($1.id))) * (store.money.averageCostCents($1.id) ?? 0) }
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Valor estimado de existencias").foregroundStyle(.secondary)
                            Text(estimate / 100, format: .currency(code: "EUR").locale(Locale(identifier: "es_ES"))).font(.title2.bold())
                            Text("Coste medio de compra de las unidades disponibles. Los productos sin coste conocido no se incluyen.").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Revisar inventario") { navigation.section = .inventory }
                    }
                }
            }.padding(28)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onChange(of: period) { _, value in choosePeriod(value) }
        .onChange(of: start) { _, _ in selectedDate = nil }
        .onChange(of: end) { _, _ in selectedDate = nil }
        .onAppear { monthlyTarget = savedTarget }
    }
    private var noData: some View {
        Text("No hay operaciones en este periodo. Prueba otras fechas o registra una venta o un gasto.").foregroundStyle(.secondary).frame(maxWidth: .infinity, minHeight: 140, alignment: .center)
    }
    private func selectedPoint(_ report: FinanceReport) -> FinancePoint? {
        guard let selectedDate else { return nil }
        return report.points.min { abs($0.date.timeIntervalSince(selectedDate)) < abs($1.date.timeIntervalSince(selectedDate)) }
    }
    private func comparison(_ title: String, _ value: Int64, _ previous: Int64, color: Color) -> some View {
        MacCard(title: title) {
            Text(euro(value)).font(.system(size: 27, weight: .semibold, design: .rounded)).monospacedDigit().foregroundStyle(color).lineLimit(1).minimumScaleFactor(0.7)
            Text((value - previous >= 0 ? "+" : "") + euro(value - previous) + " frente al periodo anterior")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
    private func choosePeriod(_ value: String) {
        guard value != "Personalizado" else { return }
        end = Date()
        start = value == "Este año" ? Calendar.current.dateInterval(of: .year, for: end)!.start : Calendar.current.date(byAdding: .day, value: value == "7 días" ? -6 : value == "90 días" ? -89 : -29, to: end)!
        selectedDate = nil
    }
    private var targetCard: some View {
        let first = Calendar.current.dateInterval(of: .month, for: Date())!.start
        let month = FinanceReport(money: store.money, records: store.records, start: first, end: Date())
        let target = max(0, savedTarget)
        let progress = target > 0 ? min(1, max(0, Double(month.totals.income) / 100 / target)) : 0
        return MacCard(title: "Tu objetivo de ingresos de este mes") {
            HStack {
                Text(euro(month.totals.income) + " de " + euro(MoneyLedger.cents(target) ?? 0)).font(.headline)
                Spacer()
                TextField("Objetivo EUR", value: $monthlyTarget, format: .number).textFieldStyle(.roundedBorder).frame(width: 115)
                Text("€")
                Button("Guardar objetivo") { savedTarget = monthlyTarget }.disabled(!monthlyTarget.isFinite || monthlyTarget < 0 || monthlyTarget > 10_000_000)
            }
            if target > 0 { ProgressView(value: progress).accessibilityLabel("Progreso del objetivo de ingresos") }
            Text(target == 0 ? "Guarda un importe mayor que cero para activar el objetivo." : "\(Int(progress * 100)) % completado · Se calcula con ingresos netos del mes actual.").font(.caption).foregroundStyle(.secondary)
        }
    }
}
