import Foundation

/// Continuous pan/zoom in projected space: a zooming camera follows the same smooth
/// curve as its moving center, with no pauses or separate animation stages.
struct MapFlightPlan {
    struct Viewport { let x: Double; let y: Double; let width: Double; let height: Double }
    enum Phase: String { case flight, finished }
    struct Frame { let viewport: Viewport; let phase: Phase }
    static let duration = 2.3
    let start: Viewport
    let destination: Viewport
    private let distance: Double
    private let r0: Double
    private let pathLength: Double
    private let rho = sqrt(2.0)

    init(start: Viewport, destination: Viewport, worldWidth: Double) {
        self.start = start
        var dx = (destination.x - start.x).truncatingRemainder(dividingBy: worldWidth)
        if dx > worldWidth / 2 { dx -= worldWidth }
        if dx < -worldWidth / 2 { dx += worldWidth }
        self.destination = Viewport(x: start.x + dx, y: destination.y, width: destination.width, height: destination.height)
        let aspect = start.width / start.height
        let d = hypot(dx, (destination.y - start.y) * aspect)
        distance = d
        if d > 0.000001 {
            let w0 = start.width, w1 = destination.width
            let common = w1 * w1 - w0 * w0
            let b0 = (common + 4 * d * d) / (4 * w0 * d)
            let b1 = (common - 4 * d * d) / (4 * w1 * d)
            r0 = -asinh(b0)
            pathLength = (-asinh(b1) - r0) / sqrt(2)
        } else { r0 = 0; pathLength = 0 }
    }
    func frame(at elapsed: Double) -> Frame {
        if elapsed <= 0 { return Frame(viewport: start, phase: .flight) }
        if elapsed >= Self.duration { return Frame(viewport: destination, phase: .finished) }
        let t = elapsed / Self.duration
        let eased = t * t * t * (t * (t * 6 - 15) + 10)
        let progress: Double, width: Double
        if distance > 0.000001 {
            let s = eased * pathLength
            progress = min(1, max(0, start.width / (rho * rho * distance) * (cosh(r0) * tanh(rho * s + r0) - sinh(r0))))
            width = start.width * cosh(r0) / cosh(rho * s + r0)
        } else {
            progress = eased
            width = exp(log(start.width) + (log(destination.width) - log(start.width)) * eased)
        }
        let aspect = exp(log(start.width / start.height) + (log(destination.width / destination.height) - log(start.width / start.height)) * eased)
        return Frame(viewport: Viewport(x: start.x + (destination.x - start.x) * progress,
            y: start.y + (destination.y - start.y) * progress, width: width, height: width / aspect), phase: .flight)
    }
}
