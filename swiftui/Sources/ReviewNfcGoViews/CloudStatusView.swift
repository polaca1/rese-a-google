import SwiftUI

/// Normal saving is invisible. Expose only problems that need a person's attention.
struct CloudBackupStatusView: View {
    @EnvironmentObject private var cloud: CloudBackupController
    @State private var resolving = false
    var body: some View {
        Group {
            if cloud.state == .conflict {
                VStack(alignment: .leading, spacing: 10) {
                    Label("Hay cambios diferentes en tus dispositivos.", systemImage: "exclamationmark.triangle")
                    Button("Revisar cambios") { resolving = true }
                }
            } else if case .failed = cloud.state {
                VStack(alignment: .leading, spacing: 10) {
                    Label("No se han podido guardar los últimos cambios. Siguen en este dispositivo.", systemImage: "exclamationmark.triangle")
                    Text("Se volverá a intentar automáticamente.").font(.caption).foregroundStyle(.secondary)
                    Button("Reintentar ahora") { cloud.requestSync(immediate: true) }
                }
            }
        }
        .confirmationDialog("¿Qué cambios quieres conservar?", isPresented: $resolving, titleVisibility: .visible) {
            Button("Conservar los de este dispositivo") { Task { await cloud.resolve(useCloud: false) } }
            Button("Recuperar los de mi cuenta") { Task { await cloud.resolve(useCloud: true) } }
            Button("Cancelar", role: .cancel) { }
        } message: {
            Text("Se aplicarán los cambios elegidos a tus dispositivos. Las dos versiones se conservarán internamente para poder recuperar los datos.")
        }
    }
}
