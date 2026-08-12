import XCTest
@testable import EyeProtection

final class BoundedIntegerInputRuleTests: XCTestCase {
    func testValidIntegerIsReadyToApplyOnce() {
        let result = BoundedIntegerInputRule.commit(
            draft: "120",
            current: 20,
            range: 1...180
        )

        XCTAssertEqual(result, BoundedIntegerInputCommit(value: 120, shouldApply: true))
    }

    func testWhitespaceIsTrimmedAndSameValueDoesNotApplyAgain() {
        let result = BoundedIntegerInputRule.commit(
            draft: " 20 \n",
            current: 20,
            range: 1...180
        )

        XCTAssertEqual(result, BoundedIntegerInputCommit(value: 20, shouldApply: false))
    }

    func testOutOfRangeValuesAreClamped() {
        XCTAssertEqual(
            BoundedIntegerInputRule.commit(draft: "0", current: 20, range: 1...180),
            BoundedIntegerInputCommit(value: 1, shouldApply: true)
        )
        XCTAssertEqual(
            BoundedIntegerInputRule.commit(draft: "181", current: 20, range: 1...180),
            BoundedIntegerInputCommit(value: 180, shouldApply: true)
        )
        XCTAssertEqual(
            BoundedIntegerInputRule.commit(draft: "4", current: 20, range: 5...300),
            BoundedIntegerInputCommit(value: 5, shouldApply: true)
        )
        XCTAssertEqual(
            BoundedIntegerInputRule.commit(draft: "301", current: 20, range: 5...300),
            BoundedIntegerInputCommit(value: 300, shouldApply: true)
        )
    }

    func testInvalidOrOverflowingInputKeepsCurrentValue() {
        for draft in ["", "   ", "abc", "20.5", "999999999999999999999999"] {
            XCTAssertEqual(
                BoundedIntegerInputRule.commit(draft: draft, current: 20, range: 1...180),
                BoundedIntegerInputCommit(value: 20, shouldApply: false)
            )
        }
    }

    func testRandomThemeRotationIntervalUsesFiveMinutesThroughOneDay() {
        let range = Preferences.randomThemeRotationIntervalMinutesRange

        XCTAssertEqual(
            BoundedIntegerInputRule.commit(draft: "4", current: 60, range: range),
            BoundedIntegerInputCommit(value: 5, shouldApply: true)
        )
        XCTAssertEqual(
            BoundedIntegerInputRule.commit(draft: "60", current: 30, range: range),
            BoundedIntegerInputCommit(value: 60, shouldApply: true)
        )
        XCTAssertEqual(
            BoundedIntegerInputRule.commit(draft: "1441", current: 60, range: range),
            BoundedIntegerInputCommit(value: 1_440, shouldApply: true)
        )
        XCTAssertEqual(
            BoundedIntegerInputRule.commit(draft: "nope", current: 60, range: range),
            BoundedIntegerInputCommit(value: 60, shouldApply: false)
        )
    }
}
