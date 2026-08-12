import XCTest
@testable import EyeProtection

final class FatigueEngineTests: XCTestCase {
    private let origin = Date(timeIntervalSince1970: 1_000_000)

    func testTwentyMinutesReachesOneHundredAndLatchesRestRequirement() {
        var engine = FatigueEngine()

        let events = engine.accrueUsage(
            for: 20 * 60,
            endingAt: origin.addingTimeInterval(20 * 60)
        )

        XCTAssertEqual(engine.snapshot.fatiguePercent, 100, accuracy: 0.000_001)
        XCTAssertTrue(engine.snapshot.restRequired)
        let thresholdTime = origin.addingTimeInterval(20 * 60)
        XCTAssertEqual(engine.snapshot.overloadStartedAt, thresholdTime)
        XCTAssertEqual(engine.snapshot.activeOverloadEpisode?.startedAt, thresholdTime)
        XCTAssertEqual(restRequiredEventCount(in: events), 1)
    }

    func testThresholdTimeIsInterpolatedWithinUsageInterval() {
        var engine = FatigueEngine()
        engine.accrueUsage(
            for: 10 * 60,
            endingAt: origin.addingTimeInterval(10 * 60)
        )

        engine.accrueUsage(
            for: 20 * 60,
            endingAt: origin.addingTimeInterval(30 * 60)
        )

        XCTAssertEqual(
            engine.snapshot.overloadStartedAt,
            origin.addingTimeInterval(20 * 60)
        )
    }

    func testCustomThirtyMinuteUsageDurationReachesThresholdAndContinuesPastIt() {
        var engine = FatigueEngine(
            usageDurationForOneHundredPercent: 30 * 60,
            requiredContinuousRestDuration: 30
        )

        engine.accrueUsage(
            for: 30 * 60,
            endingAt: origin.addingTimeInterval(30 * 60)
        )
        XCTAssertEqual(engine.snapshot.fatiguePercent, 100, accuracy: 0.000_001)
        XCTAssertTrue(engine.snapshot.restRequired)

        engine.accrueUsage(
            for: 30 * 60,
            endingAt: origin.addingTimeInterval(60 * 60)
        )
        XCTAssertEqual(engine.snapshot.fatiguePercent, 200, accuracy: 0.000_001)
    }

    func testCustomThirtySecondRestUsesConfiguredProgressAndCompletionTime() {
        var engine = FatigueEngine(requiredContinuousRestDuration: 30)
        engine.accrueUsage(for: 2_160, endingAt: origin.addingTimeInterval(2_160))
        let restStart = origin.addingTimeInterval(2_160)

        engine.beginRest(trigger: .manual, at: restStart)
        engine.advanceRest(by: 15, endingAt: restStart.addingTimeInterval(15))

        XCTAssertEqual(engine.snapshot.fatiguePercent, 90, accuracy: 0.000_001)
        XCTAssertEqual(engine.restProgress, 0.5, accuracy: 0.000_001)
        XCTAssertEqual(engine.restRemaining, 15, accuracy: 0.000_001)

        let events = engine.advanceRest(by: 20, endingAt: restStart.addingTimeInterval(35))
        guard case let .restCompleted(attempt)? = events.first(where: { event in
            if case .restCompleted = event { return true }
            return false
        }) else {
            return XCTFail("Expected a completed rest attempt")
        }
        XCTAssertEqual(attempt.duration, 30, accuracy: 0.000_001)
        XCTAssertEqual(attempt.endedAt, restStart.addingTimeInterval(30))
        XCTAssertEqual(engine.snapshot.fatiguePercent, 0, accuracy: 0.000_001)
    }

    func testUsageDurationUpdateRescalesFatigueAndIsRejectedDuringActiveRest() throws {
        var engine = FatigueEngine()
        engine.accrueUsage(for: 10 * 60, endingAt: origin.addingTimeInterval(10 * 60))
        XCTAssertEqual(engine.snapshot.fatiguePercent, 50, accuracy: 0.000_001)

        let updateEvents = try XCTUnwrap(engine.updateDurations(
            usageDurationForOneHundredPercent: 30 * 60,
            requiredContinuousRestDuration: 30,
            at: origin.addingTimeInterval(10 * 60)
        ))
        XCTAssertEqual(engine.snapshot.fatiguePercent, 100.0 / 3.0, accuracy: 0.000_001)
        XCTAssertEqual(updateEvents.count, 1)

        engine.accrueUsage(for: 20 * 60, endingAt: origin.addingTimeInterval(30 * 60))
        XCTAssertEqual(engine.snapshot.fatiguePercent, 100, accuracy: 0.000_001)

        engine.beginRest(trigger: .manual, at: origin.addingTimeInterval(30 * 60))
        XCTAssertNil(engine.updateDurations(
            usageDurationForOneHundredPercent: 60 * 60,
            requiredContinuousRestDuration: 60,
            at: origin.addingTimeInterval(30 * 60)
        ))
        XCTAssertEqual(engine.usageDurationForOneHundredPercent, 30 * 60)
        XCTAssertEqual(engine.requiredContinuousRestDuration, 30)
    }

