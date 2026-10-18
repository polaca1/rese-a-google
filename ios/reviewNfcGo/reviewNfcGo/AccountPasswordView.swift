import SwiftUI

/// The same account settings on iPhone and Mac. Google credentials never enter the app.
struct AccountPasswordView: View {
    @ObservedObject var auth: RemoteAuthClient
    @Environment(\.dismiss) private var dismiss
    @State private var password = ""
    @State private var confirmation = ""
    @State private var busy = false
    @State private var saved = false
    @State private var message: String?
    @FocusState private var focused: Field?
    private enum Field: Hashable { case password, confirmation }
    private var valid: Bool {
        !busy && !saved && (8...128).contains(password.count) && password == confirmation
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(auth.session?.user.email ?? "")
                    Text("Google y tu correo dan acceso a la misma cuenta. Elige una contraseña para entrar también con tu correo, conservando tus datos. Puedes seguir usando Google.")
                        .foregroundStyle(.secondary)
                }
                if saved {
                    Section { Label("Contraseña guardada. Ya puedes entrar con este correo y tu contraseña nueva.", systemImage: "checkmark.circle") }
                } else {
                    Section("Nueva contraseña") {
                        SecureField("Contraseña", text: $password)
                            .textContentType(.newPassword).focused($focused, equals: .password)
                            .onSubmit { focused = .confirmation }
                        SecureField("Repite la contraseña", text: $confirmation)
                            .textContentType(.newPassword).focused($focused, equals: .confirmation)
                            .onSubmit(save)
                        Text("Entre 8 y 128 caracteres. No tiene que ser la contraseña de Google.").font(.footnote).foregroundStyle(.secondary)
                    }.disabled(busy)
                    if !confirmation.isEmpty && password != confirmation {
                        Text("Las contraseñas no coinciden.").foregroundStyle(.red)
                    }
                    if let message { Text(message).foregroundStyle(.red) }
                    Button(action: save) {
                        HStack { if busy { ProgressView() }; Text("Guardar contraseña") }
                    }.disabled(!valid)
                    Link("Recuperar por correo", destination: URL(string: "https://polaca1.github.io/rese-a-google/reset-password.html")!)
                        .disabled(busy)
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Crear o cambiar contraseña")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(saved ? "Listo" : "Cancelar") { dismiss() }.disabled(busy)
                }
            }
            .interactiveDismissDisabled(busy)
        }
        #if os(macOS)
        .frame(width: 500, height: 500)
        #endif
        .onDisappear { password = ""; confirmation = "" }
    }

    private func save() {
        guard valid else { return }
        focused = nil; busy = true; message = nil
        Task { @MainActor in
            defer { busy = false; password = ""; confirmation = "" }
            do { try await auth.updatePassword(password); saved = true }
            catch { message = error.localizedDescription }
        }
    }
}
