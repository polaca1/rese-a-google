import SwiftUI
import MapKit
import CoreLocation
import UserNotifications
import UIKit
import ActivityKit

struct InlineDateTimePicker: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    let title: String
    @Binding var selection: Date
    let range: ClosedRange<Date>

    init(_ title: String, selection: Binding<Date>, in range: PartialRangeFrom<Date>) {
        self.title = title; _selection = selection
        self.range = range.lowerBound...Date.distantFuture
    }
    init(_ title: String, selection: Binding<Date>, in range: ClosedRange<Date>) {
        self.title = title; _selection = selection; self.range = range
    }
    var body: some View {
        (typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8)) : AnyLayout(HStackLayout(alignment: .center, spacing: 8))) {
            Text(title).lineLimit(typeSize.isAccessibilitySize ? nil : 2).frame(maxWidth: .infinity, alignment: .leading)
                #if DEBUG
                .background(GeometryReader { geometry in
                    Color.clear.onAppear { DateRowVerification.observe(title: title, component: "label", frame: geometry.frame(in: .global)) }
                })
                #endif
            DatePicker(title, selection: $selection, in: range, displayedComponents: [.date, .hourAndMinute])
                .datePickerStyle(.compact)
                .labelsHidden()
                .fixedSize(horizontal: true, vertical: false)
                .accessibilityLabel(title)
                #if DEBUG
                .background(GeometryReader { geometry in
                    Color.clear.onAppear { DateRowVerification.observe(title: title, component: "controls", frame: geometry.frame(in: .global)) }
                })
                #endif
        }
    }
}

#if DEBUG
@MainActor
enum DateRowVerification {
    static var frames: [String: [String: CGRect]] = [:]
    static func observe(title: String, component: String, frame: CGRect) {
        guard ProcessInfo.processInfo.arguments.contains("--verification-dates"), frame.width > 0 else { return }
        frames[title, default: [:]][component] = frame
        guard frames.count == 2, frames.values.allSatisfy({ $0.count == 2 }) else { return }
        let aligned = frames.values.allSatisfy { abs($0["label"]!.midY - $0["controls"]!.midY) < 1 }
        let output = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("date-layout-verification.json")
        try? JSONSerialization.data(withJSONObject: ["passed": aligned, "rows": frames.count], options: .prettyPrinted).write(to: output)
    }
}
#endif

// MARK: - Quick reminder

