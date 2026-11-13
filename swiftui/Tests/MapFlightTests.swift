import Foundation
@main struct MapFlightTests {
    static func main() {
        var checks = 0
        func check(_ value: @autoclosure () -> Bool, _ name: String) { precondition(value(), name); checks += 1 }
        func near(_ a: Double, _ b: Double) -> Bool { abs(a-b) < 0.00001 }
        let start = MapFlightPlan.Viewport(x: 100, y: 200, width: 100, height: 200)
        let target = MapFlightPlan.Viewport(x: 1500, y: 3000, width: 60, height: 120)
        let plan = MapFlightPlan(start: start, destination: target, worldWidth: 10000)
        let early = plan.frame(at: 0.5).viewport, middle = plan.frame(at: 1.15).viewport, late = plan.frame(at: 1.9).viewport
        check(early.x > start.x && early.y > start.y && early.width > start.width, "Pan and zoom out overlap")
        check(late.x < target.x && late.y < target.y && late.width > target.width, "Pan continues during zoom in")
        check(middle.width > early.width && middle.width > late.width, "Zoom follows a continuous wide arc")
        check(plan.frame(at: -1).viewport.x == start.x && plan.frame(at: 0).viewport.width == start.width, "Exact initial camera")
        check(plan.frame(at: 3).phase == .finished && plan.frame(at: 3).viewport.width == target.width, "Exact destination and zoom")
        var previous = start
        for index in 1...230 {
            let frame = plan.frame(at: Double(index)/100).viewport
            check(frame.width.isFinite && frame.width > 0 && frame.height > 0, "Finite viewport at every frame")
            check(frame.x >= previous.x - 0.00001 && frame.y >= previous.y - 0.00001, "No backtracking or abrupt stage changes")
            previous = frame
        }
        let wrapped = MapFlightPlan(start: .init(x: 9950,y: 100,width: 30,height: 60), destination: .init(x: 50,y: 100,width: 30,height: 60), worldWidth: 10000)
        check(near(wrapped.destination.x - wrapped.start.x, 100), "Short date-line route")
        let same = MapFlightPlan(start: start, destination: start, worldWidth: 10000)
        check(near(same.frame(at: 1).viewport.width, 100), "Identical centers stay finite")
        let zoom = MapFlightPlan(start: start, destination: .init(x: 100,y: 200,width: 10,height: 20), worldWidth: 10000)
        check(zoom.frame(at: 1).viewport.width < start.width && zoom.frame(at: 1).viewport.x == start.x, "Same center zooms smoothly")
        let interrupted = MapFlightPlan(start: middle, destination: start, worldWidth: 10000)
        check(near(interrupted.frame(at: 0).viewport.width, middle.width) && near(interrupted.frame(at: 0).viewport.x, middle.x), "Interrupted flight begins at current visible camera")
        print("Continuous map flight: \(checks) checks passed")
    }
}
