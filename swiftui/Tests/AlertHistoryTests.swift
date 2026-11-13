import Foundation

@main
struct AlertHistoryTests {
    static func main() throws {
        let now = Date(timeIntervalSince1970: 1900000000)
        let business = UUID()
        var ledger = AlertHistoryLedger()
        func register(_ kind: AlertHistoryKind, _ systemID: String, _ fingerprint: String, _ fireDate: Date, newPlan: Bool = false) -> UUID {
            ledger.register(systemID: systemID, fingerprint: fingerprint, kind: kind, recordID: business,
                businessName: "Negocio", title: "Visita", body: "Volver", scheduledDate: fireDate, at: now, startsNewPlan: newPlan)
        }
        let reminder = register(.reminder, "reminder", "plan1", now.addingTimeInterval(30))
        precondition(reminder == register(.reminder, "reminder", "plan1", now.addingTimeInterval(30)))
        precondition(ledger.entries.count == 1 && ledger.entries[0].status == .scheduled)
        ledger.reconcileNotifications(pending: ["reminder"], delivered: [], at: now.addingTimeInterval(40))
        precondition(ledger.entries[0].status == .scheduled, "Una programación pendiente no es una entrega")
        ledger.reconcileNotifications(pending: [], delivered: [], at: now.addingTimeInterval(40))
        precondition(ledger.entries[0].status == .unconfirmed, "Un aviso retirado por iOS no puede presentarse como enviado")
        ledger.transition(id: reminder, to: .delivered, at: now.addingTimeInterval(30))
        ledger.transition(id: reminder, to: .opened, at: now.addingTimeInterval(50))
        let opened = ledger
        ledger.transition(id: reminder, to: .delivered, at: now.addingTimeInterval(30))
        ledger.cancelNotifications(systemIDs: ["reminder"], at: now.addingTimeInterval(60))
        precondition(ledger == opened, "Una nueva lectura del Centro de notificaciones no borra la apertura")

        let future = register(.reminder, "future", "v1", now.addingTimeInterval(600))
        ledger.cancelNotifications(systemIDs: ["future"], at: now)
        precondition(ledger.entries.first { $0.id == future }!.status == .cancelled)
        let reenabled = register(.reminder, "future", "v1", now.addingTimeInterval(600), newPlan: true)
        precondition(reenabled != future, "Cancelar y volver a programar conserva ambas entradas")
        let rescheduled = register(.reminder, "future", "v2", now.addingTimeInterval(900), newPlan: true)
        precondition(rescheduled != reenabled)
        ledger.transition(id: future, to: .delivered, at: now)
        precondition(ledger.entries.first { $0.id == rescheduled }!.status == .scheduled, "Una entrega antigua no modifica el plan nuevo")

        let activity = register(.liveActivity, "activity1", "activity1", now.addingTimeInterval(10))
        ledger.transition(id: activity, to: .delivered, at: now.addingTimeInterval(10))
        ledger.transition(id: activity, to: .opened, at: now.addingTimeInterval(15))
        ledger.transition(id: activity, to: .finished, at: now.addingTimeInterval(20))
        let finished = ledger
        precondition(activity == register(.liveActivity, "activity1", "activity1", now.addingTimeInterval(10)))
        ledger.transition(id: activity, to: .delivered, at: now.addingTimeInterval(10))
        precondition(ledger == finished, "Los snapshots de actividades finalizadas no crean duplicados")
        let activityEntry = ledger.entries.first { $0.id == activity }!
        precondition(activityEntry.events.map(\.status) == [.scheduled, .delivered, .opened, .finished])
        precondition(activityEntry.recordID == business && activityEntry.businessName == "Negocio")

        let failed = register(.test, "test1", "test1", now)
        ledger.transition(id: failed, to: .failed, at: now)
        precondition(failed == register(.test, "test1", "test1", now))
        precondition(ledger.entries.first { $0.id == failed }!.status == .scheduled, "Un reintento conserva el fallo anterior")
        let unseenActivity = register(.liveActivity, "unseen-activity", "unseen-activity", now)
        ledger.reconcileActivities(available: [], at: now.addingTimeInterval(60))
        precondition(ledger.entries.first { $0.id == unseenActivity }!.status == .unconfirmed)
        let cancelledActivity = register(.liveActivity, "cancelled-activity", "cancelled-activity", now.addingTimeInterval(600))
        ledger.transition(id: cancelledActivity, to: .cancelled, at: now)
        ledger.transition(id: cancelledActivity, to: .finished, at: now)
        precondition(ledger.entries.first { $0.id == cancelledActivity }!.status == .cancelled)
        let restored = try JSONDecoder().decode(AlertHistoryLedger.self, from: JSONEncoder().encode(ledger))
        precondition(restored == ledger, "El historial completo debe sobrevivir al cierre de la app")
        print("Historial: persistencia, entrega confirmada, aperturas, cancelación, reprogramación y deduplicación correctos")
    }
}
