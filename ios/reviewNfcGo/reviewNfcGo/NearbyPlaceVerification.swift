#if DEBUG
import Foundation
import CoreLocation

@MainActor enum NearbyPlaceVerification {
    static func run(finder display: PlaceFinder) async {
        let output = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("nearby-verification.json")
        let coordinate = CLLocationCoordinate2D(latitude: 40.4168, longitude: -3.7038)
        func place(_ id: String, name: String, type: String) -> PlaceResult {
            PlaceResult(id: id, name: name, address: "Calle Mayor, Madrid", latitude: coordinate.latitude + 0.000045,
                        longitude: coordinate.longitude, types: [type], primaryType: type, businessStatus: "OPERATIONAL")
        }
        let bar = place("nearby-bar", name: "Bar de la Plaza", type: "bar")
        let insurance = place("nearby-insurance", name: "Seguros Centro", type: "insurance_agency")
        let cafeA = place("nearby-cafe-a", name: "Café de la Plaza", type: "cafe")
        let cafeB = place("nearby-cafe-b", name: "Café Central", type: "cafe")
        var checks: [String] = []
        func check(_ value: Bool, _ label: String) throws {
            guard value else { throw NSError(domain: "NearbyVerification", code: 1, userInfo: [NSLocalizedDescriptionKey: label]) }
            checks.append(label)
        }
        do {
            var requests = 0
            let finder = PlaceFinder(nearbyLookup: { _ in requests += 1; return [insurance, bar] })
            finder.prepareMapVerification()
            let fix = CLLocation(coordinate: coordinate, altitude: 0, horizontalAccuracy: 5, verticalAccuracy: 5, timestamp: Date())
            finder.locationManager(CLLocationManager(), didUpdateLocations: [fix])
            await finder.useMyLocation()
            try check(finder.selectedPlace?.id == bar.id && finder.nearbyChoices.isEmpty, "Misma distancia: primero el bar")
            await finder.useMyLocation()
            try check(finder.selectedPlace?.id == insurance.id && finder.nearbyPosition == 2, "Segundo toque de Mi ubicación cambia al seguro")
            await finder.useMyLocation()
            try check(finder.selectedPlace?.id == bar.id && requests == 1, "La lista vuelve al primero sin repetir la consulta a Google")
            finder.chooseSearchResult(cafeA)
            await finder.useMyLocation()
            try check(finder.selectedPlace?.id == bar.id, "Volver desde una búsqueda manual empieza por el local más probable")

            let ambiguous = PlaceFinder(nearbyLookup: { _ in [cafeB, cafeA] })
            ambiguous.prepareMapVerification()
            await ambiguous.searchNearest(to: coordinate, accuracy: 5)
            try check(ambiguous.selectedPlace == nil && ambiguous.nearbyChoices.count == 2,
                      "Dos locales igual de probables muestran dos opciones sin seleccionar ni habilitar NFC")
            ambiguous.chooseNearbyPlace(cafeB)
            try check(ambiguous.selectedPlace?.id == cafeB.id && ambiguous.nearbyChoices.isEmpty,
                      "Elegir una opción confirma ese negocio y retira la tarjeta de elección")
            ambiguous.chooseSearchResult(bar)
            ambiguous.chooseNearbyPlace(cafeA)
            try check(ambiguous.selectedPlace?.id == bar.id, "Un botón de una lista antigua no reemplaza una elección posterior")

            var pending: CheckedContinuation<[PlaceResult], Error>?
            let delayed = PlaceFinder(nearbyLookup: { _ in try await withCheckedThrowingContinuation { pending = $0 } })
            delayed.prepareMapVerification()
            let operation = Task { await delayed.searchNearest(to: coordinate) }
            for _ in 0..<50 { if pending != nil { break }; try await Task.sleep(for: .milliseconds(10)) }
            guard let continuation = pending else { throw NSError(domain: "NearbyVerification", code: 2) }
            delayed.chooseSearchResult(cafeB)
            continuation.resume(returning: [bar, insurance])
            await operation.value
            try check(delayed.selectedPlace?.id == cafeB.id && delayed.nearbyChoices.isEmpty,
                      "Una respuesta tardía no sobrescribe el negocio elegido por nombre")

            let empty = PlaceFinder(nearbyLookup: { _ in [] }); empty.prepareMapVerification()
            await empty.searchNearest(to: coordinate)
            try check(empty.selectedPlace == nil && empty.nearbyChoices.isEmpty && !empty.isLoading,
                      "Una zona sin candidatos deja elegir por nombre y no inventa locales")
            let failing = PlaceFinder(nearbyLookup: { _ in throw URLError(.notConnectedToInternet) }); failing.prepareMapVerification()
            await failing.searchNearest(to: coordinate)
            try check(failing.selectedPlace == nil && failing.errorMessage != nil && !failing.isLoading,
                      "Un fallo de conexión no se convierte en una selección aleatoria")

            display.prepareNearbyChoicesVerification([cafeB, cafeA], coordinate: coordinate)
            try JSONSerialization.data(withJSONObject: ["passed": true, "checks": checks], options: .prettyPrinted).write(to: output)
        } catch {
            try? JSONSerialization.data(withJSONObject: ["passed": false, "checks": checks, "error": error.localizedDescription], options: .prettyPrinted).write(to: output)
        }
    }
}
#endif