    func testRestDurationUpdateDoesNotChangeFatigue() throws {
        var engine = FatigueEngine()
        engine.accrueUsage(for: 10 * 60, endingAt: origin.addingTimeInterval(10 * 60))

        let events = try XCTUnwrap(engine.updateDurations(
            usageDurationForOneHundredPercent: 20 * 60,
            requiredContinuousRestDuration: 45,
            at: origin.addingTimeInterval(10 * 60)
        ))

        XCTAssertTrue(events.isEmpty)
        XCTAssertEqual(engine.snapshot.fatiguePercent, 50, accuracy: 0.000_001)
        XCTAssertEqual(engine.requiredContinuousRestDuration, 45)
    }

    func testShorterUsageDurationCanImmediatelyCreateOneOverloadEpisode() throws {
        var engine = FatigueEngine()
        engine.accrueUsage(for: 10 * 60, endingAt: origin.addingTimeInterval(10 * 60))
        let changedAt = origin.addingTimeInterval(10 * 60 + 1)

        let firstEvents = try XCTUnwrap(engine.updateDurations(
            usageDurationForOneHundredPercent: 10 * 60,
            requiredContinuousRestDuration: 20,
            at: changedAt
        ))
        let episodeID = try XCTUnwrap(engine.snapshot.activeOverloadEpisode?.id)

        XCTAssertEqual(engine.snapshot.fatiguePercent, 100, accuracy: 0.000_001)
        XCTAssertTrue(engine.snapshot.restRequired)
        XCTAssertEqual(engine.snapshot.overloadStartedAt, changedAt)
        XCTAssertEqual(restRequiredEventCount(in: firstEvents), 1)

        let secondEvents = try XCTUnwrap(engine.updateDurations(
            usageDurationForOneHundredPercent: 5 * 60,
            requiredContinuousRestDuration: 20,
            at: changedAt.addingTimeInterval(1)
        ))

        XCTAssertEqual(engine.snapshot.fatiguePercent, 200, accuracy: 0.000_001)
        XCTAssertEqual(engine.snapshot.activeOverloadEpisode?.id, episodeID)
        XCTAssertEqual(engine.snapshot.activeOverloadEpisode?.peakFatiguePercent, 200)
        XCTAssertEqual(restRequiredEventCount(in: secondEvents), 0)
    }

    func testLongerUsageDurationKeepsExistingRestRequirementLatched() throws {
        var engine = FatigueEngine()
        engine.accrueUsage(for: 20 * 60, endingAt: origin.addingTimeInterval(20 * 60))
        let episodeID = try XCTUnwrap(engine.snapshot.activeOverloadEpisode?.id)
        let overloadStartedAt = engine.snapshot.overloadStartedAt

        let events = try XCTUnwrap(engine.updateDurations(
            usageDurationForOneHundredPercent: 40 * 60,
            requiredContinuousRestDuration: 20,
            at: origin.addingTimeInterval(20 * 60 + 1)
        ))

        XCTAssertEqual(engine.snapshot.fatiguePercent, 50, accuracy: 0.000_001)
        XCTAssertTrue(engine.snapshot.restRequired)
        XCTAssertEqual(engine.snapshot.activeOverloadEpisode?.id, episodeID)
        XCTAssertEqual(engine.snapshot.overloadStartedAt, overloadStartedAt)
        XCTAssertEqual(restRequiredEventCount(in: events), 0)
    }

    func testFortyMinutesReachesTwoHundredWithoutCreatingAnotherEpisode() {
        var engine = FatigueEngine()
        let firstEvents = engine.accrueUsage(
            for: 20 * 60,
            endingAt: origin.addingTimeInterval(20 * 60)
        )
        let secondEvents = engine.accrueUsage(
            for: 20 * 60,
            endingAt: origin.addingTimeInterval(40 * 60)
        )

        XCTAssertEqual(engine.snapshot.fatiguePercent, 200, accuracy: 0.000_001)
        XCTAssertEqual(engine.snapshot.activeOverloadEpisode?.peakFatiguePercent, 200)
        XCTAssertEqual(restRequiredEventCount(in: firstEvents), 1)
        XCTAssertEqual(restRequiredEventCount(in: secondEvents), 0)
    }

