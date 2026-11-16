import XCTest
@testable import Rivulet

final class FocusScrollMotionTests: XCTestCase {
    private let frame60 = 1.0 / 60

    /// Runs the spring from rest at 60 Hz until it reports done.
    private func runSpring(to target: CGFloat, response: Double) -> (frames: Int, maxY: CGFloat, first: CGFloat, end: CGFloat) {
        var y: CGFloat = 0, v: CGFloat = 0, frames = 0, maxY: CGFloat = 0
        var first: CGFloat?
        while frames < 600 {
            let s = FocusScrollMotion.spring(from: y, to: target, velocity: v, dt: frame60,
                                             viewport: 1080, response: response)
            first = first ?? s.y
            y = s.y; v = s.velocity; frames += 1; maxY = max(maxY, y)
            if s.done { break }
        }
        return (frames, maxY, first!, y)
    }

    func test_spring_startsGently_settlesOnTarget_withoutOvershoot() {
        let r = runSpring(to: 450, response: FocusScrollMotion.verticalResponse)
        XCTAssertLessThan(r.first, 20, "eases in from rest, no kick")
        XCTAssertEqual(r.end, 450)
        XCTAssertLessThanOrEqual(r.maxY, 450, "critically damped: no overshoot from rest")
        XCTAssertLessThan(r.frames, 45, "settles within ~0.75 s")
    }

    func test_spring_retargetKeepsSpeed() {
        var y: CGFloat = 0, v: CGFloat = 0
        for _ in 0..<6 {
            let s = FocusScrollMotion.spring(from: y, to: 300, velocity: v, dt: frame60, viewport: 1080,
                                             response: FocusScrollMotion.rowResponse)
            y = s.y; v = s.velocity
        }
        let s = FocusScrollMotion.spring(from: y, to: 600, velocity: v, dt: frame60, viewport: 1080,
                                         response: FocusScrollMotion.rowResponse)
        XCTAssertGreaterThan(s.velocity, v, "a further target speeds the glide up instead of restarting it")
    }

    func test_spring_farTargetIsBroughtToTwoViewports() {
        let s = FocusScrollMotion.spring(from: 0, to: 10_000, velocity: 0, dt: frame60, viewport: 1000, response: 0.4)
        XCTAssertGreaterThanOrEqual(s.y, 8000)
    }

    func test_minimalOffset_keepsEdgeInsetAndOnlyMovesWhenNeeded() {
        let row = CGRect(x: 0, y: 1500, width: 260, height: 430)
        XCTAssertEqual(FocusScrollMotion.minimalOffset(revealing: row, from: 0, height: 1080), 1500 + 430 - 1080 + 180)
        XCTAssertEqual(FocusScrollMotion.minimalOffset(revealing: row, from: 1100, height: 1080), 1100)
        XCTAssertEqual(FocusScrollMotion.minimalOffset(revealing: row, from: 2000, height: 1080), 1500 - 180)
    }
}
