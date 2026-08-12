import XCTest
@testable import EyeProtection

final class PresenceEngineTests: XCTestCase {
    private let origin = Date(timeIntervalSince1970: 2_000_000)

    func testObservationCannotStartASessionWithoutInput() {
        var engine = PresenceEngine()

        let update = engine.ingest(sample(at: 0))

        XCTAssertEqual(update.state, .idleUncertain)
        XCTAssertNil(engine.lastInputAt)
        XCTAssertFalse(update.events.contains { event in
            if case .sessionStarted = event { return true }
            return false
        })
    }

    func testInputStartsSessionAndActiveWindowIncludesTenSeconds() {
        var engine = PresenceEngine()

        let start = engine.ingest(sample(at: 0, inputDetected: true))
        let boundary = engine.ingest(sample(at: 10))
        let afterBoundary = engine.ingest(sample(at: 10.001))

        XCTAssertEqual(start.state, .activeInteraction)
        XCTAssertEqual(boundary.state, .activeInteraction)
        XCTAssertEqual(afterBoundary.state, .passiveStatic)
    }

    func testTwentySecondsWithoutInputRemainsPassiveStaticAndContributesToFatigue() {
        var engine = PresenceEngine()
        engine.ingest(sample(at: 0, inputDetected: true))

        let update = engine.ingest(sample(at: 20))

        XCTAssertEqual(update.state, .passiveStatic)
        XCTAssertTrue(update.state.contributesToFatigue)
    }

    func testStaticWindowUsesLastRealInputAndExpiresAfterFifteenMinutes() {
        var engine = PresenceEngine()
        engine.ingest(sample(at: 0, inputDetected: true))

        XCTAssertEqual(engine.ingest(sample(at: 180)).state, .passiveStatic)
        XCTAssertEqual(engine.ingest(sample(at: 899)).state, .passiveStatic)
        XCTAssertEqual(engine.ingest(sample(at: 900)).state, .passiveStatic)
        XCTAssertEqual(engine.ingest(sample(at: 901)).state, .idleUncertain)
        XCTAssertNil(engine.lastInputAt)
    }

    func testMissingInputPermissionIsUnobservableAndRequiresNewInputAfterRestore() {
        var engine = PresenceEngine()
        engine.ingest(sample(at: 0, inputDetected: true))

        let denied = engine.ingest(
            sample(
                at: 5,
                authorization: MonitoringAuthorization(inputMonitoringGranted: false)
            )
        )
        let restored = engine.ingest(sample(at: 6))
        let restarted = engine.ingest(sample(at: 7, inputDetected: true))

        XCTAssertEqual(denied.state, .unobservable)
        XCTAssertEqual(restored.state, .idleUncertain)
        XCTAssertEqual(restarted.state, .activeInteraction)
        XCTAssertEqual(engine.lastInputAt, origin.addingTimeInterval(7))
    }

    func testInputOnlyRuntimeIsCompleteAndObservable() {
        let runtime = MonitoringRuntimeStatus(inputMonitorRunning: true)
        var engine = PresenceEngine()

        engine.ingest(PresenceSample(
            timestamp: origin,
            inputDetected: true,
            authorization: runtime.authorization
        ))
        let update = engine.ingest(PresenceSample(
            timestamp: origin.addingTimeInterval(11),
            inputDetected: false,
            authorization: runtime.authorization
        ))

        XCTAssertTrue(runtime.isComplete)
        XCTAssertTrue(runtime.authorization.isFullyGranted)
        XCTAssertEqual(update.state, .passiveStatic)
        XCTAssertTrue(update.state.contributesToFatigue)
    }

    func testInputOnlyActivityCanAccrueToFatigueThreshold() {
        var presence = PresenceEngine()
        var fatigue = FatigueEngine()
        presence.ingest(sample(at: 0, inputDetected: true))

        for minute in 1...20 {
            let elapsed = TimeInterval(minute * 60)
            let update = presence.ingest(
                sample(at: elapsed, inputDetected: true)
            )
            if update.state.contributesToFatigue {
                fatigue.accrueUsage(
                    for: 60,
                    endingAt: origin.addingTimeInterval(elapsed)
                )
            }
        }

        XCTAssertEqual(fatigue.snapshot.fatiguePercent, 100, accuracy: 0.000_001)
        XCTAssertTrue(fatigue.snapshot.restRequired)
    }

    func testLongInactivityFreezesFatigueWithoutStartingRest() {
        var presence = PresenceEngine()
        var fatigue = FatigueEngine()
        presence.ingest(sample(at: 0, inputDetected: true))
        fatigue.accrueUsage(for: 600, endingAt: origin.addingTimeInterval(600))

        let idle = presence.ingest(sample(at: 901))

        XCTAssertEqual(idle.state, .idleUncertain)
        XCTAssertFalse(idle.state.contributesToFatigue)
        XCTAssertEqual(fatigue.snapshot.fatiguePercent, 50, accuracy: 0.000_001)
        XCTAssertNil(fatigue.snapshot.activeRest)
    }

    func testSystemAwayStatesEndSessionAndReturnNeedsFreshInput() {
        for systemState in [
            SystemPresenceState.locked,
            .displayAsleep,
            .systemAsleep
        ] {
            var engine = PresenceEngine()
            engine.ingest(sample(at: 0, inputDetected: true))

            let away = engine.ingest(sample(at: 2, systemState: systemState))
            let returned = engine.ingest(sample(at: 30))

            XCTAssertEqual(away.state, .awayConfirmed)
            XCTAssertEqual(returned.state, .idleUncertain)
            XCTAssertNil(engine.lastInputAt)
        }
    }

    func testNonMonotonicSampleIsRejectedWithoutMutatingState() {
        var engine = PresenceEngine()
        engine.ingest(sample(at: 10, inputDetected: true))

        let rejected = engine.ingest(sample(at: 9))

        XCTAssertEqual(rejected.state, .activeInteraction)
        XCTAssertEqual(engine.lastObservationAt, origin.addingTimeInterval(10))
        XCTAssertEqual(
            rejected.events,
            [.sampleRejected(at: origin.addingTimeInterval(9), reason: .nonMonotonicTimestamp)]
        )
    }

    func testCompletedRestRequiresFreshInputBeforeUsageResumes() {
        var engine = PresenceEngine()
        engine.ingest(sample(at: 0, inputDetected: true))

        engine.resetAfterCompletedRest(at: origin.addingTimeInterval(20))
        let noFreshInput = engine.ingest(sample(at: 21))
        let freshInput = engine.ingest(sample(at: 22, inputDetected: true))

        XCTAssertEqual(noFreshInput.state, .idleUncertain)
        XCTAssertFalse(noFreshInput.state.contributesToFatigue)
        XCTAssertEqual(freshInput.state, .activeInteraction)
        XCTAssertTrue(freshInput.state.contributesToFatigue)
    }

    private func sample(
        at offset: TimeInterval,
        inputDetected: Bool = false,
        authorization: MonitoringAuthorization = .fullyGranted,
        systemState: SystemPresenceState = .available
    ) -> PresenceSample {
        PresenceSample(
            timestamp: origin.addingTimeInterval(offset),
            inputDetected: inputDetected,
            authorization: authorization,
            systemState: systemState
        )
    }
}
