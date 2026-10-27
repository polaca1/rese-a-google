#if os(iOS)
import SwiftUI
import UIKit

struct WatchBetaView: View {
    @StateObject private var model = WatchBetaController()
    @Environment(\.dismiss) private var dismiss
    @State private var copied = false

    var body: some View {
        List {
            Section {
                Label("Apple Watch", systemImage: "applewatch")
                    .font(.title2.weight(.semibold)).padding(.vertical, 8)
                Text("Beta personal · 0.7.0 (706)")
                    .font(.subheadline).foregroundColor(.secondary)
                Text("Comprueba la conexión real y solicita un perfil para el reloj. Esta primera beta todavía no instala ni renueva apps del Watch.")
                    .font(.subheadline)
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
                if let issue = model.report.issue {
                    Text(issue.message).font(.footnote).foregroundColor(.secondary)
                }
            }
            Section {
                SwiftUI.Button(action: model.detect) { Label("Detectar Watch", systemImage: "antenna.radiowaves.left.and.right") }
                    .disabled(model.running)
                SwiftUI.Button(action: model.prepareProfile) { Label("Probar perfil con ID de SideStore", systemImage: "checkmark.shield") }
                    .disabled(!model.canPrepareProfile)
            } footer: {
                Text("Se reutiliza el identificador ya existente de este SideStore. No crea App IDs ni revoca certificados. La prueba puede registrar el reloj como dispositivo de desarrollo y solicitar un perfil nuevo. No instala apps. Una solicitud enviada puede completarse aunque cierres esta pantalla.")
            }
            Section {
                SwiftUI.Button {
                    UIPasteboard.general.string = model.report.export(); copied = true
                } label: { Label(copied ? "Diagnóstico copiado" : "Copiar diagnóstico", systemImage: "doc.on.doc") }
                    .disabled(model.running)
            } footer: {
                Text("El informe solo contiene los estados de las pruebas. No incluye tu correo, identificadores de dispositivos, claves ni perfiles de firma.")
            }
        }
        .navigationTitle("Watch beta")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .cancellationAction) { SwiftUI.Button("Cerrar") { dismiss() } } }
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
