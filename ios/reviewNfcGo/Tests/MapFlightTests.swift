import Foundation

@main
struct MapFlightTests {
    static func main() {
        var checks = 0
        func check(_ condition: @autoclosure () -> Bool, _ label: String) {
            precondition(condition(), label)
            checks += 1
        }
        func near(_ a: Double, _ b: Double) -> Bool { abs(a - b) < 0.00001 }
        let start = MapFlightPlan.Viewport(x: 100, y: 200, width: 100, height: 200)
        let destination = MapFlightPlan.Viewport(x: 1500, y: 3000, width: 60, height: 120)
        let plan = MapFlightPlan(start: start, destination: destination, worldWidth: 10000)
        let zoom = MapFlightPlan.zoomDuration
        let out = plan.frame(at: zoom / 2)
        check(out.phase == .zoomOut && near(out.viewport.x, start.x) && near(out.viewport.y, start.y), "Zoom out without moving")
        check(out.viewport.width > start.width, "Zoom actually widens the viewport")
        let travel = plan.frame(at: zoom)
        check(travel.phase == .travel, "Travel begins after zoom out")
        check(abs(plan.destination.x - start.x) / travel.viewport.width <= 0.70001, "Horizontal journey fits 70% of viewport")
        check(abs(plan.destination.y - start.y) / travel.viewport.height <= 0.70001, "Vertical journey fits 70% of viewport")
        let mid = plan.frame(at: zoom + 0.5)
        check(near(mid.viewport.x, (start.x + destination.x) / 2), "Halfway across at half a second")
        check(near(mid.viewport.width, travel.viewport.width), "No zoom while travelling")
        check(plan.frame(at: zoom + 0.999).phase == .travel, "Journey continues for one second")
        let arrival = plan.frame(at: zoom + 1)
        check(arrival.phase == .zoomIn && near(arrival.viewport.x, destination.x) && near(arrival.viewport.y, destination.y), "Arrive before zooming in")
        let final = plan.frame(at: MapFlightPlan.duration)
        check(final.phase == .finished && near(final.viewport.width, destination.width) && near(final.viewport.height, destination.height), "Exact final zoom")
        check(near(MapFlightPlan.duration, 2.3), "Total time is 2.3 seconds")
        check(near(plan.frame(at: -1).viewport.width, start.width), "Early frames are clamped")
        check(plan.frame(at: 100).viewport.width == destination.width, "Late frames stay at destination")
        let wrapped = MapFlightPlan(start: .init(x: 9950, y: 100, width: 30, height: 60),
            destination: .init(x: 50, y: 100, width: 30, height: 60), worldWidth: 10000)
        check(near(wrapped.destination.x - wrapped.start.x, 100), "Shortest eastbound date-line crossing")
        let west = MapFlightPlan(start: .init(x: 50, y: 100, width: 30, height: 60),
            destination: .init(x: 9950, y: 100, width: 30, height: 60), worldWidth: 10000)
        check(near(west.destination.x - west.start.x, -100), "Shortest westbound date-line crossing")
        let same = MapFlightPlan(start: start, destination: start, worldWidth: 10000)
        check(same.frame(at: 1).viewport.width.isFinite, "Same destination stays finite")
        let interrupted = MapFlightPlan(start: mid.viewport, destination: start, worldWidth: 10000)
        check(near(interrupted.frame(at: 0).viewport.x, mid.viewport.x) && near(interrupted.frame(at: 0).viewport.width, mid.viewport.width), "Interrupted flight continues from visible camera")
        print("Map flight: \(checks) checks passed")
    }
}
