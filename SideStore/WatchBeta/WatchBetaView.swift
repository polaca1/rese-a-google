#if os(iOS)
import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct WatchBetaView: View {
    @StateObject private var model = WatchBetaController()
    @Environment(\.dismiss) private var dismiss
    @State private var copied = false
    @State private var importing = false
    @ObservedObject private var automaticWatch = WatchPackageCoordinator.shared

    var body: some View {
        List {
            Section {
                Label("Apple Watch", systemImage: "applewatch")
                    .font(.title2.weight(.semibold)).padding(.vertical, 8)
                Text("Beta personal · 0.7.0 (708)")
                    .font(.subheadline).foregroundColor(.secondary)
                Text("Comprueba la conexión real y solicita un perfil para el reloj. Permite importar, firmar e instalar una app de watchOS con un App ID existente. La renovación autónoma sigue pendiente.")
                    .font(.subheadline)
            }
            Section {
                Text(automaticWatch.message ?? "Las apps incluidas en Watch/ dentro del IPA se firmarán y enviarán al reloj automáticamente.")
                    .font(.footnote).foregroundColor(.secondary)
            }
            Section(header: Text("Comprobación")) {
                ForEach(WatchBetaStage.allCases) { stage in
                    HStack {
                        Text(stage.title)
                        Spacer()
                        status(model.report.status(stage))
                    }.accessibilityElement(children: .combine)
                }
                if model.watchCount > 1 {
                    Picker("Reloj", selection: $model.selection) {
                        ForEach(0..<model.watchCount, id: \.self) { index in Text("Watch \(index + 1)").tag(index) }
                    }.disabled(model.running)
                }
                if let diagnostic = model.report.profileDiagnostic {
                    Text(diagnostic.message).font(.footnote).foregroundColor(.secondary)
                }
                if let issue = model.report.issue {
                    Text(issue.message).font(.footnote).foregroundColor(.secondary)
                }
            }
            Section {
                SwiftUI.Button(action: model.detect) { Label("Detectar Watch", systemImage: "antenna.radiowaves.left.and.right") }
                    .disabled(model.running)
                if !model.appIDs.isEmpty {
                    Picker("App ID existente", selection: $model.selectedAppID) {
                        Text("Seleccionar…").tag("")
                        ForEach(model.appIDs, id: \.identifier) { app in
                            Text(app.bundleIdentifier).tag(app.bundleIdentifier)
                        }
                    }.disabled(model.running)
                }
                SwiftUI.Button(action: model.prepareProfile) { Label("Probar perfil con el ID seleccionado", systemImage: "checkmark.shield") }
                    .disabled(!model.canPrepareProfile || model.selectedAppID.isEmpty)
            } footer: {
                Text("Selecciona un App ID que Apple haya devuelto para tu cuenta. Se reutiliza sin modificar la identidad de tu SideStore. No crea App IDs ni revoca certificados. La prueba puede registrar el reloj como dispositivo de desarrollo y solicitar un perfil nuevo. No instala apps. Una solicitud enviada puede completarse aunque cierres esta pantalla.")
            }
            Section {
                SwiftUI.Button { importing = true } label: { Label("Elegir IPA…", systemImage: "square.and.arrow.down") }
                    .disabled(model.running)
                if let name = model.importedName {
                    Text(name)
                    SwiftUI.Button("Firmar e instalar", action: model.installImportedApp)
                        .disabled(!model.canPrepareProfile || model.watchCount != 1)
                }
                if let message = model.installMessage { Text(message).font(.footnote).foregroundColor(.secondary) }
            } header: {
                Text("Instalar en el Watch")
            } footer: {
                Text("Un único Watch enlazado, desbloqueado y cerca. Requiere emparejamiento TCP. El IPA debe contener una sola app watchOS sin extensiones y usar un App ID ya registrado en tu cuenta. No crea IDs ni elimina apps antes de actualizar.")
            }
            Section {
                SwiftUI.Button {
                    UIPasteboard.general.string = model.report.export(); copied = true
                } label: { Label(copied ? "Diagnóstico copiado" : "Copiar diagnóstico", systemImage: "doc.on.doc") }
                    .disabled(model.running)
            } footer: {
                Text("El informe contiene los estados, el paso que falla y su código numérico. No incluye tu correo, identificadores de dispositivos, claves ni perfiles de firma.")
            }
        }
        .navigationTitle("Watch beta")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .cancellationAction) { SwiftUI.Button("Cerrar") { dismiss() } } }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.data], allowsMultipleSelection: false) { result in
            if case .success(let urls) = result, let url = urls.first { model.importIPA(url) }
        }
        .onDisappear { model.cancel() }
    }

    @ViewBuilder private func status(_ value: WatchBetaStatus) -> some View {
        switch value {
        case .pending: Text("Pendiente").font(.caption).foregroundColor(.secondary)
        case .running: ProgressView().accessibilityLabel("Comprobando")
        case .passed: Image(systemName: "checkmark.circle.fill").foregroundColor(.green).accessibilityLabel("Comprobado")
        case .failed: Image(systemName: "exclamationmark.circle.fill").foregroundColor(.orange).accessibilityLabel("No completado")
        }
    }
}
#endif
