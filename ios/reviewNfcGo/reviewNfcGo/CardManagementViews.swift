import SwiftUI
import Charts
#if os(iOS)
import UIKit
#endif

@MainActor private func cardWorkspaceOwner(_ store: WorkspaceStore) -> String? {
    #if os(iOS)
    return store.loadedUserEmail
    #else
    return store.owner
    #endif
}

struct EditableReviewLinkView: View {
    @EnvironmentObject private var store: WorkspaceStore
    #if os(iOS)
    @EnvironmentObject private var auth: AuthStore
    private var account: RemoteAuthClient { auth.accountService }
    #else
    @ObservedObject private var account = RemoteAuthClient.shared
    #endif
    let recordID: UUID
    @State private var link: ManagedReviewLink?
    @State private var statistics: CardStatistics?
    @State private var target = ""
    @State private var active = true
    @State private var busy = false
    @State private var message: String?
    @State private var statsError: String?
    @State private var showWriter = false
    @FocusState private var targetFocused: Bool
    private var record: VisitRecord? { store.records.first { $0.id == recordID } }
    private var destination: String { target.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var changed: Bool { link.map { $0.target_url != destination || $0.active != active } ?? false }
    private var valid: Bool { link.map { CardLinkRules.validTarget(destination, linkID: $0.id) } ?? false }
    private var taskKey: String { recordID.uuidString + (account.session?.user.id ?? "") }
    private var ownerMatches: Bool { account.session?.user.email != nil && account.session?.user.email == cardWorkspaceOwner(store) }
    private var fixtureMode: Bool {
        #if DEBUG
        return ProcessInfo.processInfo.arguments.contains("--verification-card-details")
        #else
        return false
        #endif
    }
    var body: some View {
        Form {
            if let record, ownerMatches || fixtureMode {
                Section {
                    Label(link?.active == false ? "Enlace en pausa" : "Enlace del cliente", systemImage: link?.active == false ? "pause.circle.fill" : "link.circle.fill")
                        .font(.headline).foregroundStyle(link?.active == false ? Color.orange : Color.blue)
                    Text(record.place.name).font(.subheadline).foregroundStyle(.secondary)
                    Text("El mismo enlace permanece en la tarjeta. Su destino se puede cambiar aunque el NFC esté bloqueado.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                if let link {
                    Section("Destino") {
                        TextField("Dirección HTTPS", text: $target, axis: .vertical).lineLimit(2...4)
                            .focused($targetFocused).autocorrectionDisabled()
                            #if os(iOS)
                            .textInputAutocapitalization(.never).keyboardType(.URL)
                            #endif
                        Button("Usar la reseña de Google del negocio") { target = record.place.reviewURL }
                        Toggle("Enlace activo", isOn: $active)
                        Button("Guardar cambios", action: save).buttonStyle(.borderedProminent)
                            .disabled(busy || !changed || !valid)
                        if changed { Text("Cambios pendientes de guardar.").font(.caption).foregroundStyle(.secondary) }
                        if let message { Text(message).font(.footnote).foregroundStyle(.secondary) }
                    }.disabled(busy)
                    Section("Aperturas del enlace") {
                        if let statistics { statisticsContent(statistics) }
                        else if let statsError {
                            Label(statsError, systemImage: "exclamationmark.circle").font(.footnote).foregroundStyle(.secondary)
                            Button("Reintentar") { Task { await refreshStats(link.id) } }.disabled(busy)
                        } else { ProgressView("Cargando estadísticas…") }
                        Text("Son aperturas del enlace, no personas únicas ni reseñas publicadas. Varias tarjetas con este enlace comparten el contador.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Section("Enlace escrito en el NFC") {
                        Text(link.permanentURL).font(.caption).textSelection(.enabled)
                        #if os(iOS)
                        Button("Escribir NFC") { showWriter = true }.buttonStyle(.borderedProminent)
                        Button("Copiar enlace de tarjeta") { UIPasteboard.general.string = link.permanentURL }
                        #else
                        Button("Copiar enlace de tarjeta") { MacFiles.copy(link.permanentURL) }
                        #endif
                        if let url = URL(string: link.target_url), link.active { Link("Probar destino sin contar una apertura", destination: url) }
                        NavigationLink("Escrituras registradas") { CardWritingHistoryView(recordID: recordID) }
                    }
                } else {
                    Section("Tu primera tarjeta") {
                        Text("Por defecto abrirá la reseña de Google de este negocio, usando su Place ID.")
                        Text(record.place.reviewURL).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                        Button("Preparar enlace del cliente") { Task { await create() } }.buttonStyle(.borderedProminent).disabled(busy)
                        if let message { Text(message).font(.footnote).foregroundStyle(.secondary) }
                    }
                }
                Section {
                    Text("Las etiquetas que ya contienen un enlace directo de Google necesitan regrabarse para usar un enlace actualizable. Si están bloqueadas, hay que usar otra etiqueta.")
                        .font(.caption).foregroundStyle(.secondary)
                    Text("Las estadísticas empiezan al activar el contador. El enlace necesita Internet para abrir su destino; tus ventas y datos de cuenta permanecen privados.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            } else { Text("Inicia sesión en la cuenta de este cliente para gestionar su tarjeta.") }
            if busy { ProgressView() }
        }
        .navigationTitle("Tarjeta y estadísticas")
        .toolbar {
            ToolbarItem(placement: .primaryAction) { Button("Guardar", action: save).disabled(busy || !changed || !valid) }
            #if os(iOS)
            ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("Hecho") { targetFocused = false } }
            #endif
        }
        .task(id: taskKey) {
            #if DEBUG
            if fixtureMode { prepareScreenshot(); return }
            #endif
            await load()
        }
        .refreshable { if !changed { await load() } }
        #if os(iOS)
        .scrollDismissesKeyboard(.interactively)
        .sheet(isPresented: $showWriter) { NavigationStack { NFCCardWriteView(recordID: recordID) } }
        #endif
    }
    @ViewBuilder private func statisticsContent(_ value: CardStatistics) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 90), alignment: .leading)], spacing: 12) {
            metric("Totales", value.total); metric("7 días", value.last_7_days); metric("30 días", value.last_30_days)
        }.padding(.vertical, 6)
        if value.total > 0 {
            Chart(value.daily.suffix(14)) { day in
                if let date = day.date { BarMark(x: .value("Día", date, unit: .day), y: .value("Aperturas", day.opens)).foregroundStyle(Color.blue.gradient) }
            }.frame(height: 160).chartXAxis { AxisMarks(values: .stride(by: .day, count: 7)) }
            Text("Últimos 14 días · recuento diario en UTC").font(.caption).foregroundStyle(.secondary)
            if let text = value.last_opened_at, let date = CardLinkDates.timestamp(text) {
                LabeledContent("Última apertura", value: date.formatted(date: .abbreviated, time: .shortened))
            }
        } else { Text("Aún no se ha registrado ninguna apertura.").foregroundStyle(.secondary) }
    }
    private func metric(_ title: String, _ value: Int64) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value.formatted()).font(.title2.bold()).monospacedDigit()
            Text(title).font(.caption).foregroundStyle(.secondary)
        }.accessibilityElement(children: .combine)
    }
    private func persist(_ value: ManagedReviewLink, owner: String, email: String) throws {
        guard account.session?.user.id == owner, cardWorkspaceOwner(store) == email,
              var current = record else { throw CancellationError() }
        let old = current; try current.applyManagedLink(value)
        if current != old { try store.saveClient(current) }
    }
    private func load() async {
        link = nil; statistics = nil; statsError = nil; message = nil
        guard let initial = record, let owner = account.session?.user.id, let email = account.session?.user.email, ownerMatches else { return }
        busy = true; defer { busy = false }
        do {
            guard let id = initial.reviewLinkID else { target = initial.place.reviewURL; return }
            if let value = try await account.managedReviewLink(id: id) {
                try persist(value, owner: owner, email: email); link = value; target = value.target_url; active = value.active
                await refreshStats(value.id)
            } else { target = initial.place.reviewURL }
        } catch is CancellationError { link = nil; statistics = nil }
        catch { message = error.localizedDescription }
    }
    private func create() async {
        guard let initial = record, let owner = account.session?.user.id, let email = account.session?.user.email, ownerMatches else { return }
        busy = true; message = nil; defer { busy = false }
        do {
            let value = try await account.ensureManagedReviewLink(for: initial)
            try persist(value, owner: owner, email: email); link = value; target = value.target_url; active = value.active
            await refreshStats(value.id)
        } catch { message = error.localizedDescription }
    }
    private func refreshStats(_ id: UUID) async {
        let owner = account.session?.user.id; statsError = nil
        do {
            let value = try await account.reviewLinkStatistics(id: id)
            guard owner == account.session?.user.id, ownerMatches, link?.id == id else { return }
            statistics = value
        } catch { statistics = nil; statsError = error.localizedDescription }
    }
    private func save() {
        guard let previous = link, let owner = account.session?.user.id, let email = account.session?.user.email, changed, valid, !busy else { return }
        let destination = destination, enabled = active
        targetFocused = false; busy = true; message = nil
        Task { @MainActor in
            defer { busy = false }
            do {
                let value = try await account.updateManagedReviewLink(previous, target: destination, active: enabled)
                try persist(value, owner: owner, email: email); link = value; target = value.target_url; active = value.active
                message = "Cambios guardados. Se aplican en la próxima apertura del enlace."
            } catch { message = error.localizedDescription }
        }
    }
    #if DEBUG
    private func prepareScreenshot() {
        guard var current = record else { return }
        let id = current.reviewLinkID ?? UUID()
        let value = ManagedReviewLink(id: id, user_id: "11111111-1111-4111-8111-111111111111", business_id: current.id,
                                      target_url: current.place.reviewURL, active: true, revision: 1,
                                      updated_at: ISO8601DateFormatter().string(from: Date()), label: current.place.name)
        try? current.applyManagedLink(value)
        if (current.nfcWrites ?? []).isEmpty {
            if let event = try? current.prepareCardWriting(link: value) { try? current.finishCardWriting(event.id, confirmed: true) }
        }
        try? store.saveClient(current)
        link = value; target = value.target_url; active = value.active
        let formatter = DateFormatter(); formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.timeZone = TimeZone(secondsFromGMT: 0); formatter.dateFormat = "yyyy-MM-dd"
        let days = (0..<14).map { index in CardOpeningDay(day: formatter.string(from: Calendar.current.date(byAdding: .day, value: index - 13, to: Date())!), opens: Int64(index % 4)) }
        let total = days.reduce(Int64(0)) { $0 + $1.opens }
        statistics = CardStatistics(link_id: id, total: total, last_7_days: days.suffix(7).reduce(0) { $0 + $1.opens }, last_30_days: total,
                                    last_opened_at: value.updated_at, first_recorded_day: days.first?.day, daily: days)
    }
    #endif
}

