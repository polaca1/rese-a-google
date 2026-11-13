import SwiftUI
import MapKit
import CoreLocation
import UserNotifications
import UIKit
import ActivityKit

// MARK: - Native MapKit map

struct NativeMapView: UIViewRepresentable {
    let selectedPlace: PlaceResult?
    let focusRequest: MapFocusRequest?
    let onTap: (CLLocationCoordinate2D) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.delegate = context.coordinator
        map.showsUserLocation = true
        map.pointOfInterestFilter = .includingAll
        map.isRotateEnabled = false
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.didTap(_:)))
        tap.cancelsTouchesInView = false
        map.addGestureRecognizer(tap)
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--verification-map") {
            MapCameraVerification.map = map
            MapCameraVerification.coordinator = context.coordinator
        }
        #endif
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        context.coordinator.parent = self
        let coordinator = context.coordinator
        if coordinator.lastPlace != selectedPlace {
            coordinator.lastPlace = selectedPlace
            map.removeAnnotations(map.annotations.filter { !($0 is MKUserLocation) })
            if let place = selectedPlace {
                let annotation = MKPointAnnotation()
                annotation.coordinate = place.coordinate
                annotation.title = place.name
                annotation.subtitle = place.address
                map.addAnnotation(annotation)
            }
        }
        guard let request = focusRequest, coordinator.lastFocusID != request.id else { return }
        coordinator.lastFocusID = request.id
        coordinator.focus(map, request: request)
    }

    static func dismantleUIView(_ map: MKMapView, coordinator: Coordinator) {
        coordinator.cancelFlight()
        map.delegate = nil
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        var parent: NativeMapView
        var lastPlace: PlaceResult?
        var lastFocusID: UUID?
        private weak var flightMap: MKMapView?
        private var flight: MapFlightPlan?
        var isFlying: Bool { flight != nil }
        private var flightRequest: MapFocusRequest?
        private var flightStarted: CFTimeInterval = 0
        private var displayLink: CADisplayLink?
        #if DEBUG
        private var verificationElapsed: TimeInterval = 0
        #endif
        init(parent: NativeMapView) { self.parent = parent }

        private final class FrameTarget: NSObject {
            weak var owner: Coordinator?
            init(_ owner: Coordinator) { self.owner = owner }
            @objc func tick(_ link: CADisplayLink) { owner?.advanceFlight(link) }
        }

        func focus(_ map: MKMapView, request: MapFocusRequest) {
            cancelFlight()
            // Following must start after arrival; enabling it first jumps to the GPS fix.
            map.setUserTrackingMode(.none, animated: false)
            let distance: CLLocationDistance = request.target == .user ? 850 : 650
            let region = map.regionThatFits(MKCoordinateRegion(center: request.coordinate,
                latitudinalMeters: distance, longitudinalMeters: distance))
            if UIAccessibility.isReduceMotionEnabled {
                map.setRegion(region, animated: false)
                if request.target == .user { map.setUserTrackingMode(.follow, animated: false) }
                return
            }
            let from = map.visibleMapRect
            let west = MKMapPoint(CLLocationCoordinate2D(latitude: region.center.latitude,
                longitude: region.center.longitude - region.span.longitudeDelta / 2))
            let east = MKMapPoint(CLLocationCoordinate2D(latitude: region.center.latitude,
                longitude: region.center.longitude + region.span.longitudeDelta / 2))
            let north = MKMapPoint(CLLocationCoordinate2D(latitude: region.center.latitude + region.span.latitudeDelta / 2,
                longitude: region.center.longitude))
            let south = MKMapPoint(CLLocationCoordinate2D(latitude: region.center.latitude - region.span.latitudeDelta / 2,
                longitude: region.center.longitude))
            let center = MKMapPoint(request.coordinate)
            let width = abs(east.x - west.x)
            let height = abs(south.y - north.y)
            guard from.width > 0, from.height > 0, width > 0, height > 0 else { return }
            flight = MapFlightPlan(start: .init(x: from.midX, y: from.midY, width: from.width, height: from.height),
                destination: .init(x: center.x, y: center.y, width: width, height: height), worldWidth: MKMapRect.world.width)
            flightMap = map
            flightRequest = request
            flightStarted = CACurrentMediaTime()
            #if DEBUG
            verificationElapsed = 0
            #endif
            let target = FrameTarget(self)
            let link = CADisplayLink(target: target, selector: #selector(FrameTarget.tick(_:)))
            link.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 60, preferred: 60)
            displayLink = link
            link.add(to: .main, forMode: .common)
        }

        private func advanceFlight(_ link: CADisplayLink) {
            guard let map = flightMap, let flight, let request = flightRequest else { cancelFlight(); return }
            var elapsed = max(0, link.timestamp - flightStarted)
            #if DEBUG
            // Exercise every native camera step even when a headless runner drops
            // several seconds of callbacks. Release flights retain wall-clock time.
            if ProcessInfo.processInfo.arguments.contains("--verification-map") {
                verificationElapsed += 1.0 / 30.0
                elapsed = verificationElapsed
            }
            #endif
            let frame = flight.frame(at: elapsed)
            let v = frame.viewport
            map.setVisibleMapRect(MKMapRect(x: v.x - v.width / 2, y: v.y - v.height / 2,
                                            width: v.width, height: v.height), animated: false)
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--verification-map") {
                MapCameraVerification.samples.append(.init(elapsed: elapsed, phase: frame.phase,
                    rect: map.visibleMapRect))
            }
            #endif
            if frame.phase == .finished {
                cancelFlight()
                if request.target == .user { map.setUserTrackingMode(.follow, animated: false) }
            }
        }

        func cancelFlight() {
            displayLink?.invalidate()
            displayLink = nil
            flight = nil
            flightRequest = nil
            flightMap = nil
        }

        func mapView(_ mapView: MKMapView, regionWillChangeAnimated animated: Bool) {
            // Native pans and pinches take control immediately, without waiting for the flight.
            func isInteracting(_ view: UIView) -> Bool {
                if view.gestureRecognizers?.contains(where: { $0.state == .began || $0.state == .changed }) == true { return true }
                return view.subviews.contains(where: isInteracting)
            }
            if isInteracting(mapView) { cancelFlight() }
        }

        @objc func didTap(_ gesture: UITapGestureRecognizer) {
            guard let map = gesture.view as? MKMapView else { return }
            let point = gesture.location(in: map)
            let coordinate = map.convert(point, toCoordinateFrom: map)
            parent.onTap(coordinate)
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            if annotation is MKUserLocation { return nil }
            let id = "SelectedPlace"
            let view = mapView.dequeueReusableAnnotationView(withIdentifier: id) as? MKMarkerAnnotationView ?? MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: id)
            view.annotation = annotation
            view.markerTintColor = UIColor.systemBlue
            view.glyphImage = UIImage(systemName: "building.2.fill")
            view.canShowCallout = true
            return view
        }
    }
}

