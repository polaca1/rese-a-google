import SwiftUI

struct AlertHistoryView: View {
    @ObservedObject private var history = AlertHistoryStore.shared
    @State private var filter = HistoryFilter.all

    private enum HistoryFilter: String, CaseIterable {
        case all = "Todo", notifications = "Avisos", activities = "Live Activities"
    }

    private var entries: [AlertHistoryEntry] {
        history.ledger.entries.filter {
            filter == .all || (filter == .activities ? $0.kind == .liveActivity : $0.kind != .liveActivity)
        }.sorted { $0.lastEventDate > $1.lastEventDate }
    }

    var body: some View {
        List {
            Section {
                Picker("Mostrar", selection: $filter) {
                    ForEach(HistoryFilter.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
            } footer: {
                Text("El historial se guarda en este iPhone desde esta versión. «Enviada» indica una entrega confirmada por iOS; «Entrega sin confirmar» indica que pasó la hora prevista y iOS ya no conserva el aviso.")
            }
            if entries.isEmpty {
                Section {
                    VStack(spacing: 10) {
                        Image(systemName: "bell.and.waves.left.and.right").font(.largeTitle).foregroundStyle(.secondary)
                        Text("Sin registros todavía").font(.headline)
                        Text("Aquí aparecerán tus recordatorios y Live Activities.")
                            .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 32)
                }
            } else {
                Section("Registro") {
                    ForEach(entries) { entry in
                        NavigationLink(destination: AlertHistoryDetailView(entryID: entry.id)) {
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: entry.kind.symbol).foregroundStyle(AppTheme.blue).frame(width: 24)
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(entry.businessName ?? entry.title).font(.headline)
                                    Text(entry.kind.title).font(.subheadline).foregroundStyle(.secondary)
                                    HStack {
                                        Text(entry.statusTitle).font(.caption.weight(.semibold)).foregroundStyle(entry.status.historyColor)
                                        Spacer()
                                        Text(entry.lastEventDate, format: .dateTime.day().month().hour().minute())
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
        }
        .navigationTitle("Historial de avisos")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { history.refresh() }
        .refreshable { history.refresh() }
    }
}

struct AlertHistoryDetailView: View {
    @ObservedObject private var history = AlertHistoryStore.shared
    @EnvironmentObject private var store: AppStore
    let entryID: UUID
    private var entry: AlertHistoryEntry? { history.ledger.entries.first { $0.id == entryID } }

    var body: some View {
        List {
            if let entry {
                Section(entry.kind.title) {
                    Text(entry.title).font(.headline)
                    if !entry.body.isEmpty { Text(entry.body).foregroundStyle(.secondary) }
                    LabeledContent("Estado") {
                        Text(entry.statusTitle).foregroundStyle(entry.status.historyColor)
                    }
                    LabeledContent("Hora prevista", value: entry.scheduledDate.formatted(date: .abbreviated, time: .shortened))
                }
                if let recordID = entry.recordID {
                    Section("Negocio") {
                        if store.records.contains(where: { $0.id == recordID }) {
                            NavigationLink(destination: RecordDetailView(recordID: recordID)) {
                                Label("Abrir ficha de \(entry.businessName ?? "negocio")", systemImage: "building.2")
                            }
                        } else {
                            Text(entry.businessName ?? "Negocio eliminado")
                            Text("La ficha se ha eliminado. Su historial se conserva.")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                }
                Section("Registro de estados") {
                    ForEach(entry.events.sorted { $0.date > $1.date }) { event in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(entry.kind == .liveActivity && event.status == .delivered ? "Activación confirmada" : event.status.title)
                                .foregroundStyle(event.status.historyColor)
                            Text(event.date, format: .dateTime.day().month().year().hour().minute().second())
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            } else {
                Text("Este registro ya no está disponible.")
            }
        }
        .navigationTitle("Detalle del aviso")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private extension AlertHistoryStatus {
    var historyColor: Color {
        switch self {
        case .delivered, .opened: return .green
        case .failed: return .red
        case .unconfirmed: return .orange
        case .scheduled: return AppTheme.blue
        case .finished, .cancelled: return .secondary
        }
    }
}
