import XCTest
@testable import EyeProtection

final class RestOverlayWindowAnimationTests: XCTestCase {
    func testDefaultTransitionDurations() {
        XCTAssertEqual(
            RestOverlayWindowAnimation.duration(for: .appearing, reduceMotion: false),
            0.30,
            accuracy: 0.001
        )
        XCTAssertEqual(
            RestOverlayWindowAnimation.duration(for: .disappearing, reduceMotion: false),
            0.22,
            accuracy: 0.001
        )
    }

    func testReduceMotionDisablesWindowTransitions() {
        XCTAssertEqual(
            RestOverlayWindowAnimation.duration(for: .appearing, reduceMotion: true),
            0
        )
        XCTAssertEqual(
            RestOverlayWindowAnimation.duration(for: .disappearing, reduceMotion: true),
            0
        )
    }
}