#if DEBUG
@MainActor
enum MapCameraVerification {
    static weak var map: MKMapView?
    static weak var coordinator: NativeMapView.Coordinator?
    struct Sample {
        let elapsed: Double
        let phase: MapFlightPlan.Phase
        let rect: MKMapRect
    }
    static var samples: [Sample] = []

    static func run(finder: PlaceFinder) async {
        let output = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("map-camera-verification.json")
        var checks: [String] = []
        do {
            for _ in 0..<30 {
                if map != nil { break }
                try await Task.sleep(nanoseconds: 100_000_000)
            }
            guard let map else { throw VerificationError.failed("No se creó el mapa") }
            let madrid = CLLocation(latitude: 40.4168, longitude: -3.7038)
            let seville = PlaceResult(id: "verification-seville", name: "Negocio en Sevilla",
                address: "Sevilla", latitude: 37.3891, longitude: -5.9845)
            let barcelona = CLLocationCoordinate2D(latitude: 41.3874, longitude: 2.1686)
            finder.prepareMapVerification()
            finder.locationManager(CLLocationManager(), didUpdateLocations: [madrid])
            try await assertFocus(map, on: madrid.coordinate, label: "Primera ubicación", checks: &checks)
            samples.removeAll()
            finder.selectPlace(seville, focus: true)
            try await assertFocus(map, on: seville.coordinate, label: "Búsqueda lejos de la ubicación", checks: &checks)
            // Headless simulators may skip a display-link callback while MapKit loads tiles.
            // Assert the observed path instead of requiring a frame in a particular 150 ms window.
            let moving = samples.filter { $0.phase == .flight }
            guard moving.count >= 5, let first = moving.first,
                  let widest = moving.max(by: { $0.rect.width < $1.rect.width }),
                  let finish = samples.first(where: { $0.phase == .finished }),
                  widest.rect.width > first.rect.width * 10,
                  finish.rect.width < widest.rect.width / 20,
                  hypot(widest.rect.midX - first.rect.midX, widest.rect.midY - first.rect.midY) > 10000,
                  hypot(widest.rect.midX - finish.rect.midX, widest.rect.midY - finish.rect.midY) > 10000,
                  moving.contains(where: { $0.elapsed < widest.elapsed && $0.rect.width > first.rect.width * 1.1 && hypot($0.rect.midX - first.rect.midX, $0.rect.midY - first.rect.midY) > 1 }),
                  moving.contains(where: { $0.elapsed > widest.elapsed && $0.rect.width < widest.rect.width * 0.9 && hypot($0.rect.midX - finish.rect.midX, $0.rect.midY - finish.rect.midY) > 1 })
            else { throw VerificationError.failed("Desplazamiento y zoom simultáneos") }
            checks.append("Desplazamiento y zoom simultáneos en una curva continua")
            finder.locationManager(CLLocationManager(), didUpdateLocations: [madrid])
            try await Task.sleep(nanoseconds: 500_000_000)
            try await assertFocus(map, on: seville.coordinate, label: "El GPS no interrumpe el negocio buscado", checks: &checks)
            map.setRegion(MKCoordinateRegion(center: barcelona, latitudinalMeters: 900, longitudinalMeters: 900), animated: false)
            finder.selectPlace(seville, focus: true)
            try await assertFocus(map, on: seville.coordinate, label: "Volver a buscar el mismo negocio después de mover el mapa", checks: &checks)
            finder.focusOnUserLocation()
            try await assertFocus(map, on: madrid.coordinate, label: "Mi ubicación después de una búsqueda", checks: &checks)
            map.setUserTrackingMode(.none, animated: false)
            map.setRegion(MKCoordinateRegion(center: barcelona, latitudinalMeters: 900, longitudinalMeters: 900), animated: false)
            finder.focusOnUserLocation()
            try await assertFocus(map, on: madrid.coordinate, label: "Mi ubicación después de arrastrar el mapa", checks: &checks)
            // A new search interrupts the flight and starts from the current visible camera.
            finder.selectPlace(seville, focus: true)
            try await Task.sleep(nanoseconds: 900_000_000)
            finder.focusOnUserLocation()
            try await assertFocus(map, on: madrid.coordinate, label: "Interrumpir el vuelo con un nuevo destino", checks: &checks)
            finder.selectPlace(seville, focus: true)
            try await Task.sleep(nanoseconds: 900_000_000)
            coordinator?.cancelFlight()
            map.setRegion(MKCoordinateRegion(center: barcelona, latitudinalMeters: 900, longitudinalMeters: 900), animated: false)
            try await Task.sleep(nanoseconds: 1_800_000_000)
            try await assertFocus(map, on: barcelona, label: "Cancelar el vuelo devuelve el control al mapa", checks: &checks)
            finder.focusOnUserLocation()
            try await assertFocus(map, on: madrid.coordinate, label: "Volver a ubicación después de cancelar el vuelo", checks: &checks)
            finder.selectPlace(nil, focus: false)
            try JSONSerialization.data(withJSONObject: ["passed": true, "checks": checks], options: .prettyPrinted).write(to: output)
        } catch {
            try? JSONSerialization.data(withJSONObject: ["passed": false, "checks": checks, "error": String(describing: error), "samples": samples.map { ["elapsed": $0.elapsed, "width": $0.rect.width, "x": $0.rect.midX, "y": $0.rect.midY] }], options: .prettyPrinted).write(to: output)
        }
    }

    private static func assertFocus(_ map: MKMapView, on coordinate: CLLocationCoordinate2D,
                                    label: String, checks: inout [String]) async throws {
        let target = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        for _ in 0..<150 {
            let actual = CLLocation(latitude: map.centerCoordinate.latitude, longitude: map.centerCoordinate.longitude)
            if actual.distance(from: target) < 100 && map.region.span.latitudeDelta < 0.03 && coordinator?.isFlying != true {
                checks.append(label)
                return
            }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        throw VerificationError.failed(label)
    }

    private enum VerificationError: Error { case failed(String) }
}
#endif
