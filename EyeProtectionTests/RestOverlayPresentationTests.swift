import XCTest
@testable import EyeProtection

final class RestOverlayPresentationTests: XCTestCase {
    func testDecisionCopyUsesExactFatigueAndReminderDuration() {
        let presentation = RestOverlayPresentation(
            mode: .decision,
            fatigueDisplay: "1.2k%",
            overloadDuration: 60,
            restSecondsRemaining: 0,
            restProgress: 0
        )

        XCTAssertEqual(
            presentation.decisionDetailText,
            "当前疲劳度 1.2k% · 距首次提醒 1 分钟"
        )
        XCTAssertEqual(
            presentation.decisionAccessibilityValue,
            "当前疲劳度 1.2k%，距首次提醒 1 分钟"
        )
    }

    func testRestingValuesAreRoundedAndClampedForDisplay() {
        let presentation = RestOverlayPresentation(
            mode: .resting,
            fatigueDisplay: "90%",
            overloadDuration: 0,
            restSecondsRemaining: 9.01,
            restProgress: 1.4
        )

        XCTAssertEqual(presentation.wholeSecondsRemaining, 10)
        XCTAssertEqual(presentation.clampedRestProgress, 1)
        XCTAssertEqual(presentation.restingAccessibilityLabel, "正在休息，还剩 10 秒")
    }

    func testRestingValuesNeverExposeNegativeNumbers() {
        let presentation = RestOverlayPresentation(
            mode: .resting,
            fatigueDisplay: "0%",
            overloadDuration: 0,
            restSecondsRemaining: -3,
            restProgress: -0.2
        )

        XCTAssertEqual(presentation.wholeSecondsRemaining, 0)
        XCTAssertEqual(presentation.clampedRestProgress, 0)
        XCTAssertEqual(presentation.restingAccessibilityLabel, "正在休息，还剩 0 秒")
    }

    func testDecisionButtonsRemainEqualSized() {
        XCTAssertEqual(RestOverlayLayout.actionButtonSize, CGSize(width: 210, height: 52))
        XCTAssertEqual(RestOverlayLayout.actionSpacing, 24)
        XCTAssertGreaterThanOrEqual(
            RestOverlayLayout.decisionContentWidth,
            (RestOverlayLayout.actionButtonSize.width * 2) + RestOverlayLayout.actionSpacing
        )
    }
}