    func testDeferringRestKeepsLatchAndContinuesSameEpisode() throws {
        var engine = FatigueEngine()
        let thresholdAt = origin.addingTimeInterval(1_200)
        engine.accrueUsage(for: 1_200, endingAt: thresholdAt)
        let episodeID = try XCTUnwrap(engine.snapshot.activeOverloadEpisode?.id)

        let deferredAt = thresholdAt.addingTimeInterval(1)
        let deferredEvents = engine.recordContinueWorking(at: deferredAt)

        XCTAssertEqual(deferredEvents.count, 1)
        guard case let .continuedWorking(recordedAt) = deferredEvents[0] else {
            return XCTFail("Expected a deferred-rest event")
        }
        XCTAssertEqual(recordedAt, deferredAt)
        XCTAssertTrue(engine.snapshot.restRequired)
        XCTAssertNil(engine.snapshot.activeRest)
        XCTAssertEqual(engine.snapshot.fatiguePercent, 100, accuracy: 0.000_001)
        XCTAssertEqual(engine.snapshot.activeOverloadEpisode?.id, episodeID)

        let continuedEvents = engine.accrueUsage(
            for: 600,
            endingAt: thresholdAt.addingTimeInterval(601)
        )

        XCTAssertEqual(engine.snapshot.fatiguePercent, 150, accuracy: 0.000_001)
        XCTAssertTrue(engine.snapshot.restRequired)
        XCTAssertEqual(engine.snapshot.activeOverloadEpisode?.id, episodeID)
        XCTAssertEqual(engine.snapshot.activeOverloadEpisode?.peakFatiguePercent, 150)
        XCTAssertEqual(restRequiredEventCount(in: continuedEvents), 0)
    }

    func testTenSecondInterruptedRestFromOneHundredEightyKeepsNinetyAndLatch() {
        var engine = FatigueEngine()
        engine.accrueUsage(
            for: 36 * 60,
            endingAt: origin.addingTimeInterval(36 * 60)
        )
        let restStart = origin.addingTimeInterval(36 * 60)

        engine.beginRest(trigger: .manual, at: restStart)
        engine.advanceRest(by: 10, endingAt: restStart.addingTimeInterval(10))

        XCTAssertTrue(engine.isResting)
        XCTAssertEqual(engine.restProgress, 0.5, accuracy: 0.000_001)
        XCTAssertEqual(engine.restRemaining, 10, accuracy: 0.000_001)

        let interruptionEvents = engine.interruptRest(
            reason: .keyboard,
            at: restStart.addingTimeInterval(10)
        )

        XCTAssertEqual(engine.snapshot.fatiguePercent, 90, accuracy: 0.000_001)
        XCTAssertTrue(engine.snapshot.restRequired)
        XCTAssertNil(engine.snapshot.activeRest)
        XCTAssertFalse(engine.isResting)
        XCTAssertEqual(engine.restProgress, 0)
        XCTAssertEqual(engine.restRemaining, 0)
        guard case let .restInterrupted(attempt)? = interruptionEvents.first else {
            return XCTFail("Expected a rest interruption event")
        }
        XCTAssertEqual(attempt.duration, 10)
        XCTAssertEqual(attempt.endFatiguePercent, 90, accuracy: 0.000_001)
        XCTAssertEqual(attempt.outcome, .interrupted(.keyboard))
    }

    func testTwentyContinuousSecondsOfAnySystemRestClearsFatigueAndLatch() {
        for trigger in [
            RestTrigger.screenLocked,
            .displayAsleep,
            .systemSleep
        ] {
            var engine = FatigueEngine()
            engine.accrueUsage(
                for: 48 * 60,
                endingAt: origin.addingTimeInterval(48 * 60)
            )
            let restStart = origin.addingTimeInterval(48 * 60)

            engine.beginRest(trigger: trigger, at: restStart)
            let completionEvents = engine.advanceRest(
                by: 20,
                endingAt: restStart.addingTimeInterval(20)
            )

            XCTAssertEqual(engine.snapshot.fatiguePercent, 0, accuracy: 0.000_001)
            XCTAssertFalse(engine.snapshot.restRequired)
            XCTAssertNil(engine.snapshot.activeRest)
            XCTAssertNil(engine.snapshot.activeOverloadEpisode)
            XCTAssertTrue(completionEvents.contains { event in
                if case .restCompleted = event { return true }
                return false
            })
            XCTAssertTrue(completionEvents.contains { event in
                if case .overloadCompleted = event { return true }
                return false
            })
        }
    }

