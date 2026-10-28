
import Foundation
import Combine
import WatchConnectivity
import Network

@MainActor
final class WatchStore: NSObject, ObservableObject, WCSessionDelegate {
    @Published var phone = "Conectando…"
    @Published var localService = "Comprobando…"
    @Published var delivery = "La apertura del reloj aún no se ha confirmado al iPhone."
    private var connection: NWConnection?
    private var started = false

    func start() {
        guard !started else { return }
        started = true
        if WCSession.isSupported() {
            WCSession.default.delegate = self
            WCSession.default.activate()
        } else { phone = "No disponible" }
        let connection = NWConnection(host: "127.0.0.1", port: 62078, using: .tcp)
        self.connection = connection
        connection.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                guard let self else { return }
                switch state {
                case .ready: self.localService = "Puerto accesible"; self.connection?.cancel()
                case .failed: self.localService = "No accesible"
                default: break
                }
            }
        }
        connection.start(queue: DispatchQueue(label: "SideStore.Watch.LocalProbe"))
        Task {
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            if localService == "Comprobando…" { localService = "Sin respuesta"; connection.cancel() }
        }
    }

    private func announce() {
        let session = WCSession.default
        phone = session.isReachable ? "Conectado" : "No disponible ahora"
        let message: [String: Any] = ["sideStoreWatchLaunch": true,
            "version": Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "",
            "localService": localService]
        if session.isReachable {
            session.sendMessage(message, replyHandler: { _ in
                Task { @MainActor in self.delivery = "Apertura confirmada al iPhone." }
            }, errorHandler: { _ in
                Task { @MainActor in self.delivery = "No se ha confirmado todavía; se reintentará al conectar." }
            })
        }
    }

    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        Task { @MainActor in self.announce() }
    }
    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in self.announce() }
    }
}
