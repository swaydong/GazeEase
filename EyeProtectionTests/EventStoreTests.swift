import XCTest
@testable import EyeProtection

@MainActor
final class EventStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!
    private var store: EventStore!

    override func setUpWithError() throws {
        suiteName = "EyeProtectionTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        store = try EventStore(inMemory: true, defaults: defaults)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        store = nil
        defaults = nil
        suiteName = nil
    }

    func testContinuingWorkDoesNotCountAsRestResponse() {
        let now = Date()
        let episodeID = store.beginOverload(
            at: now.addingTimeInterval(-60),
            fatigue: 100
        )

        store.markOverloadResponse(
            id: episodeID,
            kind: "continued",
            at: now.addingTimeInterval(-50)
        )

        var analytics = store.analytics(now: now)
        XCTAssertEqual(analytics.today.continuedWorkingCount, 1)
        XCTAssertNil(analytics.today.averageResponseDuration)
        XCTAssertEqual(analytics.today.completedRestCount, 0)
        XCTAssertEqual(analytics.today.interruptedRestCount, 0)
        XCTAssertEqual(analytics.today.manualRestCount, 0)
        XCTAssertEqual(analytics.today.systemRestCount, 0)

        store.markOverloadResponse(
            id: episodeID,
            kind: "manual",
            at: now.addingTimeInterval(-30)
        )

        analytics = store.analytics(now: now)
        XCTAssertEqual(
            analytics.today.averageResponseDuration ?? -1,
            30,
            accuracy: 0.000_001
        )
    }

    func testTodayAndWeekMetricsUseDifferentScopes() {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date()).addingTimeInterval(12 * 60 * 60)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!

        store.recordSample(
            at: yesterday,
            fatigue: 180,
            presenceState: "activeInteraction",
            elapsed: 120,
            continuousUsageDuration: 2_400
        )
        store.recordRestAttempt(
            overloadEpisodeID: nil,
            startedAt: yesterday,
            endedAt: yesterday.addingTimeInterval(20),
            startFatigue: 180,
            endFatigue: 0,
            source: "system",
            outcome: "completed",
            interruptionReason: nil
        )

        store.recordSample(
            at: today,
            fatigue: 120,
            presenceState: "passiveStatic",
            elapsed: 60,
            continuousUsageDuration: 1_200
        )
        store.recordRestAttempt(
            overloadEpisodeID: nil,
            startedAt: today,
            endedAt: today.addingTimeInterval(10),
            startFatigue: 120,
            endFatigue: 60,
            source: "manual",
            outcome: "interrupted",
            interruptionReason: "keyboard"
        )

        let analytics = store.analytics(now: today)
        XCTAssertEqual(analytics.today.peakFatigue, 120, accuracy: 0.000_001)
        XCTAssertEqual(analytics.today.overloadDuration, 60, accuracy: 0.000_001)
        XCTAssertEqual(analytics.today.longestUsageDuration, 1_200, accuracy: 0.000_001)
        XCTAssertEqual(analytics.today.interruptedRestCount, 1)
        XCTAssertEqual(analytics.today.manualRestCount, 1)
        XCTAssertEqual(analytics.week.peakFatigue, 180, accuracy: 0.000_001)
        XCTAssertEqual(analytics.week.overloadDuration, 180, accuracy: 0.000_001)
        XCTAssertEqual(analytics.week.longestUsageDuration, 2_400, accuracy: 0.000_001)
        XCTAssertEqual(analytics.week.completedRestCount, 1)
        XCTAssertEqual(analytics.week.interruptedRestCount, 1)
        XCTAssertEqual(analytics.week.manualRestCount, 1)
        XCTAssertEqual(analytics.week.systemRestCount, 1)
    }

    func testRuntimeStateRestoresLatchedOverloadValues() {
        let episodeID = UUID()
        let savedAt = Date()
        store.saveRuntimeState(PersistedRuntimeState(
            fatigue: 185,
            restRequired: true,
            overloadStartedAt: savedAt.addingTimeInterval(-900),
            overloadEpisodeID: episodeID,
            continuousUsageDuration: 2_400,
            reminderPromptState: .manualRetry,
            reminderDecisionPending: true,
            lastInactivityRestCompletedAt: savedAt.addingTimeInterval(-60),
            lastReminderMultiple: 1,
            savedAt: savedAt
        ))

        let restored = store.loadRuntimeState()
        XCTAssertEqual(restored?.fatigue, 185)
        XCTAssertEqual(restored?.restRequired, true)
        XCTAssertEqual(restored?.overloadEpisodeID, episodeID)
        XCTAssertEqual(restored?.continuousUsageDuration, 2_400)
        XCTAssertEqual(restored?.reminderPromptState, .manualRetry)
        XCTAssertEqual(restored?.reminderDecisionPending, true)
        XCTAssertEqual(restored?.lastReminderMultiple, 1)
        XCTAssertEqual(
            restored?.lastInactivityRestCompletedAt,
            savedAt.addingTimeInterval(-60)
        )
    }

    func testInactivityRestHasIndependentEvidenceCategory() {
        let now = Date()
        for (offset, source) in [
            (0.0, RestTrigger.manual.rawValue),
            (30.0, RestTrigger.screenLocked.rawValue),
            (60.0, RestTrigger.inactivity.rawValue),
        ] {
            store.recordRestAttempt(
                overloadEpisodeID: nil,
                startedAt: now.addingTimeInterval(offset - 20),
                endedAt: now.addingTimeInterval(offset),
                startFatigue: 80,
                endFatigue: 0,
                source: source,
                outcome: "completed",
                interruptionReason: nil
            )
        }

        let metrics = store.analytics(now: now.addingTimeInterval(60)).today
        XCTAssertEqual(metrics.manualRestCount, 1)
        XCTAssertEqual(metrics.systemRestCount, 1)
        XCTAssertEqual(metrics.inactivityRestCount, 1)
    }

    func testLegacyRuntimeStateWithoutDecisionFieldStillDecodes() throws {
        struct LegacyRuntimeState: Encodable {
            var fatigue: Double
            var restRequired: Bool
            var overloadStartedAt: Date?
            var overloadEpisodeID: UUID?
            var continuousUsageDuration: TimeInterval
            var progressiveOverloadUsageDuration: TimeInterval?
            var savedAt: Date
        }

        let data = try JSONEncoder().encode(LegacyRuntimeState(
            fatigue: 120,
            restRequired: true,
            overloadStartedAt: Date(),
            overloadEpisodeID: UUID(),
            continuousUsageDuration: 1_200,
            progressiveOverloadUsageDuration: 30,
            savedAt: Date()
        ))
        let restored = try JSONDecoder().decode(PersistedRuntimeState.self, from: data)

        XCTAssertNil(restored.reminderDecisionPending)
        XCTAssertNil(restored.reminderPromptState)
        XCTAssertNil(restored.lastInactivityRestCompletedAt)
        XCTAssertNil(restored.lastReminderMultiple)
    }
}
