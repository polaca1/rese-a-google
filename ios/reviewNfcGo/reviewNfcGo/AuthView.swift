import SwiftUI
import MapKit
import CoreLocation
import UserNotifications
import UIKit
import ActivityKit

struct AuthView: View {
    @EnvironmentObject var auth: AuthStore
    @State private var createMode = false
    @State private var name = ""
    @State private var email = ""
    @State private var password = ""
    @FocusState private var focusedField: Field?
    private enum Field: Hashable { case name, email, password }
    private var canSubmit: Bool {
        !auth.isAuthenticating && !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !password.isEmpty
        && (!createMode || !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }
    private func submit() {
        guard canSubmit else { return }
        focusedField = nil
        Task {
            await auth.authenticate(name: createMode ? name : nil, email: email, password: password)
            password = ""
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(createMode ? "Crear cuenta" : "Iniciar sesión")
                            .font(.title2.bold())
                        Text("Entra con tu cuenta para continuar en iPhone y Mac.")
                            .foregroundStyle(.secondary)
                    }

                    VStack(spacing: 12) {
                        if createMode {
                            NativeField(title: "Nombre", icon: "person", text: $name)
                                .textContentType(.name).focused($focusedField, equals: .name)
                                .submitLabel(.next).onSubmit { focusedField = .email }
                        }
                        NativeField(title: "Correo electrónico", icon: "envelope", text: $email)
                            .keyboardType(.emailAddress).textContentType(.username)
                            .focused($focusedField, equals: .email).submitLabel(.next)
                            .onSubmit { focusedField = .password }
                        NativeSecureField(title: "Contraseña", text: $password)
                            .textContentType(createMode ? .newPassword : .password)
                            .focused($focusedField, equals: .password).submitLabel(.go).onSubmit(submit)
                    }

                    if let error = auth.errorMessage {
                        Text(error).font(.footnote).foregroundStyle(.red)
                    }

                    Button(action: submit) {
                        HStack { if auth.isAuthenticating { ProgressView().tint(.white) }; Text(createMode ? "Crear cuenta" : "Entrar") }
                            .frame(maxWidth: .infinity)
                    }
                    .appPrimaryButton()
                    .disabled(!canSubmit)

                    if !createMode {
                        Link("¿Olvidaste tu contraseña?", destination: URL(string: "https://polaca1.github.io/rese-a-google/reset-password.html")!)
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }

                    Button {
                        Task { await auth.authenticateWithGoogle() }
                    } label: {
                        GoogleSignInLabel().frame(maxWidth: .infinity)
                    }
                    .appSecondaryButton()
                    .disabled(auth.isAuthenticating)

                    Button(createMode ? "Ya tengo cuenta" : "Crear una cuenta") {
                        createMode.toggle()
                        password = ""
                        auth.errorMessage = nil
                    }
                    .frame(maxWidth: .infinity)
                    .appSecondaryButton()
                    .disabled(auth.isAuthenticating)

                    if createMode {
                        Text("Si ya usabas reviewNfcGo, crea la cuenta con el mismo correo para conservar tus datos de este iPhone. Puedes elegir una contraseña nueva.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 20)
                }
                .padding(24)
                .background(TopScrollBlurVerification(screen: "auth"))
            }
            .appTopScrollBlur {
                HStack(spacing: 14) {
                    LogoMark(size: 58)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("reviewNfcGo").font(.system(size: 34, weight: .bold, design: .rounded))
                        Text("Encuentra. Copia. Gestiona.").foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 24).padding(.top, 60)
            }
            .background(Color(uiColor: .systemBackground))
            .scrollDismissesKeyboard(.interactively)
            .disabled(auth.isAuthenticating)
            .navigationBarHidden(true)
        }
    }
}

struct NativeField: View {
    let title: String
    let icon: String
    @Binding var text: String
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon).foregroundStyle(.secondary).frame(width: 22).accessibilityHidden(true)
            TextField(title, text: $text)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .accessibilityLabel(title)
        }
        .padding(14)
        .appGlassField()
    }
}

struct NativeSecureField: View {
    let title: String
    @Binding var text: String
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "lock").foregroundStyle(.secondary).frame(width: 22).accessibilityHidden(true)
            SecureField(title, text: $text)
                .accessibilityLabel(title)
        }
        .padding(14)
        .appGlassField()
    }
}
