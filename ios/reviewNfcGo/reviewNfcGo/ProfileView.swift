import SwiftUI
import MapKit
import CoreLocation
import UserNotifications
import UIKit
import ActivityKit

// MARK: - Profile

struct ProfileView: View {
    @EnvironmentObject var auth: AuthStore
    @EnvironmentObject var store: AppStore
    @EnvironmentObject private var cloud: CloudBackupController
    @State private var confirmingSignOut = false

    var body: some View {
        List {
            Section {
                HStack(spacing: 14) {
                    ProfileAvatar(size: 64)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(auth.currentUser?.name ?? "").font(.headline)
                        Text(auth.currentUser?.email ?? "").font(.subheadline).foregroundStyle(.secondary)
                    }
                }.padding(.vertical, 8)
                ProfilePhotoPicker()
            }
            Section("Resumen") {
                LabeledContent("Sitios guardados", value: "\(store.records.count)")
                LabeledContent("Saldo", value: (Double(store.money.balanceCents) / 100).formatted(.currency(code: "EUR")))
                LabeledContent("Tarjetas vendidas", value: "\(store.totalCardsSold)")
                LabeledContent("Recordatorios", value: "\(store.pendingReminders.count)")
            }
            if let title = store.undoTitle {
                Section { Button("Deshacer: " + title) { store.undoLastChange() } }
            }
            Section("Acerca de reviewNfcGo") {
                LabeledContent("Versión", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "6.0.2")
            }
            Section("Cuenta") {
                CloudBackupStatusView()
                Button {
                    Task { await auth.authenticateWithGoogle() }
                } label: {
                    HStack {
                        GoogleSignInLabel()
                        if auth.isAuthenticating { Spacer(); ProgressView() }
                    }
                }.disabled(auth.isAuthenticating)
                if let error = auth.errorMessage { Text(error).font(.footnote).foregroundStyle(.red) }
                Button("Cerrar sesión", role: .destructive) {
                    if cloud.shouldConfirmSignOut { confirmingSignOut = true }
                    else { auth.logout() }
                }.disabled(auth.isAuthenticating)
            }
        }
        .navigationTitle("Perfil")
        .confirmationDialog("Tus últimos cambios aún se están guardando", isPresented: $confirmingSignOut, titleVisibility: .visible) {
            Button("Guardar y seguir aquí") { cloud.requestSync(immediate: true) }
            Button("Cerrar sesión igualmente", role: .destructive) { auth.logout() }
            Button("Cancelar", role: .cancel) { }
        } message: {
            Text("Espera a que termine el guardado antes de cerrar sesión. Tus cambios siguen en este iPhone; si borras la app antes de guardarlos, puedes perderlos.")
        }
    }
}