struct CardWritingHistoryView: View {
    @EnvironmentObject private var store: WorkspaceStore
    let recordID: UUID
    @State private var error: String?
    private var record: VisitRecord? { store.records.first { $0.id == recordID } }
    var body: some View {
        List {
            if let record {
                if (record.nfcWrites ?? []).isEmpty {
                    Text("Todavía no hay escrituras registradas para este cliente.").foregroundStyle(.secondary)
                }
                ForEach((record.nfcWrites ?? []).sorted { $0.date > $1.date }) { event in
                    Section {
                        Label(event.status == .confirmed ? "Escritura confirmada" : event.status == .cancelled ? "No escrita" : "Pendiente de confirmar",
                              systemImage: event.status == .confirmed ? "checkmark.circle.fill" : "wave.3.right")
                        Text((event.confirmedAt ?? event.date).formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary)
                        Text(event.writtenURL).font(.caption).textSelection(.enabled)
                        if event.status == .prepared {
                            Button("Confirmar que se escribió") { finish(event.id, confirmed: true) }
                            Button("No se escribió") { finish(event.id, confirmed: false) }
                        }
                    }
                }
                Section { Text("La confirmación la realizas tú después de usar el escritor NFC. Abrir el escritor no demuestra que la etiqueta se haya grabado.").font(.caption).foregroundStyle(.secondary) }
            }
        }.navigationTitle("Escrituras NFC")
            .alert("No se pudo actualizar", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) { Button("Aceptar") { error = nil } } message: { Text(error ?? "") }
    }
    private func finish(_ id: UUID, confirmed: Bool) {
        guard var value = record else { return }
        do { try value.finishCardWriting(id, confirmed: confirmed); try store.saveClient(value) }
        catch { self.error = error.localizedDescription }
    }
}

