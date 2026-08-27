import SwiftData
import XCTest
@testable import EyeProtection

@MainActor
final class EventStoreTests: XCTestCase {
    private enum InjectedSaveError: Error {
        case failure
    }

    private final class ContextSaveGate {
        var shouldFail = false
    }

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
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today)!

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
        store.recordSample(
            at: tomorrow,
            fatigue: 999,
            presenceState: "activeInteraction",
            elapsed: 600,
            continuousUsageDuration: 9_999
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

    func testAnalyticsReturnsSevenCalendarDaysAndFillsMissingDaysWithoutPersistingThem() throws {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date()).addingTimeInterval(12 * 60 * 60)
        let threeDaysAgo = calendar.date(byAdding: .day, value: -3, to: today)!

        store.recordSample(
            at: threeDaysAgo,
            fatigue: 175,
            presenceState: "activeInteraction",
            elapsed: 90,
            continuousUsageDuration: 2_100
        )

        let context = ModelContext(store.container)
        let countBeforeQuery = try context.fetchCount(FetchDescriptor<DailySummaryRecord>())
        let analytics = store.analytics(now: today)
        let countAfterQuery = try context.fetchCount(FetchDescriptor<DailySummaryRecord>())

        XCTAssertEqual(analytics.dailyPoints.count, 7)
        XCTAssertEqual(countBeforeQuery, 1)
        XCTAssertEqual(countAfterQuery, countBeforeQuery)

        let expectedDates = (-6...0).map {
            calendar.startOfDay(for: calendar.date(byAdding: .day, value: $0, to: today)!)
        }
        XCTAssertEqual(analytics.dailyPoints.map(\.date), expectedDates)

        for point in analytics.dailyPoints {
            if calendar.isDate(point.date, inSameDayAs: threeDaysAgo) {
                XCTAssertEqual(point.peakFatigue, 175, accuracy: 0.000_001)
                XCTAssertEqual(point.overloadDuration, 90, accuracy: 0.000_001)
                XCTAssertEqual(point.longestUsageDuration, 2_100, accuracy: 0.000_001)
            } else {
                XCTAssertEqual(point.peakFatigue, 0, accuracy: 0.000_001)
                XCTAssertEqual(point.overloadDuration, 0, accuracy: 0.000_001)
                XCTAssertEqual(point.longestUsageDuration, 0, accuracy: 0.000_001)
            }
        }
    }

    func testAnalyticsSeparatesRecordsAcrossLocalMidnight() {
        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: Date())
        let beforeMidnight = startOfToday.addingTimeInterval(-2)
        let afterMidnight = startOfToday.addingTimeInterval(3)

        store.recordSample(
            at: beforeMidnight,
            fatigue: 110,
            presenceState: "activeInteraction",
            elapsed: 2,
            continuousUsageDuration: 2
        )
        store.recordSample(
            at: afterMidnight,
            fatigue: 111,
            presenceState: "activeInteraction",
            elapsed: 5,
            continuousUsageDuration: 7
        )

        let analytics = store.analytics(now: afterMidnight.addingTimeInterval(60))
        let yesterdayPoint = analytics.dailyPoints[analytics.dailyPoints.count - 2]
        let todayPoint = analytics.dailyPoints[analytics.dailyPoints.count - 1]

        XCTAssertTrue(calendar.isDate(yesterdayPoint.date, inSameDayAs: beforeMidnight))
        XCTAssertEqual(yesterdayPoint.peakFatigue, 110, accuracy: 0.000_001)
        XCTAssertEqual(yesterdayPoint.overloadDuration, 4, accuracy: 0.000_001)
        XCTAssertEqual(yesterdayPoint.longestUsageDuration, 4, accuracy: 0.000_001)

        XCTAssertTrue(calendar.isDate(todayPoint.date, inSameDayAs: afterMidnight))
        XCTAssertEqual(todayPoint.peakFatigue, 111, accuracy: 0.000_001)
        XCTAssertEqual(todayPoint.overloadDuration, 3, accuracy: 0.000_001)
        XCTAssertEqual(todayPoint.longestUsageDuration, 3, accuracy: 0.000_001)

        XCTAssertEqual(analytics.today.peakFatigue, 111, accuracy: 0.000_001)
        XCTAssertEqual(analytics.today.overloadDuration, 3, accuracy: 0.000_001)
        XCTAssertEqual(analytics.today.longestUsageDuration, 3, accuracy: 0.000_001)
        XCTAssertEqual(analytics.week.peakFatigue, 111, accuracy: 0.000_001)
        XCTAssertEqual(analytics.week.overloadDuration, 7, accuracy: 0.000_001)
        XCTAssertEqual(analytics.week.longestUsageDuration, 4, accuracy: 0.000_001)
    }

    func testAnalyticsWithNoStoredDaysReturnsSevenZeroDaysAndEmptyMetrics() throws {
        let calendar = Calendar.current
        let now = calendar.startOfDay(for: Date()).addingTimeInterval(15 * 60 * 60)

        let analytics = store.analytics(now: now)
        let context = ModelContext(store.container)

        XCTAssertEqual(analytics.dailyPoints.count, 7)
        XCTAssertTrue(analytics.dailyPoints.allSatisfy {
            $0.peakFatigue == 0 &&
            $0.overloadDuration == 0 &&
            $0.longestUsageDuration == 0
        })
        XCTAssertEqual(analytics.today.peakFatigue, 0, accuracy: 0.000_001)
        XCTAssertEqual(analytics.today.overloadDuration, 0, accuracy: 0.000_001)
        XCTAssertEqual(analytics.today.longestUsageDuration, 0, accuracy: 0.000_001)
        XCTAssertEqual(analytics.week.peakFatigue, 0, accuracy: 0.000_001)
        XCTAssertEqual(analytics.week.overloadDuration, 0, accuracy: 0.000_001)
        XCTAssertEqual(analytics.week.longestUsageDuration, 0, accuracy: 0.000_001)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<DailySummaryRecord>()), 0)
    }

    func testFatigueCurveKeepsPeakAndLatestValueWithinEachFiveMinuteBucket() {
        let calendar = Calendar.current
        let midday = calendar.startOfDay(for: Date()).addingTimeInterval(12 * 60 * 60)
        let bucketStart = Date(
            timeIntervalSince1970: floor(midday.timeIntervalSince1970 / 300) * 300
        )

        store.recordSample(
            at: bucketStart.addingTimeInterval(10),
            fatigue: 80,
            presenceState: "activeInteraction",
            elapsed: 5,
            continuousUsageDuration: 5
        )
        store.recordSample(
            at: bucketStart.addingTimeInterval(20),
            fatigue: 125,
            presenceState: "activeInteraction",
            elapsed: 5,
            continuousUsageDuration: 10
        )
        store.recordSample(
            at: bucketStart.addingTimeInterval(30),
            fatigue: 0,
            presenceState: "activeInteraction",
            elapsed: 5,
            continuousUsageDuration: 15
        )

        let analytics = store.analytics(now: bucketStart.addingTimeInterval(40))

        XCTAssertEqual(analytics.fatiguePoints.map(\.fatigue), [125, 0])
        XCTAssertEqual(
            analytics.fatiguePoints.map(\.timestamp),
            [bucketStart.addingTimeInterval(20), bucketStart.addingTimeInterval(30)]
        )

        let context = ModelContext(store.container)
        let storedSamples = (try? context.fetch(FetchDescriptor<FatigueSampleRecord>())) ?? []
        XCTAssertEqual(storedSamples.count, 2)
        XCTAssertEqual(storedSamples.map(\.fatigue).sorted(), [0, 125])
    }

    func testStagedSamplesStayOutOfSwiftDataUntilOneFlush() throws {
        let calendar = Calendar.current
        let midday = calendar.startOfDay(for: Date()).addingTimeInterval(12 * 60 * 60)
        let bucketStart = Date(
            timeIntervalSince1970: floor(midday.timeIntervalSince1970 / 300) * 300
        )
        let values = [80.0, 125, 0]

        for (index, fatigue) in values.enumerated() {
            store.stageSample(
                at: bucketStart.addingTimeInterval(Double((index + 1) * 10)),
                fatigue: fatigue,
                presenceState: PresenceState.activeInteraction.rawValue,
                elapsed: 5,
                continuousUsageDuration: Double((index + 1) * 5)
            )
        }

        var context = ModelContext(store.container)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<FatigueSampleRecord>()), 0)

        XCTAssertTrue(store.flushStagedSamples())

        context = ModelContext(store.container)
        let stored = try context.fetch(FetchDescriptor<FatigueSampleRecord>(
            sortBy: [SortDescriptor(\.timestamp)]
        ))
        XCTAssertEqual(stored.map(\.fatigue), [125, 0])
    }

    func testFlushingStagedUsageBeforeSessionEndPreservesFinalSegment() {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: Date()).addingTimeInterval(12 * 60 * 60)
        for offset in [0.0, 5.0] {
            store.stageSample(
                at: start.addingTimeInterval(offset),
                fatigue: 110,
                presenceState: PresenceState.activeInteraction.rawValue,
                elapsed: 5,
                continuousUsageDuration: offset + 5
            )
        }

        XCTAssertTrue(store.flushStagedSamples())
        store.recordUsageSessionEnded(at: start.addingTimeInterval(6))

        let metrics = store.analytics(now: start.addingTimeInterval(7)).today
        XCTAssertEqual(metrics.overloadDuration, 10, accuracy: 0.000_001)
        XCTAssertEqual(metrics.longestUsageDuration, 10, accuracy: 0.000_001)
    }

    func testSecondForcedFlushAtSameTimestampPersistsLatestValueWithoutDoubleCounting() throws {
        let calendar = Calendar.current
        let now = calendar.startOfDay(for: Date()).addingTimeInterval(12 * 60 * 60)
        store.stageSample(
            at: now,
            fatigue: 110,
            presenceState: PresenceState.activeInteraction.rawValue,
            elapsed: 5,
            continuousUsageDuration: 5
        )
        XCTAssertTrue(store.flushStagedSamples())

        store.stageSample(
            at: now,
            fatigue: 0,
            presenceState: PresenceState.activeInteraction.rawValue,
            elapsed: 5,
            continuousUsageDuration: 0
        )
        XCTAssertTrue(store.flushStagedSamples())

        let metrics = store.analytics(now: now.addingTimeInterval(1)).today
        XCTAssertEqual(metrics.overloadDuration, 5, accuracy: 0.000_001)
        XCTAssertEqual(metrics.longestUsageDuration, 5, accuracy: 0.000_001)
        let context = ModelContext(store.container)
        let storedFatigue = try context.fetch(FetchDescriptor<FatigueSampleRecord>())
            .map(\.fatigue)
            .sorted()
        XCTAssertEqual(storedFatigue, [0, 110])
    }

    func testFailedSessionTailFlushDoesNotResetUsageTrackerBeforeRetry() throws {
        let gate = ContextSaveGate()
        let failingStore = try EventStore(
            inMemory: true,
            defaults: defaults,
            contextSaveHook: {
                if gate.shouldFail { throw InjectedSaveError.failure }
            }
        )
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: Date()).addingTimeInterval(12 * 60 * 60)
        failingStore.recordSample(
            at: start,
            fatigue: 110,
            presenceState: PresenceState.activeInteraction.rawValue,
            elapsed: 5,
            continuousUsageDuration: 5
        )
        failingStore.stageSample(
            at: start.addingTimeInterval(5),
            fatigue: 110,
            presenceState: PresenceState.activeInteraction.rawValue,
            elapsed: 5,
            continuousUsageDuration: 10
        )

        gate.shouldFail = true
        let tailFlushSucceeded = failingStore.flushStagedSamples()
        XCTAssertFalse(tailFlushSucceeded)
        if AnalyticsSamplingPolicy.shouldCommitUsageSessionEnd(
            tailFlushSucceeded: tailFlushSucceeded
        ) {
            failingStore.recordUsageSessionEnded(at: start.addingTimeInterval(6))
        }

        gate.shouldFail = false
        failingStore.stageSample(
            at: start.addingTimeInterval(6),
            fatigue: 110,
            presenceState: PresenceState.awayConfirmed.rawValue,
            elapsed: 1,
            continuousUsageDuration: 0
        )
        XCTAssertTrue(failingStore.flushStagedSamples())

        let metrics = failingStore.analytics(now: start.addingTimeInterval(7)).today
        XCTAssertEqual(metrics.overloadDuration, 10, accuracy: 0.000_001)
        XCTAssertEqual(metrics.longestUsageDuration, 10, accuracy: 0.000_001)
    }

    func testClockRollbackAndSaveFailureRetainBothBufferedEpochs() throws {
        let gate = ContextSaveGate()
        let failingStore = try EventStore(
            inMemory: true,
            defaults: defaults,
            contextSaveHook: {
                if gate.shouldFail { throw InjectedSaveError.failure }
            }
        )
        let calendar = Calendar.current
        let base = calendar.startOfDay(for: Date()).addingTimeInterval(12 * 60 * 60)
        for (offset, continuousUsage) in [(120.0, 5.0), (125.0, 10.0), (60.0, 15.0)] {
            failingStore.stageSample(
                at: base.addingTimeInterval(offset),
                fatigue: 110,
                presenceState: PresenceState.activeInteraction.rawValue,
                elapsed: 5,
                continuousUsageDuration: continuousUsage
            )
        }

        gate.shouldFail = true
        XCTAssertFalse(failingStore.flushStagedSamples())

        gate.shouldFail = false
        failingStore.stageSample(
            at: base.addingTimeInterval(65),
            fatigue: 110,
            presenceState: PresenceState.activeInteraction.rawValue,
            elapsed: 5,
            continuousUsageDuration: 20
        )
        XCTAssertTrue(failingStore.flushStagedSamples())

        let metrics = failingStore.analytics(now: base.addingTimeInterval(180)).today
        XCTAssertEqual(metrics.overloadDuration, 20, accuracy: 0.000_001)
        XCTAssertEqual(metrics.longestUsageDuration, 20, accuracy: 0.000_001)
    }

    func testClockRollbackWithinBucketRetainsArrivalLatestThroughMaintenance() throws {
        let calendar = Calendar.current
        let bucketStart = calendar.startOfDay(for: Date()).addingTimeInterval(12 * 60 * 60)
        for (offset, fatigue, continuousUsage) in [
            (240.0, 80.0, 5.0),
            (60.0, 50.0, 10.0),
            (120.0, 60.0, 15.0),
        ] {
            store.stageSample(
                at: bucketStart.addingTimeInterval(offset),
                fatigue: fatigue,
                presenceState: PresenceState.activeInteraction.rawValue,
                elapsed: 5,
                continuousUsageDuration: continuousUsage
            )
        }
        XCTAssertTrue(store.flushStagedSamples())

        let afterRollback = store.analytics(
            now: bucketStart.addingTimeInterval(121)
        ).fatiguePoints
        XCTAssertEqual(afterRollback.map(\.fatigue), [60])

        let insertionContext = ModelContext(store.container)
        insertionContext.insert(FatigueSampleRecord(
            timestamp: bucketStart.addingTimeInterval(180),
            fatigue: 70,
            presenceState: PresenceState.activeInteraction.rawValue
        ))
        try insertionContext.save()

        let maintenanceNow = bucketStart.addingTimeInterval(6 * 60 * 60 + 6 * 60)
        while store.cleanExpiredData(now: maintenanceNow) {}

        let verificationContext = ModelContext(store.container)
        let bucketEnd = bucketStart.addingTimeInterval(5 * 60)
        let retained = try verificationContext.fetch(FetchDescriptor<FatigueSampleRecord>(
            predicate: #Predicate {
                $0.timestamp >= bucketStart &&
                    $0.timestamp < bucketEnd
            },
            sortBy: [SortDescriptor(\.timestamp)]
        ))
        XCTAssertEqual(retained.map(\.fatigue), [60, 80])
        XCTAssertEqual(retained.filter { $0.isBucketLatest == true }.map(\.fatigue), [60])

        let afterMaintenance = store.analytics(now: maintenanceNow).fatiguePoints
        XCTAssertEqual(afterMaintenance.map(\.fatigue).sorted(), [60, 80])
    }

    func testMaintenanceCompactsMoreThanTwoEnumerationBatches() throws {
        let calendar = Calendar.current
        let now = calendar.startOfDay(for: Date()).addingTimeInterval(12 * 60 * 60)
        let bucketStart = Date(
            timeIntervalSince1970: floor(
                now.addingTimeInterval(-60 * 60).timeIntervalSince1970 / 300
            ) * 300
        )
        let recordCount = EventStore.maintenanceSampleBatchSize * 2 + 3
        let context = ModelContext(store.container)
        for index in 0..<recordCount {
            context.insert(FatigueSampleRecord(
                timestamp: bucketStart.addingTimeInterval(Double(index) / 10),
                fatigue: index == 500 ? 999 : Double(index % 100),
                presenceState: PresenceState.activeInteraction.rawValue
            ))
        }
        try context.save()

        store.cleanExpiredData(now: now)
        XCTAssertTrue(store.maintenanceInProgress)
        XCTAssertEqual(
            store.maintenanceLastScanCount,
            EventStore.maintenanceSampleBatchSize
        )
        var maintenanceStepCount = 1
        while store.maintenanceInProgress, maintenanceStepCount < 10 {
            store.cleanExpiredData(now: now)
            XCTAssertLessThanOrEqual(
                store.maintenanceLastScanCount,
                EventStore.maintenanceSampleBatchSize
            )
            maintenanceStepCount += 1
        }
        XCTAssertFalse(store.maintenanceInProgress)
        XCTAssertGreaterThan(maintenanceStepCount, 2)

        let verificationContext = ModelContext(store.container)
        let bucketEnd = bucketStart.addingTimeInterval(300)
        let retained = try verificationContext.fetch(FetchDescriptor<FatigueSampleRecord>(
            predicate: #Predicate {
                $0.timestamp >= bucketStart && $0.timestamp < bucketEnd
            }
        ))
        XCTAssertEqual(retained.count, 2)
        XCTAssertTrue(retained.contains { $0.fatigue == 999 })
        XCTAssertTrue(retained.contains {
            $0.timestamp == bucketStart.addingTimeInterval(Double(recordCount - 1) / 10)
        })
    }

    func testChunkedMaintenanceDoesNotSkipHistoricalBucketsDuringLiveSampling() throws {
        let calendar = Calendar.current
        let now = calendar.startOfDay(for: Date()).addingTimeInterval(12 * 60 * 60)
        let firstBucket = Date(
            timeIntervalSince1970: floor(
                now.addingTimeInterval(-2 * 60 * 60).timeIntervalSince1970 / 300
            ) * 300
        )
        let context = ModelContext(store.container)
        for bucketIndex in 0..<4 {
            let bucketStart = firstBucket.addingTimeInterval(Double(bucketIndex * 300))
            for index in 0..<300 {
                context.insert(FatigueSampleRecord(
                    timestamp: bucketStart.addingTimeInterval(Double(index) / 2),
                    fatigue: index == 150 ? 999 : Double(index),
                    presenceState: PresenceState.activeInteraction.rawValue
                ))
            }
        }
        try context.save()

        XCTAssertTrue(store.cleanExpiredData(now: now))
        store.recordSample(
            at: now.addingTimeInterval(5),
            fatigue: 42,
            presenceState: PresenceState.activeInteraction.rawValue,
            elapsed: 5,
            continuousUsageDuration: 5
        )
        var maintenanceStepCount = 2
        while store.maintenanceInProgress, maintenanceStepCount < 20 {
            store.cleanExpiredData(now: now.addingTimeInterval(5))
            maintenanceStepCount += 1
        }
        XCTAssertFalse(store.maintenanceInProgress)

        let verificationContext = ModelContext(store.container)
        for bucketIndex in 0..<4 {
            let bucketStart = firstBucket.addingTimeInterval(Double(bucketIndex * 300))
            let bucketEnd = bucketStart.addingTimeInterval(300)
            let retained = try verificationContext.fetch(FetchDescriptor<FatigueSampleRecord>(
                predicate: #Predicate {
                    $0.timestamp >= bucketStart && $0.timestamp < bucketEnd
                }
            ))
            XCTAssertEqual(retained.count, 2)
            XCTAssertTrue(retained.contains { $0.fatigue == 999 })
            XCTAssertTrue(retained.contains {
                $0.timestamp == bucketStart.addingTimeInterval(299.0 / 2)
            })
        }
        XCTAssertTrue(try verificationContext.fetch(FetchDescriptor<FatigueSampleRecord>())
            .contains { $0.timestamp == now.addingTimeInterval(5) })
    }

    func testTimerStallUsesVerifiedUsageDeltaInsteadOfWallClockElapsed() {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: Date()).addingTimeInterval(12 * 60 * 60)

        store.recordSample(
            at: start,
            fatigue: 110,
            presenceState: "activeInteraction",
            elapsed: 5,
            continuousUsageDuration: 100
        )
        store.recordSample(
            at: start.addingTimeInterval(60),
            fatigue: 111,
            presenceState: "activeInteraction",
            elapsed: 60,
            continuousUsageDuration: 102
        )

        let metrics = store.analytics(now: start.addingTimeInterval(61)).today
        XCTAssertEqual(metrics.overloadDuration, 7, accuracy: 0.000_001)
    }

    func testThresholdCrossingCountsOnlyTheOverloadedPartOfVerifiedUsage() {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: Date()).addingTimeInterval(12 * 60 * 60)

        store.recordSample(
            at: start,
            fatigue: 99,
            presenceState: "activeInteraction",
            elapsed: 5,
            continuousUsageDuration: 5
        )
        store.recordSample(
            at: start.addingTimeInterval(10),
            fatigue: 101,
            presenceState: "activeInteraction",
            elapsed: 10,
            continuousUsageDuration: 15
        )

        XCTAssertEqual(
            store.analytics(now: start.addingTimeInterval(11)).today.overloadDuration,
            5,
            accuracy: 0.000_001
        )
    }

    func testSessionEndStartsANewContinuousUsageSegment() {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: Date()).addingTimeInterval(12 * 60 * 60)

        store.recordSample(
            at: start,
            fatigue: 40,
            presenceState: "activeInteraction",
            elapsed: 5,
            continuousUsageDuration: 5
        )
        store.recordSample(
            at: start.addingTimeInterval(5),
            fatigue: 41,
            presenceState: "passiveStatic",
            elapsed: 5,
            continuousUsageDuration: 10
        )

        store.recordUsageSessionEnded(at: start.addingTimeInterval(6))

        store.recordSample(
            at: start.addingTimeInterval(10),
            fatigue: 42,
            presenceState: "activeInteraction",
            elapsed: 5,
            continuousUsageDuration: 15
        )
        store.recordSample(
            at: start.addingTimeInterval(15),
            fatigue: 43,
            presenceState: "passiveStatic",
            elapsed: 5,
            continuousUsageDuration: 20
        )

        XCTAssertEqual(
            store.analytics(now: start.addingTimeInterval(16)).today.longestUsageDuration,
            10,
            accuracy: 0.000_001
        )
    }

    func testNonContributingPresenceAlsoEndsContinuousUsageSegment() {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: Date()).addingTimeInterval(12 * 60 * 60)

        for (offset, state, continuousUsage) in [
            (0.0, "activeInteraction", 5.0),
            (5.0, "passiveStatic", 10.0),
            (10.0, "awayConfirmed", 10.0),
            (15.0, "activeInteraction", 15.0),
            (20.0, "passiveStatic", 20.0),
        ] {
            store.recordSample(
                at: start.addingTimeInterval(offset),
                fatigue: 40,
                presenceState: state,
                elapsed: 5,
                continuousUsageDuration: continuousUsage
            )
        }

        XCTAssertEqual(
            store.analytics(now: start.addingTimeInterval(21)).today.longestUsageDuration,
            10,
            accuracy: 0.000_001
        )
    }

    func testRecordSampleRunsRetentionAndCompactionDuringLongLivedSession() throws {
        let calendar = Calendar.current
        let now = calendar.startOfDay(for: Date()).addingTimeInterval(12 * 60 * 60)
        let oldBucketStart = Date(
            timeIntervalSince1970: floor(
                now.addingTimeInterval(-60 * 60).timeIntervalSince1970 / 300
            ) * 300
        )
        let context = ModelContext(store.container)
        context.insert(FatigueSampleRecord(
            timestamp: now.addingTimeInterval(-8 * 24 * 60 * 60),
            fatigue: 999,
            presenceState: "activeInteraction"
        ))
        for (offset, fatigue) in [(10.0, 80.0), (20.0, 130.0), (30.0, 90.0)] {
            context.insert(FatigueSampleRecord(
                timestamp: oldBucketStart.addingTimeInterval(offset),
                fatigue: fatigue,
                presenceState: "activeInteraction"
            ))
        }
        try context.save()

        store.recordSample(
            at: now,
            fatigue: 50,
            presenceState: "activeInteraction",
            elapsed: 5,
            continuousUsageDuration: 5
        )

        let retained = try context.fetch(FetchDescriptor<FatigueSampleRecord>(
            sortBy: [SortDescriptor(\.timestamp)]
        ))
        XCTAssertFalse(retained.contains { $0.fatigue == 999 })
        XCTAssertEqual(
            retained.filter {
                $0.timestamp >= oldBucketStart &&
                $0.timestamp < oldBucketStart.addingTimeInterval(300)
            }.map(\.fatigue).sorted(),
            [90, 130]
        )
        XCTAssertEqual(store.maintenanceRunCount, 1)
    }

    func testMaintenanceFullScanIsThrottledToSixHourIntervals() {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: Date()).addingTimeInterval(6 * 60 * 60)
        store.cleanExpiredData(now: start)
        XCTAssertEqual(store.maintenanceRunCount, 1)

        for offset in [5.0, 60.0, 60 * 60.0, 6 * 60 * 60.0 - 1] {
            store.recordSample(
                at: start.addingTimeInterval(offset),
                fatigue: 50,
                presenceState: "activeInteraction",
                elapsed: 5,
                continuousUsageDuration: offset
            )
        }
        XCTAssertEqual(store.maintenanceRunCount, 1)

        store.recordSample(
            at: start.addingTimeInterval(6 * 60 * 60),
            fatigue: 50,
            presenceState: "activeInteraction",
            elapsed: 1,
            continuousUsageDuration: 6 * 60 * 60
        )
        XCTAssertEqual(store.maintenanceRunCount, 2)
    }

    func testClockRollbackRebasesUsageAndMaintenanceInsteadOfFreezingAnalytics() {
        let calendar = Calendar.current
        let base = calendar.startOfDay(for: Date()).addingTimeInterval(12 * 60 * 60)

        store.recordSample(
            at: base.addingTimeInterval(120),
            fatigue: 110,
            presenceState: "activeInteraction",
            elapsed: 10,
            continuousUsageDuration: 10
        )
        store.recordSample(
            at: base.addingTimeInterval(60),
            fatigue: 120,
            presenceState: "activeInteraction",
            elapsed: 10,
            continuousUsageDuration: 20
        )
        store.recordSample(
            at: base.addingTimeInterval(70),
            fatigue: 130,
            presenceState: "activeInteraction",
            elapsed: 10,
            continuousUsageDuration: 30
        )

        let analytics = store.analytics(now: base.addingTimeInterval(180))
        XCTAssertEqual(analytics.today.overloadDuration, 30, accuracy: 0.000_001)
        XCTAssertEqual(store.maintenanceRunCount, 2)
    }

    func testFatigueCurveIncludesOnlyTodaySamplesThroughRequestedTime() {
        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: Date())
        let now = startOfToday.addingTimeInterval(12 * 60 * 60)

        store.recordSample(
            at: startOfToday.addingTimeInterval(-1),
            fatigue: 888,
            presenceState: "activeInteraction",
            elapsed: 5,
            continuousUsageDuration: 5
        )

        store.recordSample(
            at: now.addingTimeInterval(-10),
            fatigue: 63,
            presenceState: "activeInteraction",
            elapsed: 5,
            continuousUsageDuration: 5
        )
        store.recordSample(
            at: now.addingTimeInterval(10),
            fatigue: 999,
            presenceState: "activeInteraction",
            elapsed: 5,
            continuousUsageDuration: 10
        )

        let analytics = store.analytics(now: now)

        XCTAssertEqual(analytics.fatiguePoints.map(\.fatigue), [63])
        XCTAssertEqual(analytics.fatiguePoints.map(\.timestamp), [now.addingTimeInterval(-10)])
        XCTAssertTrue(analytics.fatiguePoints.allSatisfy {
            $0.timestamp >= startOfToday && $0.timestamp <= now
        })
    }

    func testRuntimeStateRestoresLatchedOverloadValues() {
        let episodeID = UUID()
        let savedAt = Date()
        let activeRest = ActiveRestSession(
            trigger: .manual,
            startedAt: savedAt.addingTimeInterval(-8),
            startFatiguePercent: 185,
            elapsed: 8
        )
        let pendingAttempt = PendingRestAttempt(
            attempt: RestAttempt(
                id: UUID(),
                trigger: .screenLocked,
                startedAt: savedAt.addingTimeInterval(-30),
                endedAt: savedAt.addingTimeInterval(-20),
                startFatiguePercent: 180,
                duration: 10,
                endFatiguePercent: 90,
                outcome: .interrupted(.cancelled)
            ),
            overloadEpisodeID: episodeID
        )
        store.saveRuntimeState(PersistedRuntimeState(
            fatigue: 185,
            restRequired: true,
            overloadStartedAt: savedAt.addingTimeInterval(-900),
            overloadEpisodeID: episodeID,
            continuousUsageDuration: 2_400,
            activeRest: activeRest,
            pendingRestAttempts: [pendingAttempt],
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
        XCTAssertEqual(restored?.activeRest, activeRest)
        XCTAssertEqual(restored?.pendingRestAttempts, [pendingAttempt])
        XCTAssertEqual(restored?.reminderPromptState, .manualRetry)
        XCTAssertEqual(restored?.reminderDecisionPending, true)
        XCTAssertEqual(restored?.lastReminderMultiple, 1)
        XCTAssertEqual(
            restored?.lastInactivityRestCompletedAt,
            savedAt.addingTimeInterval(-60)
        )
    }

    func testRuntimeStateSaveReportsEncodingFailure() {
        let state = PersistedRuntimeState(
            fatigue: .infinity,
            restRequired: false,
            overloadStartedAt: nil,
            overloadEpisodeID: nil,
            continuousUsageDuration: 0,
            savedAt: Date()
        )

        XCTAssertFalse(store.saveRuntimeState(state))
        XCTAssertNil(store.loadRuntimeState())
    }

    func testClearAllSaveFailureRollsBackAndPreservesRuntimeAndBufferedSamples() throws {
        let gate = ContextSaveGate()
        let failingStore = try EventStore(
            inMemory: true,
            defaults: defaults,
            contextSaveHook: {
                if gate.shouldFail { throw InjectedSaveError.failure }
            }
        )
        let now = Calendar.current.startOfDay(for: Date()).addingTimeInterval(12 * 60 * 60)
        failingStore.recordSample(
            at: now,
            fatigue: 50,
            presenceState: PresenceState.activeInteraction.rawValue,
            elapsed: 5,
            continuousUsageDuration: 5
        )
        XCTAssertTrue(failingStore.saveRuntimeState(PersistedRuntimeState(
            fatigue: 50,
            restRequired: false,
            overloadStartedAt: nil,
            overloadEpisodeID: nil,
            continuousUsageDuration: 5,
            savedAt: now
        )))
        failingStore.stageSample(
            at: now.addingTimeInterval(5),
            fatigue: 80,
            presenceState: PresenceState.activeInteraction.rawValue,
            elapsed: 5,
            continuousUsageDuration: 10
        )

        gate.shouldFail = true
        XCTAssertFalse(failingStore.clearAll())
        XCTAssertEqual(failingStore.loadRuntimeState()?.fatigue, 50)
        var verificationContext = ModelContext(failingStore.container)
        XCTAssertEqual(
            try verificationContext.fetchCount(FetchDescriptor<FatigueSampleRecord>()),
            1
        )

        gate.shouldFail = false
        XCTAssertTrue(failingStore.flushStagedSamples())
        verificationContext = ModelContext(failingStore.container)
        XCTAssertEqual(
            try verificationContext.fetch(FetchDescriptor<FatigueSampleRecord>())
                .map(\.fatigue)
                .max(),
            80
        )

        XCTAssertTrue(failingStore.clearAll())
        XCTAssertNil(failingStore.loadRuntimeState())
        verificationContext = ModelContext(failingStore.container)
        XCTAssertEqual(
            try verificationContext.fetchCount(FetchDescriptor<FatigueSampleRecord>()),
            0
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

    func testStableRestAttemptIDPreventsRecoveryDoubleCounting() {
        let now = Date()
        let attemptID = UUID()

        for _ in 0..<2 {
            XCTAssertTrue(store.recordRestAttempt(
                id: attemptID,
                overloadEpisodeID: nil,
                startedAt: now,
                endedAt: now.addingTimeInterval(8),
                startFatigue: 180,
                endFatigue: 120,
                source: RestTrigger.manual.rawValue,
                outcome: "interrupted",
                interruptionReason: RestInterruptionReason.cancelled.rawValue
            ))
        }

        let analytics = store.analytics(now: now.addingTimeInterval(10))
        XCTAssertEqual(analytics.today.interruptedRestCount, 1)
        XCTAssertEqual(analytics.today.manualRestCount, 1)
    }

    func testTodaySummaryUsesLocalDayKeyAfterTimeZoneMidnightShifts() throws {
        let calendar = Calendar.current
        let now = calendar.startOfDay(for: Date()).addingTimeInterval(12 * 60 * 60)
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"

        let shiftedMidnight = now.addingTimeInterval(2 * 24 * 60 * 60)
        let record = DailySummaryRecord(
            dayKey: formatter.string(from: now),
            date: shiftedMidnight
        )
        record.peakFatigue = 123
        let context = ModelContext(store.container)
        context.insert(record)
        try context.save()

        XCTAssertEqual(store.analytics(now: now).today.peakFatigue, 123)
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
        XCTAssertNil(restored.activeRest)
        XCTAssertNil(restored.pendingRestAttempts)
        XCTAssertNil(restored.lastInactivityRestCompletedAt)
        XCTAssertNil(restored.lastReminderMultiple)
    }
}
