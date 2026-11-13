import Foundation

enum AlertHistoryKind: String, Codable, CaseIterable {
    case reminder, activityAlert, test, liveActivity, stock
    var title: String {
        switch self {
        case .stock: return "Stock de tarjetas"
        case .reminder: return "Recordatorio"
        case .activityAlert: return "Aviso de cuenta atrás"
        case .test: return "Notificación de prueba"
        case .liveActivity: return "Live Activity"
        }
    }
    var symbol: String { self == .liveActivity ? "timer" : "bell.fill" }
}

enum AlertHistoryStatus: String, Codable {
    case scheduled, delivered, opened, finished, cancelled, failed, unconfirmed
    var title: String {
        switch self {
        case .scheduled: return "Programada"
        case .delivered: return "Enviada"
        case .opened: return "Abierta"
        case .finished: return "Finalizada"
        case .cancelled: return "Cancelada"
        case .failed: return "No se pudo programar"
        case .unconfirmed: return "Entrega sin confirmar"
        }
    }
}

struct AlertHistoryEvent: Identifiable, Codable, Equatable {
    var id = UUID()
    let status: AlertHistoryStatus
    let date: Date
}

struct AlertHistoryEntry: Identifiable, Codable, Equatable {
    var id = UUID()
    let systemID: String
    let fingerprint: String
    let kind: AlertHistoryKind
    let recordID: UUID?
    let businessName: String?
    let title: String
    let body: String
    let scheduledDate: Date
    let createdAt: Date
    var events: [AlertHistoryEvent]
    var status: AlertHistoryStatus { events.last?.status ?? .scheduled }
    var lastEventDate: Date { events.last?.date ?? createdAt }
    var statusTitle: String {
        kind == .liveActivity && status == .delivered ? "Activa" : status.title
    }
}

struct AlertHistoryLedger: Codable, Equatable {
    var entries: [AlertHistoryEntry] = []

    @discardableResult
    mutating func register(systemID: String, fingerprint: String, kind: AlertHistoryKind,
                           recordID: UUID?, businessName: String?, title: String, body: String,
                           scheduledDate: Date, at now: Date, initialStatus: AlertHistoryStatus = .scheduled, startsNewPlan: Bool = false) -> UUID {
        if let index = entries.lastIndex(where: {
            $0.systemID == systemID && $0.fingerprint == fingerprint && $0.kind == kind &&
                (!startsNewPlan || $0.status != .cancelled)
        }) {
            // Snapshots and retries must not erase an opening or duplicate an existing plan.
            if initialStatus != .scheduled || entries[index].status == .failed { transition(id: entries[index].id, to: initialStatus, at: now) }
            return entries[index].id
        }
        let entry = AlertHistoryEntry(systemID: systemID, fingerprint: fingerprint, kind: kind,
            recordID: recordID, businessName: businessName, title: title, body: body,
            scheduledDate: scheduledDate, createdAt: now,
            events: [AlertHistoryEvent(status: initialStatus, date: now)])
        entries.append(entry)
        return entry.id
    }

    mutating func transition(id: UUID, to status: AlertHistoryStatus, at date: Date) {
        guard let index = entries.firstIndex(where: { $0.id == id }), entries[index].status != status else { return }
        let previous = entries[index].status
        if status == .scheduled && previous != .failed { return }
        if status == .delivered && [.opened, .finished].contains(previous) { return }
        if status == .finished && previous == .cancelled { return }
        if status == .unconfirmed && previous != .scheduled { return }
        if status == .cancelled && ![.scheduled, .unconfirmed].contains(previous) { return }
        entries[index].events.append(AlertHistoryEvent(status: status, date: date))
    }

    mutating func cancelNotifications(systemIDs: Set<String>, at now: Date) {
        for entry in entries where entry.kind != .liveActivity && systemIDs.contains(entry.systemID) {
            transition(id: entry.id, to: entry.scheduledDate > now ? .cancelled : .unconfirmed, at: now)
        }
    }

    mutating func reconcileActivities(available: Set<String>, at now: Date) {
        for entry in entries where entry.kind == .liveActivity && !available.contains(entry.systemID) {
            if entry.status == .scheduled && entry.scheduledDate <= now {
                transition(id: entry.id, to: .unconfirmed, at: now)
            } else if entry.status == .delivered || entry.status == .opened {
                transition(id: entry.id, to: .finished, at: now)
            }
        }
    }

    mutating func reconcileNotifications(pending: Set<String>, delivered: Set<String>, at now: Date) {
        for entry in entries where entry.kind != .liveActivity && entry.status == .scheduled &&
            entry.scheduledDate <= now && !pending.contains(entry.systemID) && !delivered.contains(entry.systemID) {
            transition(id: entry.id, to: .unconfirmed, at: now)
        }
    }
}