struct ClientVisitsView: View {
    @EnvironmentObject private var store: WorkspaceStore
    let recordID: UUID
    @State private var error: String?
    private var record: VisitRecord? { store.records.first { $0.id == recordID } }
    var body: some View {
        List {
            if let record {
                if let date = record.reminderDate, record.arrivedAt == nil {
                    Section("Visita prevista") { Label(date.formatted(date: .abbreviated, time: .shortened), systemImage: "calendar") }
                }
                Section {
                    Button("Registrar visita realizada") {
                        do { try store.updateTracking(recordID: recordID, stage: record.trackingStage, note: "", visited: true) }
                        catch { self.error = error.localizedDescription }
                    }
                }
                Section("Visitas realizadas") {
                    let visits = CardLinkRules.visits(record)
                    if visits.isEmpty { Text("Todavía no has registrado una visita.").foregroundStyle(.secondary) }
                    ForEach(visits) { visit in
                        VStack(alignment: .leading, spacing: 4) {
                            Label(visit.text, systemImage: "checkmark.circle")
                            Text(visit.date.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }.navigationTitle("Visitas al cliente")
            .alert("No se pudo registrar", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) { Button("Aceptar") { error = nil } } message: { Text(error ?? "") }
    }
}

#if os(iOS)
struct NFCCardWriteView: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var auth: AuthStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var phase
    let recordID: UUID
    @State private var link: ManagedReviewLink?
    @State private var eventID: UUID?
    @State private var busy = false
    @State private var launched = false
    @State private var leftApp = false
    @State private var confirm = false
    @State private var finished = false
    @State private var message: String?
    @State private var owner: String?
    private var record: VisitRecord? { store.records.first { $0.id == recordID } }
    var body: some View {
        Form {
            Section {
                Label(record?.place.name ?? "Tarjeta NFC", systemImage: "wave.3.right").font(.headline)
                Text("Tu etiqueta guardará un enlace fijo. Podrás cambiar su destino o desactivarlo desde Sitios, incluso si bloqueas la etiqueta.").font(.footnote).foregroundStyle(.secondary)
            }
            if busy { ProgressView("Preparando tarjeta…") }
            if let link {
                Section("Enlace de la tarjeta") {
                    Text(link.permanentURL).font(.caption).textSelection(.enabled)
                    Text("Destino: " + link.target_url).font(.footnote).foregroundStyle(.secondary)
                }
                if !link.active {
                    Section {
                        Text("Este enlace está desactivado.")
                        Button("Activar y escribir") { Task { await activateAndWrite(link) } }.buttonStyle(.borderedProminent).disabled(busy)
                    }
                }
            }
            if launched && !finished {
                Section("Después de escribir") {
                    Text("Comprueba el resultado del escritor NFC y confirma si se grabó la etiqueta.")
                    Button("Sí, la tarjeta se escribió") { finish(true) }.buttonStyle(.borderedProminent)
                    Button("No se escribió") { finish(false) }
                }
            }
            if let message {
                Section {
                    Text(message).font(.footnote)
                    if !launched { Button("Reintentar") { Task { await prepare() } }.disabled(busy) }
                }
            }
            if finished { Button("Listo") { dismiss() }.buttonStyle(.borderedProminent) }
        }
        .navigationTitle("Escribir NFC").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cerrar") { dismiss() } } }
        .task { await prepare() }
        .onChange(of: phase) { phase in
            if phase != .active && launched { leftApp = true }
            if phase == .active && leftApp && launched && !finished { leftApp = false; confirm = true }
        }
        .alert("¿La tarjeta se escribió correctamente?", isPresented: $confirm) {
            Button("Sí, escrita") { finish(true) }
            Button("No se escribió") { finish(false) }
            Button("Lo comprobaré después", role: .cancel) {}
        } message: { Text("Solo se registrará como escrita cuando lo confirmes.") }
    }
    private func current(_ expected: String) throws -> VisitRecord {
        guard auth.accountService.session?.user.id == expected,
              store.loadedUserEmail == auth.accountService.session?.user.email,
              let value = record else { throw CancellationError() }; return value
    }
    private func prepare() async {
        guard !busy, !launched, let initial = record, let owner = auth.accountService.session?.user.id else { return }
        self.owner = owner; busy = true; message = nil; defer { busy = false }
        do {
            let value = try await auth.accountService.ensureManagedReviewLink(for: initial)
            var latest = try current(owner); try latest.applyManagedLink(value)
            try store.saveClient(latest); link = value
            if value.active { try launch(value, owner: owner) }
        } catch is CancellationError { message = "La cuenta ha cambiado. Cierra esta pantalla y vuelve a intentarlo." }
        catch { message = error.localizedDescription }
    }
    private func launch(_ value: ManagedReviewLink, owner: String) throws {
        var latest = try current(owner)
        let event = try latest.prepareCardWriting(link: value)
        try store.saveClient(latest)
        eventID = event.id; launched = true
        ExternalNFCWriter.write(reviewURL: value.permanentURL)
    }
    private func activateAndWrite(_ previous: ManagedReviewLink) async {
        guard let owner, !busy else { return }
        busy = true; defer { busy = false }
        do {
            let value = try await auth.accountService.updateManagedReviewLink(previous, target: previous.target_url, active: true)
            link = value; try launch(value, owner: owner)
        } catch { message = error.localizedDescription }
    }
    private func finish(_ confirmed: Bool) {
        guard let owner, let eventID, !finished else { return }
        do {
            var latest = try current(owner); try latest.finishCardWriting(eventID, confirmed: confirmed)
            try store.saveClient(latest); finished = true
            message = confirmed ? "Escritura registrada en la ficha del cliente." : "La preparación queda registrada sin marcarla como escrita."
        } catch { message = error.localizedDescription }
    }
}
#endif
