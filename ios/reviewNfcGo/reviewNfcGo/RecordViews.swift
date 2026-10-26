import SwiftUI
import MapKit
import CoreLocation
import UserNotifications
import UIKit
import ActivityKit

// MARK: - History / record editor

struct HistoryView: View {
    @EnvironmentObject var store: AppStore
    @State private var filter = ClientDirectoryFilter.all
    @State private var query = ""
    private var rows: [VisitRecord] {
        store.records.filter { record in
            filter.matches(record, income: store.money.businessIncome(record.id), cards: store.money.businessCards(record.id)) &&
            (query.isEmpty || (record.place.name + " " + record.place.address + " " + (record.contactName ?? "")).localizedStandardContains(query))
        }
    }
    var body: some View {
        List {
            Section {
                Picker("Mostrar", selection: $filter) {
                    ForEach(ClientDirectoryFilter.allCases) { Text($0.rawValue).tag($0) }
                }.pickerStyle(.segmented)
            }.listRowBackground(Color.clear)
            NavigationLink { BusinessHubView() } label: { Label("Actividad y seguimiento", systemImage: "person.2") }
            NavigationLink { ManagedCardsListView() } label: { Label("Mis tarjetas y estadísticas", systemImage: "chart.bar.xaxis") }
            if rows.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: filter == .customers ? "person.2" : "building.2.crop.circle").font(.system(size: 42)).foregroundStyle(.secondary)
                    Text(store.records.isEmpty ? "Todavía no has guardado ningún sitio" : query.isEmpty ? (filter == .customers ? "Aún no hay clientes con compras" : "Sin visitas registradas o previstas") : "Sin coincidencias").font(.headline)
                    Text(store.records.isEmpty ? "Guarda un negocio desde Inicio para preparar su tarjeta." : "Los clientes aparecen aquí cuando registras una venta.")
                        .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }.frame(maxWidth: .infinity).padding(.vertical, 45).listRowBackground(Color.clear)
            } else {
                ForEach(rows) { record in
                    NavigationLink(value: record.id) {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(record.place.name).font(.headline)
                            Text(record.place.address).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            HStack {
                                let customer = store.money.businessIncome(record.id) > 0 || store.money.businessCards(record.id) > 0
                                Text(customer ? "Cliente" : record.trackingStage.rawValue).font(.caption.weight(.semibold)).foregroundStyle(customer ? .green : AppTheme.blue)
                                Spacer()
                                if store.money.businessIncome(record.id) > 0 {
                                    Text(Double(store.money.businessIncome(record.id)) / 100, format: .currency(code: "EUR")).font(.subheadline.bold())
                                }
                            }
                            HStack(spacing: 12) {
                                Label("\(CardLinkRules.visits(record).count) visitas", systemImage: "calendar")
                                if !CardLinkRules.confirmedWrites(record).isEmpty { Label("NFC registrado", systemImage: "wave.3.right") }
                                if record.reviewLinkActive == false { Image(systemName: "pause.circle").accessibilityLabel("Enlace en pausa") }
                            }.font(.caption2).foregroundStyle(.secondary)
                        }.padding(.vertical, 4)
                    }
                }.onDelete { offsets in
                    let ids = Set(offsets.map { rows[$0].id })
                    store.delete(at: IndexSet(store.records.indices.filter { ids.contains(store.records[$0].id) }))
                }
            }
        }
        .navigationTitle("Sitios y clientes")
        #if DEBUG
        .onAppear { if ProcessInfo.processInfo.arguments.contains("--verification-customers") { filter = .customers } }
        #endif
        .searchable(text: $query, prompt: "Buscar negocio o cliente")
        .toolbar { ToolbarItem(placement: .primaryAction) { NavigationLink { WorkspaceRouteView() } label: { Image(systemName: "point.topleft.down.to.point.bottomright.curvepath") }.accessibilityLabel("Ruta del día") } }
    }
}

struct RecordDetailView: View {
    @EnvironmentObject var store: AppStore
    let recordID: UUID
    @State private var showWriter = false
    #if DEBUG
    @State private var verificationEditorPresented = false
    #endif

    private var record: VisitRecord? { store.records.first(where: { $0.id == recordID }) }

