// SPDX-License-Identifier: MIT
// The existing MapKit control and camera coordinator, mounted as a native Day piece.
import UIKit
import MapKit
import CoreLocation

struct DayMapInput {
    let selectedPlace: PlaceResult?
    let focusRequest: MapFocusRequest?
    let onTap: (CLLocationCoordinate2D) -> Void
}

@MainActor final class DayMapView: MKMapView {
    private let coordinator: DayMapCoordinator
    init() {
        let input = DayMapView.input()
        coordinator = DayMapCoordinator(parent: input)
        super.init(frame: .zero)
        delegate = coordinator
        showsUserLocation = true
        pointOfInterestFilter = .includingAll
        isRotateEnabled = false
        let tap = UITapGestureRecognizer(target: coordinator, action: #selector(DayMapCoordinator.didTap(_:)))
        tap.cancelsTouchesInView = false
        addGestureRecognizer(tap)
        refresh()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) unavailable") }
    private static func input() -> DayMapInput {
        let finder = DayServices.shared.finder
        return DayMapInput(selectedPlace: finder.selectedPlace, focusRequest: finder.mapFocus,
            onTap: { coordinate in Task { @MainActor in await DayServices.shared.finder.searchNearest(to: coordinate) } })
    }
    func refresh() {
        let input = Self.input(); coordinator.parent = input
        if coordinator.lastPlace != input.selectedPlace {
            coordinator.lastPlace = input.selectedPlace
            removeAnnotations(annotations.filter { !($0 is MKUserLocation) })
            if let place = input.selectedPlace {
                let pin = MKPointAnnotation(); pin.coordinate = place.coordinate
                pin.title = place.name; pin.subtitle = place.address; addAnnotation(pin)
            }
        }
        if let request = input.focusRequest, coordinator.lastFocusID != request.id {
            coordinator.lastFocusID = request.id; coordinator.focus(self, request: request)
        }
    }
}
    final class DayMapCoordinator: NSObject, MKMapViewDelegate {
        var parent: DayMapInput
        var lastPlace: PlaceResult?
        var lastFocusID: UUID?
        private weak var flightMap: MKMapView?
        private var flight: MapFlightPlan?
        var isFlying: Bool { flight != nil }
        private var flightRequest: MapFocusRequest?
        private var flightStarted: CFTimeInterval = 0
        private var displayLink: CADisplayLink?
        #if REVIEWNFCGO_LEGACY_VERIFICATION
        private var verificationElapsed: TimeInterval = 0
        #endif
        init(parent: DayMapInput) { self.parent = parent }
        deinit { displayLink?.invalidate() }

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
            #if REVIEWNFCGO_LEGACY_VERIFICATION
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
            #if REVIEWNFCGO_LEGACY_VERIFICATION
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
            #if REVIEWNFCGO_LEGACY_VERIFICATION
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

@MainActor @_cdecl("review_day_map_make") public func reviewDayMapMake() -> UnsafeMutableRawPointer {
    Unmanaged.passRetained(DayMapView()).toOpaque()
}
@MainActor @_cdecl("review_day_map_refresh") public func reviewDayMapRefresh(_ raw: UnsafeMutableRawPointer) {
    Unmanaged<DayMapView>.fromOpaque(raw).takeUnretainedValue().refresh()
}
