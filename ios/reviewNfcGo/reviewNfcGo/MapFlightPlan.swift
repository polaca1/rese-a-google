import Foundation

// Projected coordinates keep zoom and travel proportional to the visible viewport.
struct MapFlightPlan {
    struct Viewport {
        let x: Double
        let y: Double
        let width: Double
        let height: Double
    }
    enum Phase: String { case zoomOut, travel, zoomIn, finished }
    struct Frame {
        let viewport: Viewport
        let phase: Phase
    }
    static let zoomDuration = 0.65
    static let travelDuration = 1.0
    static let duration = zoomDuration * 2 + travelDuration
    let start: Viewport
    let destination: Viewport
    let overviewWidth: Double
    let overviewHeight: Double

    init(start: Viewport, destination: Viewport, worldWidth: Double) {
        self.start = start
        // Take the short route across the date line, including wrapped map views.
        var dx = (destination.x - start.x).truncatingRemainder(dividingBy: worldWidth)
        if dx > worldWidth / 2 { dx -= worldWidth }
        if dx < -worldWidth / 2 { dx += worldWidth }
        self.destination = Viewport(x: start.x + dx, y: destination.y,
                                    width: destination.width, height: destination.height)
        let aspect = start.width / start.height
        // The one-second journey spans at most 70% of either viewport dimension.
        // This determines the zoom-out from distance, rather than an arbitrary zoom level.
        let neededWidth = max(abs(dx) / 0.7, abs(destination.y - start.y) * aspect / 0.7)
        overviewWidth = max(start.width, destination.width, neededWidth)
        overviewHeight = overviewWidth / aspect
    }

    func frame(at elapsed: Double) -> Frame {
        let zoom = Self.zoomDuration
        if elapsed < zoom {
            let t = Self.ease(elapsed / zoom)
            return Frame(viewport: Viewport(x: start.x, y: start.y,
                width: Self.zoom(start.width, overviewWidth, t),
                height: Self.zoom(start.height, overviewHeight, t)), phase: .zoomOut)
        }
        if elapsed < zoom + Self.travelDuration {
            let t = Self.ease((elapsed - zoom) / Self.travelDuration)
            return Frame(viewport: Viewport(x: start.x + (destination.x - start.x) * t,
                y: start.y + (destination.y - start.y) * t,
                width: overviewWidth, height: overviewHeight), phase: .travel)
        }
        if elapsed < Self.duration {
            let t = Self.ease((elapsed - zoom - Self.travelDuration) / zoom)
            return Frame(viewport: Viewport(x: destination.x, y: destination.y,
                width: Self.zoom(overviewWidth, destination.width, t),
                height: Self.zoom(overviewHeight, destination.height, t)), phase: .zoomIn)
        }
        return Frame(viewport: destination, phase: .finished)
    }

    private static func ease(_ t: Double) -> Double {
        let t = min(1, max(0, t))
        return t * t * (3 - 2 * t)
    }
    private static func zoom(_ from: Double, _ to: Double, _ t: Double) -> Double {
        exp(log(from) + (log(to) - log(from)) * t)
    }
}