    var body: some View {
        Group {
            if let record {
                ScrollView {
                    VStack(spacing: 16) {
                        NavigationLink { QuickSaleView(initialBusinessID: recordID) } label: { Label("Registrar venta", systemImage: "plus.circle.fill").frame(maxWidth: .infinity) }.buttonStyle(.borderedProminent)
                        NavigationLink("Seguimiento e historial") { ClientTimelineView(recordID: recordID) }
                        NavigationLink("Visitas al cliente") { ClientVisitsView(recordID: recordID) }
                        VStack(alignment: .leading, spacing: 10) {
                            Label("Tarjeta del cliente", systemImage: "wave.3.right").font(.headline)
                            if let written = CardLinkRules.confirmedWrites(record).first {
                                Text(written.writtenURL).font(.caption).textSelection(.enabled)
                                Text("Escritura confirmada: " + (written.confirmedAt ?? written.date).formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary)
                            } else { Text("Todavía no hay una escritura confirmada.").font(.footnote).foregroundStyle(.secondary) }
                            if let id = record.reviewLinkID {
                                Text("Destino: " + (record.reviewLinkTarget ?? record.place.reviewURL)).font(.footnote).foregroundStyle(.secondary)
                                if record.reviewLinkActive == false { Label("Enlace en pausa", systemImage: "pause.circle").foregroundStyle(.orange) }
                                Text(ReviewLinkAddress.permanent(id)).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                            }
                            NavigationLink("Tarjeta, estadísticas y destino") { EditableReviewLinkView(recordID: recordID) }
                            NavigationLink("Ver escrituras NFC") { CardWritingHistoryView(recordID: recordID) }
                        }.frame(maxWidth: .infinity, alignment: .leading).padding(18).background(AppTheme.card, in: RoundedRectangle(cornerRadius: 20))
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(alignment: .top) {
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(record.place.name).font(.title2.bold())
                                    Text(record.place.address).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(record.trackingStage.rawValue)
                                    .font(.caption.bold())
                                    .padding(.horizontal, 10).padding(.vertical, 6)
                                    .background(record.status == .completed ? Color.green.opacity(0.14) : AppTheme.softBlue)
                                    .foregroundStyle(record.status == .completed ? .green : AppTheme.blue)
                                    .clipShape(Capsule())
                            }
                            if !record.notes.isEmpty {
                                Divider()
                                Label(record.notes, systemImage: "note.text")
                                    .font(.subheadline)
                            }
                            if store.money.businessCards(record.id) > 0 {
                                Divider()
                                LabeledContent("Tarjetas vendidas", value: "\(store.money.businessCards(record.id))")
                            }
                            if record.cardsSold > 0 {
                                LabeledContent("Ganancia por tarjeta") {
                                    Text(record.earningsPerCard, format: .currency(code: "EUR"))
                                }
                            }
                            if let profit = store.money.businessProfit(record.id), store.money.businessIncome(record.id) > 0 {
                                LabeledContent("Beneficio de ventas") { Text(Double(profit) / 100, format: .currency(code: "EUR")).bold() }
                                Text("Ingreso menos coste de los productos vendidos.").font(.caption).foregroundStyle(.secondary)
                            }
                            if let arrived = record.arrivedAt { Label("Llegada: " + arrived.formatted(date: .abbreviated, time: .shortened), systemImage: "checkmark.circle") }
                            if store.money.businessIncome(record.id) > 0 {
                                Divider()
                                LabeledContent("Ingresos totales") {
                                    Text(Double(store.money.businessIncome(record.id)) / 100, format: .currency(code: "EUR")).bold()
                                }
                            }
                        }
                        .padding(18)
                        .background(Color(uiColor: .systemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))

                        if let visit = record.reminderDate, record.status != .completed, record.arrivedAt == nil {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("PRÓXIMA VISITA").font(.caption.bold()).foregroundStyle(.secondary)
                                Label(visit.formatted(date: .long, time: .shortened), systemImage: "calendar")
                                    .font(.headline)
                                if let notify = record.notificationDate ?? record.reminderDate {
                                    Label("Aviso: \(notify.formatted(date: .abbreviated, time: .shortened))", systemImage: "bell.fill")
                                        .foregroundStyle(AppTheme.blue)
                                }
                                TimelineView(.periodic(from: .now, by: 1)) { context in
                                    if visit > context.date {
                                        HStack {
                                            Image(systemName: "timer")
                                            Text("Quedan \(Self.remainingString(from: context.date, to: visit))")
                                                .font(.headline.monospacedDigit())
                                        }
                                    } else {
                                        Text("La hora prevista ya ha llegado").foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(18)
                            .background(Color(uiColor: .systemBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                        }

                        VStack(spacing: 10) {
                            Button {
                                showWriter = true
                            } label: {
                                Label("Escribir NFC", systemImage: "wave.3.right")
                                    .frame(maxWidth: .infinity)
                            }
                            .appPrimaryButton()

                            Button {
                                UIPasteboard.general.string = record.reviewLinkID.map(ReviewLinkAddress.permanent) ?? record.place.reviewURL
                            } label: {
                                Label(record.reviewLinkID == nil ? "Copiar enlace de reseña" : "Copiar enlace de tarjeta", systemImage: "doc.on.doc")
                                    .frame(maxWidth: .infinity)
                            }
                            .appSecondaryButton()
                        }

                        VStack(alignment: .leading, spacing: 10) {
                            Text("UBICACIÓN").font(.caption.bold()).foregroundStyle(.secondary)
                            ZStack {
                                PlaceMiniMap(place: record.place).allowsHitTesting(false)
                                Button { MapLauncher.openAppleMaps(place: record.place) } label: {
                                    Color.clear.contentShape(Rectangle())
                                }.buttonStyle(.plain)
                            }
                            .frame(height: 210)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            HStack(spacing: 10) {
                                Button { MapLauncher.openAppleMaps(place: record.place) } label: {
                                    Label("Apple Maps", systemImage: "map.fill").frame(maxWidth: .infinity)
                                }.appSecondaryButton()
                                Button { MapLauncher.openGoogleMaps(place: record.place) } label: {
                                    Label("Google Maps", systemImage: "location.fill").frame(maxWidth: .infinity)
                                }.appSecondaryButton()
                            }
                        }
                        .padding(18)
                        .background(Color(uiColor: .systemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    }
                    .padding(16)
                }
                .background(AppTheme.background)
                .navigationTitle("Ficha")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        NavigationLink("Editar", destination: RecordEditView(recordID: recordID)).bold()
                    }
                }
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "building.2").font(.system(size: 42)).foregroundStyle(.secondary)
                    Text("Sitio no encontrado").font(.headline)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .sheet(isPresented: $showWriter) { NavigationStack { NFCCardWriteView(recordID: recordID) } }
        #if DEBUG
        .navigationDestination(isPresented: $verificationEditorPresented) {
            RecordEditView(recordID: recordID)
        }
        .onAppear {
            if ProcessInfo.processInfo.arguments.contains("--verification-editor") { verificationEditorPresented = true }
        }
        #endif
    }

    private static func remainingString(from: Date, to: Date) -> String {
        let seconds = max(0, Int(to.timeIntervalSince(from)))
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        let s = seconds % 60
        return h > 0 ? String(format: "%02d:%02d:%02d", h, m, s) : String(format: "%02d:%02d", m, s)
    }
}

struct RecordEditView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    let recordID: UUID

    @State private var original: VisitRecord?
    @State private var draft: VisitRecord?
    @State private var reminderEnabled = false
    @State private var unitEarningsText = ""
    @State private var showDiscardAlert = false
    @FocusState private var focusedField: EditorField?

    enum EditorField: Hashable { case notes, earnings }
    private var isSold: Bool { draft?.status == .completed }
    private var minimumDate: Date { Date().addingTimeInterval(5) }

    private var hasChanges: Bool {
        guard var draft, let original else { return false }
        guard let amount = parsedUnitEarnings else { return true }
        draft.earnings = calculatedTotal ?? 0
        if unitPriceChanged { draft.unitEarnings = amount }
        if !reminderEnabled || draft.status == .completed {
            draft.reminderDate = nil
            draft.notificationDate = nil
        }
        return draft != original
    }

    private var parsedUnitEarnings: Double? { SaleAmountFormatting.parse(unitEarningsText) }

    private var unitPriceChanged: Bool {
        guard let original, let draft else { return true }
        return unitEarningsText != (original.earningsPerCard == 0 ? "" : SaleAmountFormatting.text(for: original.earningsPerCard)) || draft.cardsSold != original.cardsSold
    }
    private var calculatedTotal: Double? {
        guard let draft, let amount = parsedUnitEarnings else { return nil }
        if !unitPriceChanged, let original { return original.earnings }
        return VisitRecord.totalEarnings(perCard: amount, count: draft.cardsSold)
    }
    private var earningsAreValid: Bool {
        guard draft != nil, let amount = parsedUnitEarnings, let total = calculatedTotal else { return false }
        return amount <= VisitRecord.maximumEarningsPerCard && MoneyLedger.cents(total) != nil && store.money.canAssign(draft!)
    }

    var body: some View {
        Form {
            if draft != nil {
                let binding = Binding<VisitRecord>(get: { draft! }, set: { draft = $0 })
                Section("Negocio") {
                    Text(binding.wrappedValue.place.name).font(.headline)
                    Text(binding.wrappedValue.place.address).foregroundStyle(.secondary)
                }
                Section("Seguimiento") {
                    Picker("Estado", selection: binding.status) {
                        Text("Contactado").tag(VisitStatus.contacted)
                        Text("Volver").tag(VisitStatus.pending)
                        Text("Vendido").tag(VisitStatus.completed)
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: binding.wrappedValue.status) { status in
                        if status == .completed {
                            draft?.cardsSold = max(draft?.hasQuickSales == true ? 0 : 1, draft?.cardsSold ?? 0)
                            reminderEnabled = false
                            draft?.reminderDate = nil
                            draft?.notificationDate = nil
                        }
                    }
                    TextField("Notas", text: binding.notes, axis: .vertical).lineLimit(3...7).focused($focusedField, equals: .notes)
                }
                Section {
                    Stepper(value: binding.cardsSold, in: (isSold && draft?.hasQuickSales != true ? 1 : 0)...max(100_000, original?.cardsSold ?? 0)) {
                        LabeledContent("Tarjetas vendidas", value: "\(binding.wrappedValue.cardsSold)")
                    }
                    if !store.money.products.filter({ $0.kind == .nfcCard }).isEmpty {
                        Picker("Tarjeta / color", selection: binding.inventoryProductID) {
                            Text("Sin asignar inventario").tag(UUID?.none)
                            ForEach(store.money.products.filter { $0.kind == .nfcCard }) { product in
                                Text("\(product.displayName) (\(store.money.stock(product.id)) disponibles)").tag(Optional(product.id))
                            }
                        }
                        if !store.money.canAssign(binding.wrappedValue) {
                            Text("No hay suficientes tarjetas de este color. Registra la compra en Dinero o revisa la cantidad.").font(.footnote).foregroundStyle(.red)
                        }
                    }
                    HStack {
                        Text("Ganancia por tarjeta"); Spacer()
                        TextField("0,00", text: $unitEarningsText).keyboardType(.decimalPad).multilineTextAlignment(.trailing).focused($focusedField, equals: .earnings).frame(maxWidth: 110)
                        Text("€").foregroundStyle(.secondary)
                    }
                    LabeledContent("Ganancia total") {
                        Text(calculatedTotal ?? 0, format: .currency(code: "EUR")).bold()
                    }
                    LabeledContent("Máximo por tarjeta", value: "50,00 €")
                    if let original, let amount = parsedUnitEarnings,
                       original.unitEarnings == nil, !unitPriceChanged,
                       VisitRecord.totalEarnings(perCard: amount, count: original.cardsSold) != original.earnings {
                        Text("Total de una venta anterior conservado. Cambiar el precio o la cantidad de tarjetas recalcula el total.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    if !earningsAreValid {
                        Text("Introduce una ganancia por tarjeta entre 0 € y 50 €.")
                            .font(.footnote).foregroundStyle(.red)
                    }
                } header: {
                    Text(draft?.hasQuickSales == true ? "Ventas anteriores de tarjetas" : "Venta de tarjetas")
                } footer: {
                    Text("Ganancia total = tarjetas vendidas × ganancia por tarjeta. Máximo de 50 € por tarjeta.")
                }
                Section("Recordatorio") {
                    Toggle("Volver otro día", isOn: $reminderEnabled)
                        .disabled(isSold)
                        .onChange(of: reminderEnabled) { enabled in
                            if enabled && draft?.reminderDate == nil {
                                let visit = Date().addingTimeInterval(3600)
                                draft?.reminderDate = visit
                                draft?.notificationDate = Date().addingTimeInterval(1800)
                            }
                            if !enabled {
                                draft?.reminderDate = nil
                                draft?.notificationDate = nil
                            }
                        }
                    if isSold {
                        Text("Este negocio está marcado como vendido; sus avisos quedan cancelados.").font(.footnote).foregroundStyle(.secondary)
                    } else if reminderEnabled {
                        InlineDateTimePicker("Fecha y hora de la visita", selection: Binding(
                            get: { max(draft?.reminderDate ?? Date().addingTimeInterval(3600), minimumDate) },
                            set: { newValue in
                                draft?.reminderDate = newValue
                                if let n = draft?.notificationDate, n > newValue { draft?.notificationDate = newValue }
                            }
                        ), in: minimumDate...)
                        if let visit = draft?.reminderDate {
                            InlineDateTimePicker("Avisarme el", selection: Binding(
                                get: { max(min(draft?.notificationDate ?? visit, visit), minimumDate) },
                                set: { draft?.notificationDate = $0 }
                            ), in: minimumDate...max(visit, minimumDate))
                        }
                        Text("No se pueden guardar fechas pasadas. El aviso puede ser anterior a la visita.").font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("Editar")
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button { focusedField = nil; attemptDismiss() } label: { Label("Atrás", systemImage: "chevron.left") }
            }
            ToolbarItem(id: "save-business-record", placement: .confirmationAction) {
                Button("Guardar") { saveAndDismiss() }.appConfirmationButton().disabled(!earningsAreValid)
            }
            ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("OK") { focusedField = nil } }
        }
        .onAppear {
            if let value = store.records.first(where: { $0.id == recordID }) {
                original = value; draft = value
                reminderEnabled = value.reminderDate != nil && value.status != .completed
                unitEarningsText = value.earningsPerCard == 0 ? "" : SaleAmountFormatting.text(for: value.earningsPerCard)
                if value.notificationDate == nil { draft?.notificationDate = value.reminderDate }
                #if DEBUG
                if ProcessInfo.processInfo.arguments.contains("--verification-unit-calculation") { verifyUnitEarningsEditor() }
                #endif
            }
        }
        .alert("¿Descartar cambios?", isPresented: $showDiscardAlert) {
            Button("Seguir editando", role: .cancel) {}
            Button("Descartar", role: .destructive) { dismiss() }
        } message: { Text("Los cambios que no hayas guardado se perderán.") }
    }

    #if DEBUG
    private func verifyUnitEarningsEditor() {
        let savedDraft = draft, savedText = unitEarningsText
        unitEarningsText = "20"
        draft?.cardsSold = 3
        let three = calculatedTotal == 60 && earningsAreValid
        draft?.cardsSold = 5
        let five = calculatedTotal == 100 && earningsAreValid
        draft?.cardsSold = 1
        let one = calculatedTotal == 20 && earningsAreValid
        unitEarningsText = "51"
        let cap = !earningsAreValid
        draft = savedDraft; unitEarningsText = savedText
        let unchanged = !hasChanges
        let output = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("unit-earnings-verification.json")
        try? JSONSerialization.data(withJSONObject: ["passed": three && five && one && cap && unchanged,
            "threeCards": three, "fiveCards": five, "oneCard": one, "cap": cap, "unchanged": unchanged], options: .prettyPrinted).write(to: output)
    }
    #endif

    private func attemptDismiss() { if hasChanges { showDiscardAlert = true } else { dismiss() } }

    private func saveAndDismiss() {
        focusedField = nil
        guard earningsAreValid, var value = draft, let amount = parsedUnitEarnings else { return }
        value.earnings = calculatedTotal ?? 0
        if unitPriceChanged { value.unitEarnings = amount }
        value.normalizeSales()
        if value.status == .completed || !reminderEnabled {
            value.reminderDate = nil; value.notificationDate = nil
        } else {
            if value.reminderDate == nil || value.reminderDate! <= Date() { value.reminderDate = Date().addingTimeInterval(3600) }
            if value.notificationDate == nil || value.notificationDate! <= Date() { value.notificationDate = min(Date().addingTimeInterval(60), value.reminderDate!) }
            if value.notificationDate! > value.reminderDate! { value.notificationDate = value.reminderDate }
        }
        guard store.update(value) else { return }
        original = value; draft = value; dismiss()
    }


}