struct QuickReminderView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    let place: PlaceResult
    @State private var visitDate = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date().addingTimeInterval(86400)
    @State private var notificationDate = Calendar.current.date(byAdding: .hour, value: 23, to: Date()) ?? Date().addingTimeInterval(82800)
    @State private var notes = ""
    @State private var validationMessage: String?
    // A fixed, whole-minute boundary keeps the compact picker's displayed values
    // in sync with its binding, including while editing a visit near the present.
    @State private var minimumDate = Date(timeIntervalSince1970: (floor(Date().timeIntervalSince1970 / 60) + 1) * 60)
    @FocusState private var notesFocused: Bool

    private var visitSelection: Binding<Date> {
        Binding(get: { visitDate }, set: { newDate in
            visitDate = max(newDate, minimumDate)
            notificationDate = min(max(notificationDate, minimumDate), visitDate)
            validationMessage = nil
        })
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Volver a") {
                    Text(place.name).font(.headline)
                    Text(place.address).font(.subheadline).foregroundStyle(.secondary)
                }
                Section("Visita") {
                    InlineDateTimePicker("Fecha y hora de la visita", selection: visitSelection, in: minimumDate...)
                    InlineDateTimePicker("Avisarme el", selection: $notificationDate, in: minimumDate...max(visitDate, minimumDate))
                    Text("El aviso puede ser anterior a la visita. Si su hora pasa mientras editas, se programará para el próximo minuto disponible.")
                        .font(.footnote).foregroundStyle(.secondary)
                    if let validationMessage {
                        Label(validationMessage, systemImage: "exclamationmark.circle")
                            .font(.footnote).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("reminder-validation")
                    }
                }
                Section("Nota opcional") {
                    TextField("Ej. Preguntar por el encargado", text: $notes, axis: .vertical)
                        .lineLimit(2...5)
                        .focused($notesFocused)
                }
                Section("Ubicación guardada") {
                    PlaceMiniMap(place: place)
                        .frame(height: 170)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    Button { MapLauncher.openAppleMaps(place: place) } label: {
                        Label("Abrir en Apple Maps", systemImage: "map.fill")
                    }
                    Button { MapLauncher.openGoogleMaps(place: place) } label: {
                        Label("Abrir en Google Maps", systemImage: "location.fill")
                    }
                }
            }
            .navigationTitle("Volver más tarde")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") { saveReminder() }.appConfirmationButton()
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer(); Button("OK") { notesFocused = false }
                }
            }
            #if DEBUG
            .task {
                if ProcessInfo.processInfo.arguments.contains("--verification-reminder-save") {
                    try? await Task.sleep(nanoseconds: 300_000_000)
                    verifyReminderSaving()
                }
            }
            #endif
        }
    }

    @discardableResult
    private func saveReminder(dismissAfterSaving: Bool = true) -> VisitRecord? {
        notesFocused = false
        let now = Date()
        // Compact controls expose minutes, so hidden seconds must not make the
        // same visible visit and notification time fail the ordering check.
        let visit = Date(timeIntervalSince1970: floor(visitDate.timeIntervalSince1970 / 60) * 60)
        guard visit > now else {
            minimumDate = Date(timeIntervalSince1970: (floor(now.timeIntervalSince1970 / 60) + 1) * 60)
            validationMessage = "La hora de la visita ya ha pasado. Elige una fecha y hora futuras para guardar."
            return nil
        }
        let selectedNotice = Date(timeIntervalSince1970: floor(notificationDate.timeIntervalSince1970 / 60) * 60)
        // If the form stayed open past the notice, save the upcoming visit and
        // schedule its notice for the next available minute, never after it.
        let nextMinute = Date(timeIntervalSince1970: (floor(now.timeIntervalSince1970 / 60) + 1) * 60)
        let notice = min(visit, selectedNotice > now ? selectedNotice : nextMinute)
        visitDate = visit; notificationDate = notice; validationMessage = nil
        let record = store.saveReminder(for: place, visitDate: visit, notificationDate: notice, notes: notes)
        if dismissAfterSaving { dismiss() }
        return record
    }

    #if DEBUG
    private func verifyReminderSaving() {
        var checks: [String: Bool] = [:]
        let originalUser = store.loadedUserEmail
        let testUser = "reminder-verification@example.invalid"
        UserDefaults.standard.removeObject(forKey: "resenago.records.\(testUser)")
        UserDefaults.standard.removeObject(forKey: MoneyLedger.storageKey(testUser))
        store.switchUser(testUser)
        let now = Date()
        visitDate = now.addingTimeInterval(7200); notificationDate = now.addingTimeInterval(10800)
        notes = "Comprobar guardado real"
        let first = saveReminder(dismissAfterSaving: false)
        checks["Guarda el negocio y ajusta un aviso posterior a la visita"] = first?.notificationDate == first?.reminderDate && first != nil
        if let first {
            let owner = store.loadedUserEmail
            store.switchUser(owner)
            let restored = store.records.first { $0.id == first.id }
            checks["La visita, el aviso y las notas sobreviven a la recarga"] = restored?.reminderDate == first.reminderDate && restored?.notificationDate == first.notificationDate && restored?.notes == notes
            checks["Aparece en los recordatorios pendientes"] = store.pendingReminders.contains { $0.id == first.id }
            notificationDate = now.addingTimeInterval(-120)
            let updated = saveReminder(dismissAfterSaving: false)
            checks["Guardar con un aviso caducado conserva la visita y programa un aviso futuro"] = updated?.id == first.id && (updated?.notificationDate ?? .distantPast) > now
            checks["Editar el recordatorio no duplica el negocio"] = store.records.filter { $0.place.id == place.id }.count == 1
            visitDate = now.addingTimeInterval(-60)
            checks["Una visita pasada muestra un error y conserva lo guardado"] = saveReminder(dismissAfterSaving: false) == nil && validationMessage != nil && store.records.first(where: { $0.id == first.id })?.reminderDate == updated?.reminderDate
            visitDate = now.addingTimeInterval(3600)
            notificationDate = visitDate.addingTimeInterval(20)
            let sameMinute = saveReminder(dismissAfterSaving: false)
            checks["Los segundos ocultos no impiden guardar la misma hora visible"] = sameMinute != nil && sameMinute?.notificationDate == sameMinute?.reminderDate
        }
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("reminder-save-verification.json")
        try? JSONSerialization.data(withJSONObject: ["passed": checks.count == 7 && checks.values.allSatisfy { $0 }, "checks": checks], options: .prettyPrinted).write(to: url)
        store.switchUser(originalUser)
        UserDefaults.standard.removeObject(forKey: "resenago.records.\(testUser)")
        UserDefaults.standard.removeObject(forKey: MoneyLedger.storageKey(testUser))
    }
    #endif
}