    func testUsageDoesNotChangeFatigueUntilActiveRestIsExplicitlyInterrupted() {
        var engine = FatigueEngine()
        engine.accrueUsage(for: 1_200, endingAt: origin.addingTimeInterval(1_200))
        engine.beginRest(trigger: .manual, at: origin.addingTimeInterval(1_200))

        let events = engine.accrueUsage(
            for: 60,
            endingAt: origin.addingTimeInterval(1_260)
        )

        XCTAssertTrue(events.isEmpty)
        XCTAssertEqual(engine.snapshot.fatiguePercent, 100, accuracy: 0.000_001)
    }

    func testCodableSnapshotRestoresLatchedPartialRestProgress() throws {
        var original = FatigueEngine()
        original.accrueUsage(for: 2_160, endingAt: origin.addingTimeInterval(2_160))
        original.beginRest(trigger: .manual, at: origin.addingTimeInterval(2_160))
        original.advanceRest(by: 10, endingAt: origin.addingTimeInterval(2_170))

        let data = try JSONEncoder().encode(original.snapshot)
        let decoded = try JSONDecoder().decode(FatigueSnapshot.self, from: data)
        let restored = FatigueEngine(snapshot: decoded)

        XCTAssertEqual(restored.snapshot.fatiguePercent, 90, accuracy: 0.000_001)
        XCTAssertTrue(restored.snapshot.restRequired)
        XCTAssertNotNil(restored.snapshot.overloadStartedAt)
        XCTAssertTrue(restored.isResting)
        XCTAssertEqual(restored.restProgress, 0.5, accuracy: 0.000_001)
        XCTAssertEqual(restored.restRemaining, 10, accuracy: 0.000_001)
    }

    func testTwoHourSecondBySecondUsageReachesSixHundredPercent() {
        var engine = FatigueEngine()

        for second in 1...7_200 {
            engine.accrueUsage(
                for: 1,
                endingAt: origin.addingTimeInterval(TimeInterval(second))
            )
        }

        XCTAssertEqual(engine.snapshot.fatiguePercent, 600, accuracy: 0.000_001)
        XCTAssertTrue(engine.snapshot.restRequired)
        XCTAssertEqual(
            engine.snapshot.activeOverloadEpisode?.peakFatiguePercent ?? -1,
            600,
            accuracy: 0.000_001
        )
    }

    func testConfirmedInactivityRestClearsFatigueAndLatchIndependentlyOfCountdown() throws {
        var engine = FatigueEngine(requiredContinuousRestDuration: 300)
        engine.accrueUsage(
            for: 36 * 60,
            endingAt: origin.addingTimeInterval(36 * 60)
        )
        let completedAt = origin.addingTimeInterval(36 * 60 + 60)

        let events = engine.completeConfirmedRest(
            trigger: .inactivity,
            qualifyingDuration: 60,
            endingAt: completedAt
        )

        XCTAssertEqual(engine.snapshot.fatiguePercent, 0, accuracy: 0.000_001)
        XCTAssertFalse(engine.snapshot.restRequired)
        XCTAssertNil(engine.snapshot.activeRest)
        XCTAssertNil(engine.snapshot.activeOverloadEpisode)

        guard case let .restCompleted(attempt)? = events.first(where: { event in
            if case .restCompleted = event { return true }
            return false
        }) else {
            return XCTFail("Expected a completed inactivity rest")
        }
        XCTAssertEqual(attempt.trigger, .inactivity)
        XCTAssertEqual(attempt.duration, 60, accuracy: 0.000_001)
        XCTAssertEqual(attempt.startedAt, completedAt.addingTimeInterval(-60))
        XCTAssertEqual(attempt.endedAt, completedAt)
        XCTAssertEqual(attempt.startFatiguePercent, 180, accuracy: 0.000_001)
        XCTAssertEqual(attempt.endFatiguePercent, 0, accuracy: 0.000_001)
        XCTAssertTrue(events.contains { event in
            if case .overloadCompleted = event { return true }
            return false
        })
    }

    private func restRequiredEventCount(in events: [FatigueEvent]) -> Int {
        events.reduce(into: 0) { count, event in
            if case .restRequired = event {
                count += 1
            }
        }
    }
}
