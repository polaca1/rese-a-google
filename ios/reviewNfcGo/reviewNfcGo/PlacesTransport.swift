import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

enum PlacesTransport {
    static var fallbackKey: String { Bundle.main.object(forInfoDictionaryKey: "GooglePlacesFallbackAPIKey") as? String ?? "" }
    static func execute(_ request: URLRequest, fallback: String = fallbackKey,
                        send: (URLRequest) async throws -> (Data, URLResponse) = { try await URLSession.shared.data(for: $0) }) async throws -> (Data, URLResponse) {
        var primary = request; primary.timeoutInterval = 18
        let canFallback = !fallback.isEmpty && fallback != primary.value(forHTTPHeaderField: "X-Goog-Api-Key")
        let result: (Data, URLResponse)
        do {
            result = try await send(primary)
        } catch {
            guard canFallback, !Task.isCancelled, let network = error as? URLError,
                  [.timedOut, .networkConnectionLost, .cannotConnectToHost].contains(network.code) else { throw error }
            var secondary = primary; secondary.setValue(fallback, forHTTPHeaderField: "X-Goog-Api-Key")
            return try await send(secondary)
        }
            if let http = result.1 as? HTTPURLResponse, canFallback,
               [401, 403, 408, 429].contains(http.statusCode) || (500...599).contains(http.statusCode) {
                try Task.checkCancellation()
                var secondary = primary; secondary.setValue(fallback, forHTTPHeaderField: "X-Goog-Api-Key")
                return try await send(secondary)
            }
        return result
    }
}
