import XCTest
@testable import EyeProtection

final class FatigueValueFormatterTests: XCTestCase {
    func testRegularAndCompactPercentages() {
        XCTAssertEqual(FatigueValueFormatter.display(63.4), "63%")
        XCTAssertEqual(FatigueValueFormatter.display(999), "999%")
        XCTAssertEqual(FatigueValueFormatter.display(1_000), "1.0k%")
        XCTAssertEqual(FatigueValueFormatter.display(1_200), "1.2k%")
    }

    func testInvalidValuesAreClampedForDisplay() {
        XCTAssertEqual(FatigueValueFormatter.display(-5), "0%")
        XCTAssertEqual(FatigueValueFormatter.display(.infinity), "0%")
    }

    func testDisplayNeverShowsOneHundredBeforeActualThreshold() {
        XCTAssertEqual(FatigueValueFormatter.display(99.49), "99%")
        XCTAssertEqual(FatigueValueFormatter.display(99.5), "99%")
        XCTAssertEqual(FatigueValueFormatter.display(99.999), "99%")
        XCTAssertEqual(FatigueValueFormatter.display(100), "100%")
    }
}
