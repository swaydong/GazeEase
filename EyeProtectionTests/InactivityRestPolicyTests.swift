import XCTest
@testable import EyeProtection

final class InactivityRestPolicyTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testThresholdRequiresEnabledReliableActiveMonitoring() {
        XCTAssertFalse(reached(enabled: false, idleDuration: 300))
        XCTAssertFalse(reached(idleDuration: 300, monitoringAvailable: false))
        XCTAssertFalse(reached(idleDuration: 300, systemAway: true))
        XCTAssertFalse(reached(idleDuration: 300, isResting: true))
        XCTAssertFalse(reached(idleDuration: nil))
        XCTAssertFalse(reached(idleDuration: .nan))
        XCTAssertFalse(reached(idleDuration: -1))
    }

    func testThresholdTriggersOnlyAtConfiguredDuration() {
        XCTAssertFalse(reached(idleDuration: 299.999))
        XCTAssertTrue(reached(idleDuration: 300))
        XCTAssertTrue(reached(idleDuration: 900))
    }

    func testSameIdlePeriodIsHandledOnlyOnceAndNewInputStartsAnotherPeriod() {
        let completionDuringCurrentIdlePeriod = now.addingTimeInterval(-60)
        XCTAssertFalse(reached(
            idleDuration: 300,
            lastCompletedAt: completionDuringCurrentIdlePeriod
        ))

        let completionBeforeNewInput = now.addingTimeInterval(-600)
        XCTAssertTrue(reached(
            idleDuration: 300,
            lastCompletedAt: completionBeforeNewInput
        ))
    }

    private func reached(
        enabled: Bool = true,
        idleDuration: TimeInterval?,
        lastCompletedAt: Date? = nil,
        monitoringAvailable: Bool = true,
        systemAway: Bool = false,
        isResting: Bool = false
    ) -> Bool {
        InactivityRestPolicy.thresholdReached(
            enabled: enabled,
            thresholdMinutes: 5,
            idleDuration: idleDuration,
            now: now,
            lastCompletedAt: lastCompletedAt,
            monitoringAvailable: monitoringAvailable,
            systemAway: systemAway,
            isResting: isResting
        )
    }
}