// MARK: - Reminders

struct RemindersView: View {
    @EnvironmentObject var store: AppStore
    #if DEBUG
    @State private var verificationHistoryPresented = false
    #endif

    var body: some View {
        List {
            Section {
                NotificationPermissionsRow()
            }
            if store.pendingReminders.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "bell.slash").font(.system(size: 40)).foregroundStyle(.secondary)
                    Text("Sin recordatorios pendientes").font(.headline)
                    Text("En un sitio guardado puedes indicar que debes volver otro día y elegir fecha y hora.")
                        .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity).padding(.vertical, 60)
                .listRowBackground(Color.clear)
            } else {
                ForEach(store.pendingReminders) { record in
                    NavigationLink(destination: RecordDetailView(recordID: record.id)) {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(record.place.name).font(.headline)
                            if let date = record.reminderDate {
                                Label("Visita: \(date.formatted(date: .abbreviated, time: .shortened))", systemImage: "calendar")
                                    .font(.subheadline).foregroundStyle(AppTheme.blue)
                            }
                            if let notify = record.notificationDate ?? record.reminderDate {
                                Label("Aviso: \(notify.formatted(date: .abbreviated, time: .shortened))", systemImage: "bell")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Label(record.place.address, systemImage: "mappin.and.ellipse")
                                .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                            if !record.notes.isEmpty {
                                Text(record.notes).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                            }
                        }.padding(.vertical, 4)
                    }
                }
            }
        }
        .navigationTitle("Recordatorios")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                NavigationLink(destination: AlertHistoryView()) {
                    Image(systemName: "bell.badge")
                }
                .accessibilityLabel("Ver historial de notificaciones y Live Activities")
            }
        }
        .onAppear {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--verification-history") {
                verificationHistoryPresented = true
                return
            }
            #endif
            NotificationManager.requestPermission()
        }
        #if DEBUG
        .navigationDestination(isPresented: $verificationHistoryPresented) { AlertHistoryView() }
        #endif
    }
}

struct NotificationPermissionsRow: View {
    @State private var statusText = "Comprobando notificaciones…"
    @State private var denied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: denied ? "bell.slash.fill" : "bell.badge.fill")
                    .foregroundStyle(denied ? .red : AppTheme.blue)
                Text(statusText).font(.subheadline.weight(.semibold))
            }
            if denied {
                Button("Abrir Ajustes de notificaciones") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                }
            }
        }
        .onAppear { refresh() }
    }

    private func refresh() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async {
                switch settings.authorizationStatus {
                case .authorized, .provisional, .ephemeral:
                    statusText = "Notificaciones activadas"
                    denied = false
                case .denied:
                    statusText = "Notificaciones desactivadas"
                    denied = true
                case .notDetermined:
                    statusText = "Falta dar permiso a las notificaciones"
                    denied = false
                @unknown default:
                    statusText = "Comprueba las notificaciones"
                    denied = false
                }
            }
        }
    }
}

struct PlaceMiniMap: UIViewRepresentable {
    let place: PlaceResult

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.isScrollEnabled = false
        map.isZoomEnabled = false
        map.isRotateEnabled = false
        map.isPitchEnabled = false
        map.pointOfInterestFilter = .includingAll
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        map.removeAnnotations(map.annotations)
        let annotation = MKPointAnnotation()
        annotation.coordinate = place.coordinate
        annotation.title = place.name
        map.addAnnotation(annotation)
        map.setRegion(MKCoordinateRegion(center: place.coordinate, latitudinalMeters: 650, longitudinalMeters: 650), animated: false)
    }
}
