import Foundation
import OSLog
import SwiftData

@MainActor
final class EventStore {
    private static let logger = Logger(subsystem: "com.local.EyeProtection", category: "EventStore")
    private static let runtimeStateKey = "runtimeState.v1"
    private static let usageTrackerKey = "analyticsUsageTracker.v1"
    private static let sampleBucketInterval: TimeInterval = 5 * 60
    private static let sampleRetentionInterval: TimeInterval = 7 * 24 * 60 * 60
    private static let detailRetentionInterval: TimeInterval = 30 * 24 * 60 * 60
    private static let summaryRetentionInterval: TimeInterval = 365 * 24 * 60 * 60
    private static let maintenanceInterval: TimeInterval = 6 * 60 * 60
    static let maintenanceSampleBatchSize = 512
    static let maintenanceBucketDeleteLimit = 32

    private struct BufferedSample {
        var sequence: UInt64
        var date: Date
        var fatigue: Double
        var presenceState: String
        var elapsed: TimeInterval
        var continuousUsageDuration: TimeInterval
    }

    private struct SampleBucketRetention {
        var count: Int
        var peakID: UUID
        var peakFatigue: Double
        var peakTimestamp: Date
        var latestID: UUID
        var latestTimestamp: Date
        var hasArrivalLatest: Bool

        init(_ record: FatigueSampleRecord) {
            count = 1
            peakID = record.id
            peakFatigue = record.fatigue
            peakTimestamp = record.timestamp
            latestID = record.id
            latestTimestamp = record.timestamp
            hasArrivalLatest = record.isBucketLatest == true
        }

        mutating func observe(_ record: FatigueSampleRecord) {
            count += 1
            if record.fatigue > peakFatigue ||
                (record.fatigue == peakFatigue && record.timestamp >= peakTimestamp) {
                peakID = record.id
                peakFatigue = record.fatigue
                peakTimestamp = record.timestamp
            }
            if record.isBucketLatest == true {
                if !hasArrivalLatest || record.timestamp >= latestTimestamp {
                    latestID = record.id
                    latestTimestamp = record.timestamp
                }
                hasArrivalLatest = true
            } else if !hasArrivalLatest, record.timestamp >= latestTimestamp {
                latestID = record.id
                latestTimestamp = record.timestamp
            }
        }
    }

    private struct SampleBucketDeletion {
        var bucketStart: Date
        var peakID: UUID
        var latestID: UUID
    }

    private struct SampleMaintenanceState {
        var cutoff: Date
        var upperBound: Date
        var scanOffset = 0
        var buckets: [Date: SampleBucketRetention] = [:]
        var deletions: [SampleBucketDeletion] = []
        var deletionIndex = 0
        var isScanning = true
    }

    private struct UsageTracker: Codable {
        var lastSampleAt: Date?
        var lastFatigue: Double?
        var lastContinuousUsageDuration: TimeInterval?
        var lastPresenceContributed: Bool
        var activeSegmentDay: Date?
        var activeSegmentDuration: TimeInterval

        static let empty = UsageTracker(
            lastSampleAt: nil,
            lastFatigue: nil,
            lastContinuousUsageDuration: nil,
            lastPresenceContributed: false,
            activeSegmentDay: nil,
            activeSegmentDuration: 0
        )
    }

    let container: ModelContainer
    private let context: ModelContext
    private let defaults: UserDefaults
    private let contextSaveHook: (() throws -> Void)?
    private var usageTracker: UsageTracker
    private var nextMaintenanceAt = Date.distantPast
    private(set) var maintenanceRunCount = 0
    private(set) var maintenanceLastScanCount = 0
    private var sampleMaintenanceState: SampleMaintenanceState?
    private var bufferedSamples: [BufferedSample] = []
    private var nextSampleSequence: UInt64 = 0

    var maintenanceInProgress: Bool {
        sampleMaintenanceState != nil
    }

    init(
        inMemory: Bool = false,
        defaults: UserDefaults = .standard,
        contextSaveHook: (() throws -> Void)? = nil
    ) throws {
        let schema = Schema([
            FatigueSampleRecord.self,
            OverloadEpisodeRecord.self,
            RestAttemptRecord.self,
            DailySummaryRecord.self,
        ])
        let configuration = ModelConfiguration(
            "EyeProtection",
            schema: schema,
            isStoredInMemoryOnly: inMemory
        )
        self.container = try ModelContainer(for: schema, configurations: [configuration])
        let context = ModelContext(container)
        context.autosaveEnabled = false
        self.context = context
        self.defaults = defaults
        self.contextSaveHook = contextSaveHook
        self.usageTracker = defaults.data(forKey: Self.usageTrackerKey)
            .flatMap { try? JSONDecoder().decode(UsageTracker.self, from: $0) }
            ?? .empty
    }

    static func makeDefault() -> EventStore {
        do {
            return try EventStore()
        } catch {
            logger.error("Persistent store failed; using in-memory fallback: \(error.localizedDescription, privacy: .public)")
            do {
                return try EventStore(inMemory: true)
            } catch {
                fatalError("Unable to create an in-memory data store: \(error)")
            }
        }
    }

    @discardableResult
    func saveRuntimeState(_ state: PersistedRuntimeState) -> Bool {
        do {
            defaults.set(try JSONEncoder().encode(state), forKey: Self.runtimeStateKey)
            return true
        } catch {
            Self.logger.error("Unable to encode runtime state: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    func loadRuntimeState() -> PersistedRuntimeState? {
        guard let data = defaults.data(forKey: Self.runtimeStateKey) else { return nil }
        do {
            return try JSONDecoder().decode(PersistedRuntimeState.self, from: data)
        } catch {
            Self.logger.error("Unable to decode runtime state: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    func recordSample(
        at date: Date,
        fatigue: Double,
        presenceState: String,
        elapsed: TimeInterval,
        continuousUsageDuration: TimeInterval
    ) {
        stageSample(
            at: date,
            fatigue: fatigue,
            presenceState: presenceState,
            elapsed: elapsed,
            continuousUsageDuration: continuousUsageDuration
        )
        flushStagedSamples()
    }

    func stageSample(
        at date: Date,
        fatigue: Double,
        presenceState: String,
        elapsed: TimeInterval,
        continuousUsageDuration: TimeInterval
    ) {
        bufferedSamples.append(BufferedSample(
            sequence: nextSampleSequence,
            date: date,
            fatigue: fatigue.isFinite ? max(0, fatigue) : 0,
            presenceState: presenceState,
            elapsed: elapsed.isFinite ? max(0, elapsed) : 0,
            continuousUsageDuration: continuousUsageDuration.isFinite
                ? max(0, continuousUsageDuration)
                : 0
        ))
        nextSampleSequence &+= 1
    }

    @discardableResult
    func flushStagedSamples() -> Bool {
        guard !bufferedSamples.isEmpty else { return true }
        // Arrival order is authoritative across wall-clock corrections. Sorting by
        // the corrected timestamp would move pre-correction observations after the
        // new epoch and can either lose or double-count the session boundary.
        let samples = bufferedSamples
        let trackerBeforeFlush = usageTracker
        let nextMaintenanceBeforeFlush = nextMaintenanceAt
        let maintenanceRunCountBeforeFlush = maintenanceRunCount
        let maintenanceLastScanCountBeforeFlush = maintenanceLastScanCount
        let sampleMaintenanceStateBeforeFlush = sampleMaintenanceState

        var previousDate = usageTracker.lastSampleAt
        let containsClockRollback = samples.contains { sample in
            defer { previousDate = sample.date }
            return previousDate.map { sample.date < $0 } ?? false
        }
        if containsClockRollback {
            nextMaintenanceAt = .distantPast
            sampleMaintenanceState = nil
        }
        performMaintenanceIfNeeded(now: samples[samples.count - 1].date)

        for sample in samples {
            if usageTracker.lastSampleAt.map({ sample.date < $0 }) == true {
                // Rebase at the arrival-order epoch boundary. Previously applied
                // observations remain durable in their summaries, while the new
                // epoch seeds its segment from the reported cumulative counter.
                usageTracker = .empty
            }
            applySample(sample)
        }
        for sample in curveSamples(from: samples) {
            upsertSample(
                at: sample.date,
                fatigue: sample.fatigue,
                presenceState: sample.presenceState
            )
        }
        saveUsageTracker()
        guard saveContext() else {
            context.rollback()
            usageTracker = trackerBeforeFlush
            nextMaintenanceAt = nextMaintenanceBeforeFlush
            maintenanceRunCount = maintenanceRunCountBeforeFlush
            maintenanceLastScanCount = maintenanceLastScanCountBeforeFlush
            sampleMaintenanceState = sampleMaintenanceStateBeforeFlush
            saveUsageTracker()
            return false
        }
        bufferedSamples.removeFirst(samples.count)
        return true
    }

    private func applySample(_ sample: BufferedSample) {
        let date = sample.date

        let normalizedFatigue = sample.fatigue.isFinite ? max(0, sample.fatigue) : 0
        let normalizedContinuousUsage = sample.continuousUsageDuration.isFinite
            ? max(0, sample.continuousUsageDuration)
            : 0
        let contributesToFatigue = PresenceState(
            rawValue: sample.presenceState
        )?.contributesToFatigue == true
        let isMonotonicSample = usageTracker.lastSampleAt.map { date >= $0 } ?? true
        let verifiedUsageDuration = isMonotonicSample
            ? verifiedUsageDuration(
                at: date,
                elapsed: sample.elapsed,
                continuousUsageDuration: normalizedContinuousUsage,
                contributesToFatigue: contributesToFatigue
            )
            : 0

        let summary = summaryRecord(for: date)
        summary.peakFatigue = max(summary.peakFatigue, normalizedFatigue)

        guard isMonotonicSample else {
            return
        }

        if contributesToFatigue {
            let cumulativeCounterReset = usageTracker.lastContinuousUsageDuration.map {
                normalizedContinuousUsage < $0
            } ?? false
            recordContinuousUsage(
                duration: verifiedUsageDuration,
                endingAt: date,
                reportedContinuousUsageDuration: normalizedContinuousUsage,
                seedFromReportedCounter: usageTracker.lastSampleAt == nil || cumulativeCounterReset
            )
            recordOverloadUsage(
                duration: verifiedUsageDuration,
                endingAt: date,
                previousFatigue: usageTracker.lastFatigue,
                currentFatigue: normalizedFatigue
            )
        } else {
            resetUsageSegment()
        }

        usageTracker.lastSampleAt = max(usageTracker.lastSampleAt ?? date, date)
        usageTracker.lastFatigue = normalizedFatigue
        usageTracker.lastContinuousUsageDuration = normalizedContinuousUsage
        usageTracker.lastPresenceContributed = contributesToFatigue
    }

    /// Ends the analytics usage segment immediately when the presence engine emits
    /// `sessionEnded`, even if the next five-second persistence sample has not run yet.
    func recordUsageSessionEnded(at date: Date) {
        guard usageTracker.lastSampleAt.map({ date >= $0 }) ?? true else { return }
        resetUsageSegment()
        usageTracker.lastPresenceContributed = false
        saveUsageTracker()
    }

    func beginOverload(at date: Date, fatigue: Double, id: UUID = UUID()) -> UUID {
        context.insert(OverloadEpisodeRecord(id: id, startedAt: date, peakFatigue: fatigue))
        saveContext()
        return id
    }

    func updateOverload(id: UUID, peakFatigue: Double, save: Bool = true) {
        guard let episode = overloadEpisode(id: id) else { return }
        episode.peakFatigue = max(episode.peakFatigue, peakFatigue)
        if save {
            saveContext()
        }
    }

    func markOverloadResponse(id: UUID, kind: String, at date: Date) {
        guard let episode = overloadEpisode(id: id) else { return }
        if kind == "continued" {
            summaryRecord(for: date).continuedWorkingCount += 1
            saveContext()
            return
        }
        if episode.firstResponseAt == nil {
            episode.firstResponseAt = date
            episode.responseKind = kind
            let summary = summaryRecord(for: episode.startedAt)
            summary.responseDurationTotal += max(0, date.timeIntervalSince(episode.startedAt))
            summary.responseCount += 1
        }
        saveContext()
    }

    func completeOverload(id: UUID, at date: Date) {
        guard let episode = overloadEpisode(id: id) else { return }
        episode.endedAt = date
        episode.completed = true
        saveContext()
    }

    @discardableResult
    func recordRestAttempt(
        id: UUID = UUID(),
        overloadEpisodeID: UUID?,
        startedAt: Date,
        endedAt: Date,
        startFatigue: Double,
        endFatigue: Double,
        source: String,
        outcome: String,
        interruptionReason: String?
    ) -> Bool {
        let existingDescriptor = FetchDescriptor<RestAttemptRecord>(
            predicate: #Predicate { $0.id == id }
        )
        if (try? context.fetch(existingDescriptor).first) != nil {
            return saveContext()
        }
        context.insert(RestAttemptRecord(
            id: id,
            overloadEpisodeID: overloadEpisodeID,
            startedAt: startedAt,
            endedAt: endedAt,
            startFatigue: startFatigue,
            endFatigue: endFatigue,
            source: source,
            outcome: outcome,
            interruptionReason: interruptionReason
        ))
        let summary = summaryRecord(for: endedAt)
        if outcome == "completed" {
            summary.completedRestCount += 1
        } else {
            summary.interruptedRestCount += 1
        }
        if source == RestTrigger.manual.rawValue {
            summary.manualRestCount += 1
        } else if source != RestTrigger.inactivity.rawValue {
            summary.systemRestCount += 1
        }
        return saveContext()
    }

    func analytics(now: Date = Date()) -> AnalyticsSnapshot {
        let calendar = calendar
        let startOfToday = calendar.startOfDay(for: now)
        let sevenDaysAgo = calendar.date(byAdding: .day, value: -6, to: startOfToday) ?? startOfToday
        let endOfToday = calendar.date(byAdding: .day, value: 1, to: startOfToday) ?? now
        let sampleUpperBound = min(now, endOfToday)
        let sampleDescriptor = FetchDescriptor<FatigueSampleRecord>(
            predicate: #Predicate {
                $0.timestamp >= startOfToday && $0.timestamp <= sampleUpperBound
            },
            sortBy: [SortDescriptor(\.timestamp)]
        )
        let samples = (try? context.fetch(sampleDescriptor)) ?? []

        let sevenDayKeys = Set((0..<7).compactMap { offset in
            calendar.date(byAdding: .day, value: offset, to: sevenDaysAgo).map {
                dayKey(for: $0, calendar: calendar)
            }
        })
        let todayKey = dayKey(for: now, calendar: calendar)
        let summaryDescriptor = FetchDescriptor<DailySummaryRecord>(
            sortBy: [SortDescriptor(\.date)]
        )
        let summaries = ((try? context.fetch(summaryDescriptor)) ?? []).filter {
            sevenDayKeys.contains($0.dayKey)
        }
        let todaySummaries = summaries.filter { $0.dayKey == todayKey }

        let attemptDescriptor = FetchDescriptor<RestAttemptRecord>(
            predicate: #Predicate {
                $0.endedAt >= sevenDaysAgo && $0.endedAt < endOfToday
            },
            sortBy: [SortDescriptor(\.endedAt)]
        )
        let attempts = (try? context.fetch(attemptDescriptor)) ?? []
        let todayAttempts = attempts.filter { calendar.isDate($0.endedAt, inSameDayAs: now) }

        return AnalyticsSnapshot(
            fatiguePoints: downsample(samples, interval: 5 * 60),
            dailyPoints: dailyAnalyticsPoints(
                from: summaries,
                startDate: sevenDaysAgo,
                dayCount: 7
            ),
            today: metrics(from: todaySummaries, attempts: todayAttempts),
            week: metrics(from: summaries, attempts: attempts)
        )
    }

    @discardableResult
    func cleanExpiredData(now: Date = Date()) -> Bool {
        let nextMaintenanceBeforeStep = nextMaintenanceAt
        let maintenanceRunCountBeforeStep = maintenanceRunCount
        let maintenanceLastScanCountBeforeStep = maintenanceLastScanCount
        let maintenanceStateBeforeStep = sampleMaintenanceState
        performMaintenanceIfNeeded(now: now)
        guard saveContext() else {
            context.rollback()
            nextMaintenanceAt = nextMaintenanceBeforeStep
            maintenanceRunCount = maintenanceRunCountBeforeStep
            maintenanceLastScanCount = maintenanceLastScanCountBeforeStep
            sampleMaintenanceState = maintenanceStateBeforeStep
            return false
        }
        return sampleMaintenanceState != nil
    }

    @discardableResult
    func clearAll() -> Bool {
        do {
            try context.transaction {
                try deleteAll(FatigueSampleRecord.self)
                try deleteAll(OverloadEpisodeRecord.self)
                try deleteAll(RestAttemptRecord.self)
                try deleteAll(DailySummaryRecord.self)
                try contextSaveHook?()
            }
        } catch {
            context.rollback()
            Self.logger.error("Unable to clear data: \(error.localizedDescription, privacy: .public)")
            return false
        }
        defaults.removeObject(forKey: Self.runtimeStateKey)
        defaults.removeObject(forKey: Self.usageTrackerKey)
        usageTracker = .empty
        bufferedSamples.removeAll(keepingCapacity: true)
        sampleMaintenanceState = nil
        maintenanceLastScanCount = 0
        nextMaintenanceAt = .distantPast
        return true
    }

    private func deleteAll<T: PersistentModel>(_ model: T.Type) throws {
        try context.enumerate(
            FetchDescriptor<T>(),
            batchSize: Self.maintenanceSampleBatchSize,
            allowEscapingMutations: true
        ) { record in
            context.delete(record)
        }
    }

    private func verifiedUsageDuration(
        at date: Date,
        elapsed: TimeInterval,
        continuousUsageDuration: TimeInterval,
        contributesToFatigue: Bool
    ) -> TimeInterval {
        guard contributesToFatigue else { return 0 }

        let normalizedElapsed = elapsed.isFinite ? max(0, elapsed) : 0
        guard normalizedElapsed > 0 else { return 0 }

        var upperBounds = [normalizedElapsed, continuousUsageDuration]
        if let lastSampleAt = usageTracker.lastSampleAt {
            let wallInterval = date.timeIntervalSince(lastSampleAt)
            guard wallInterval >= 0 else { return 0 }
            upperBounds.append(wallInterval)
            if wallInterval > PresenceEngine.passiveStaticWindow {
                resetUsageSegment()
                usageTracker.lastPresenceContributed = false
            }
        }

        if let previousContinuousUsage = usageTracker.lastContinuousUsageDuration {
            let continuousDelta: TimeInterval
            if continuousUsageDuration >= previousContinuousUsage {
                continuousDelta = continuousUsageDuration - previousContinuousUsage
            } else {
                // A completed rest resets AppModel's cumulative counter.
                continuousDelta = continuousUsageDuration
            }
            upperBounds.append(max(0, continuousDelta))
        }

        return max(0, upperBounds.min() ?? 0)
    }

    private func recordContinuousUsage(
        duration: TimeInterval,
        endingAt date: Date,
        reportedContinuousUsageDuration: TimeInterval,
        seedFromReportedCounter: Bool
    ) {
        if seedFromReportedCounter {
            let day = calendar.startOfDay(for: date)
            let durationAvailableToday = max(0, date.timeIntervalSince(day))
            usageTracker.activeSegmentDay = day
            usageTracker.activeSegmentDuration = min(
                reportedContinuousUsageDuration,
                durationAvailableToday
            )
            let summary = summaryRecord(for: date)
            summary.longestUsageDuration = max(
                summary.longestUsageDuration,
                usageTracker.activeSegmentDuration
            )
            return
        }

        guard duration > 0 else { return }
        var cursor = date.addingTimeInterval(-duration)
        while cursor < date {
            let day = calendar.startOfDay(for: cursor)
            let nextDay = calendar.date(byAdding: .day, value: 1, to: day) ?? date
            let segmentEnd = min(date, nextDay)
            let segmentDuration = max(0, segmentEnd.timeIntervalSince(cursor))

            if usageTracker.activeSegmentDay.map({ !calendar.isDate($0, inSameDayAs: day) }) ?? true {
                usageTracker.activeSegmentDay = day
                usageTracker.activeSegmentDuration = 0
            }
            usageTracker.activeSegmentDuration += segmentDuration
            let summary = summaryRecord(for: day)
            summary.longestUsageDuration = max(
                summary.longestUsageDuration,
                usageTracker.activeSegmentDuration
            )
            cursor = segmentEnd
        }
    }

    private func recordOverloadUsage(
        duration: TimeInterval,
        endingAt date: Date,
        previousFatigue: Double?,
        currentFatigue: Double
    ) {
        guard duration > 0, currentFatigue >= 100 else { return }

        let overloadFraction: Double
        if let previousFatigue, previousFatigue < 100 {
            let increase = currentFatigue - previousFatigue
            overloadFraction = increase > 0
                ? min(1, max(0, (currentFatigue - 100) / increase))
                : 0
        } else {
            overloadFraction = 1
        }

        let overloadDuration = duration * overloadFraction
        guard overloadDuration > 0 else { return }
        addOverloadDuration(
            from: date.addingTimeInterval(-overloadDuration),
            to: date
        )
    }

    private func addOverloadDuration(from start: Date, to end: Date) {
        guard end > start else { return }
        var cursor = start
        while cursor < end {
            let day = calendar.startOfDay(for: cursor)
            let nextDay = calendar.date(byAdding: .day, value: 1, to: day) ?? end
            let segmentEnd = min(end, nextDay)
            summaryRecord(for: day).overloadDuration += max(
                0,
                segmentEnd.timeIntervalSince(cursor)
            )
            cursor = segmentEnd
        }
    }

    private func resetUsageSegment() {
        usageTracker.activeSegmentDay = nil
        usageTracker.activeSegmentDuration = 0
    }

    private func saveUsageTracker() {
        do {
            defaults.set(
                try JSONEncoder().encode(usageTracker),
                forKey: Self.usageTrackerKey
            )
        } catch {
            Self.logger.error("Unable to encode analytics usage state: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func upsertSample(
        at date: Date,
        fatigue: Double,
        presenceState: String
    ) {
        let bucketStart = Self.sampleBucketStart(for: date)
        let bucketEnd = bucketStart.addingTimeInterval(Self.sampleBucketInterval)
        let descriptor = FetchDescriptor<FatigueSampleRecord>(
            predicate: #Predicate {
                $0.timestamp >= bucketStart && $0.timestamp < bucketEnd
            }
        )
        let existing = (try? context.fetch(descriptor)) ?? []
        for record in existing {
            record.isBucketLatest = false
        }
        let candidate = FatigueSampleRecord(
            timestamp: date,
            fatigue: fatigue,
            presenceState: presenceState,
            isBucketLatest: true
        )
        context.insert(candidate)
        retainPeakAndLatest(in: existing + [candidate])
    }

    private func performMaintenanceIfNeeded(now: Date) {
        guard sampleMaintenanceState != nil || now >= nextMaintenanceAt else { return }
        performMaintenance(now: now)
    }

    private func performMaintenance(now: Date) {
        if sampleMaintenanceState == nil {
            maintenanceRunCount += 1
            let sampleCutoff = now.addingTimeInterval(-Self.sampleRetentionInterval)
            let detailCutoff = now.addingTimeInterval(-Self.detailRetentionInterval)
            let summaryCutoff = now.addingTimeInterval(-Self.summaryRetentionInterval)
            do {
                try context.delete(
                    model: FatigueSampleRecord.self,
                    where: #Predicate { $0.timestamp < sampleCutoff }
                )
                try context.delete(
                    model: OverloadEpisodeRecord.self,
                    where: #Predicate { $0.startedAt < detailCutoff }
                )
                try context.delete(
                    model: RestAttemptRecord.self,
                    where: #Predicate { $0.startedAt < detailCutoff }
                )
                try context.delete(
                    model: DailySummaryRecord.self,
                    where: #Predicate { $0.date < summaryCutoff }
                )
            } catch {
                Self.logger.error("Unable to expire analytics data: \(error.localizedDescription, privacy: .public)")
            }
            sampleMaintenanceState = SampleMaintenanceState(
                cutoff: sampleCutoff,
                // Normal sampling only mutates the current wall-clock bucket. Keeping
                // that bucket outside the scan makes fetchOffset stable while the
                // bounded upgrade pass is running.
                upperBound: Self.sampleBucketStart(for: now)
            )
        }

        compactSampleMaintenanceStep()
        nextMaintenanceAt = sampleMaintenanceState == nil
            ? now.addingTimeInterval(Self.maintenanceInterval)
            : .distantPast
    }

    private func compactSampleMaintenanceStep() {
        guard var state = sampleMaintenanceState else { return }
        maintenanceLastScanCount = 0
        do {
            if state.isScanning {
                let cutoff = state.cutoff
                let upperBound = state.upperBound
                var descriptor = FetchDescriptor<FatigueSampleRecord>(
                    predicate: #Predicate {
                        $0.timestamp >= cutoff && $0.timestamp < upperBound
                    },
                    sortBy: [SortDescriptor(\.timestamp)]
                )
                descriptor.fetchLimit = Self.maintenanceSampleBatchSize
                descriptor.fetchOffset = state.scanOffset
                let records = try context.fetch(descriptor)
                maintenanceLastScanCount = records.count
                for record in records {
                    let bucket = Self.sampleBucketStart(for: record.timestamp)
                    if var retention = state.buckets[bucket] {
                        retention.observe(record)
                        state.buckets[bucket] = retention
                    } else {
                        state.buckets[bucket] = SampleBucketRetention(record)
                    }
                }
                state.scanOffset += records.count
                if records.count < Self.maintenanceSampleBatchSize {
                    state.deletions = state.buckets.compactMap { bucketStart, retention in
                        guard retention.count > 2 else { return nil }
                        return SampleBucketDeletion(
                            bucketStart: bucketStart,
                            peakID: retention.peakID,
                            latestID: retention.latestID
                        )
                    }.sorted { $0.bucketStart < $1.bucketStart }
                    state.buckets.removeAll(keepingCapacity: false)
                    state.isScanning = false
                }
            }

            if !state.isScanning {
                let deletionEnd = min(
                    state.deletionIndex + Self.maintenanceBucketDeleteLimit,
                    state.deletions.count
                )
                for index in state.deletionIndex..<deletionEnd {
                    let deletion = state.deletions[index]
                    let bucketStart = deletion.bucketStart
                    let bucketEnd = bucketStart.addingTimeInterval(Self.sampleBucketInterval)
                    let peakID = deletion.peakID
                    let latestID = deletion.latestID
                    try context.delete(
                        model: FatigueSampleRecord.self,
                        where: #Predicate {
                            $0.timestamp >= bucketStart &&
                                $0.timestamp < bucketEnd &&
                                $0.id != peakID &&
                                $0.id != latestID
                        }
                    )
                }
                state.deletionIndex = deletionEnd
            }
            sampleMaintenanceState = !state.isScanning &&
                state.deletionIndex == state.deletions.count
                ? nil
                : state
        } catch {
            Self.logger.error("Unable to compact fatigue samples: \(error.localizedDescription, privacy: .public)")
            sampleMaintenanceState = state
        }
    }

    private func retainPeakAndLatest(in records: [FatigueSampleRecord]) {
        guard !records.isEmpty else { return }
        let peak = records.max { left, right in
            if left.fatigue == right.fatigue {
                return left.timestamp < right.timestamp
            }
            return left.fatigue < right.fatigue
        }
        var arrivalLatest: FatigueSampleRecord?
        for record in records where record.isBucketLatest == true {
            if arrivalLatest == nil ||
                record.timestamp >= (arrivalLatest?.timestamp ?? .distantPast) {
                arrivalLatest = record
            }
        }
        let latest = arrivalLatest ?? records.reduce(records[0]) { current, candidate in
            candidate.timestamp >= current.timestamp ? candidate : current
        }
        var retainedIDs = Set([latest.id])
        if let peak {
            retainedIDs.insert(peak.id)
        }
        for record in records where !retainedIDs.contains(record.id) {
            context.delete(record)
        }
    }

    private static func sampleBucketStart(for date: Date) -> Date {
        Date(
            timeIntervalSince1970: floor(
                date.timeIntervalSince1970 / sampleBucketInterval
            ) * sampleBucketInterval
        )
    }

    private func curveSamples(from samples: [BufferedSample]) -> [BufferedSample] {
        var retainedByBucket: [Date: (peak: BufferedSample, latest: BufferedSample)] = [:]
        for sample in samples {
            let bucket = Self.sampleBucketStart(for: sample.date)
            guard var retained = retainedByBucket[bucket] else {
                retainedByBucket[bucket] = (sample, sample)
                continue
            }
            if sample.fatigue > retained.peak.fatigue ||
                (sample.fatigue == retained.peak.fatigue &&
                    (sample.date > retained.peak.date ||
                        (sample.date == retained.peak.date &&
                            sample.sequence > retained.peak.sequence))) {
                retained.peak = sample
            }
            if sample.sequence > retained.latest.sequence {
                retained.latest = sample
            }
            retainedByBucket[bucket] = retained
        }

        return retainedByBucket.values.flatMap { retained in
            retained.peak.sequence == retained.latest.sequence
                ? [retained.peak]
                : [retained.peak, retained.latest]
        }.sorted { $0.sequence < $1.sequence }
    }

    private func summaryRecord(for date: Date) -> DailySummaryRecord {
        let calendar = calendar
        let day = calendar.startOfDay(for: date)
        let dayKey = dayKey(for: day, calendar: calendar)
        let descriptor = FetchDescriptor<DailySummaryRecord>(
            predicate: #Predicate { $0.dayKey == dayKey }
        )
        if let existing = try? context.fetch(descriptor).first {
            return existing
        }
        let summary = DailySummaryRecord(dayKey: dayKey, date: day)
        context.insert(summary)
        return summary
    }

    private func overloadEpisode(id: UUID) -> OverloadEpisodeRecord? {
        let descriptor = FetchDescriptor<OverloadEpisodeRecord>(
            predicate: #Predicate { $0.id == id }
        )
        return try? context.fetch(descriptor).first
    }

    private func metrics(
        from summaries: [DailySummaryRecord],
        attempts: [RestAttemptRecord]
    ) -> AnalyticsMetrics {
        let responseTotal = summaries.reduce(0) { $0 + $1.responseDurationTotal }
        let responseCount = summaries.reduce(0) { $0 + $1.responseCount }
        let manualRestCount = attempts.count { $0.source == RestTrigger.manual.rawValue }
        let inactivityRestCount = attempts.count {
            $0.source == RestTrigger.inactivity.rawValue
        }
        let systemRestCount = attempts.count { attempt in
            switch attempt.source {
            case RestTrigger.screenLocked.rawValue,
                 RestTrigger.displayAsleep.rawValue,
                 RestTrigger.systemSleep.rawValue,
                 "system":
                true
            default:
                false
            }
        }
        return AnalyticsMetrics(
            peakFatigue: summaries.map(\.peakFatigue).max() ?? 0,
            overloadDuration: summaries.reduce(0) { $0 + $1.overloadDuration },
            longestUsageDuration: summaries.map(\.longestUsageDuration).max() ?? 0,
            completedRestCount: summaries.reduce(0) { $0 + $1.completedRestCount },
            interruptedRestCount: summaries.reduce(0) { $0 + $1.interruptedRestCount },
            continuedWorkingCount: summaries.reduce(0) { $0 + $1.continuedWorkingCount },
            averageResponseDuration: responseCount > 0 ? responseTotal / Double(responseCount) : nil,
            manualRestCount: manualRestCount,
            systemRestCount: systemRestCount,
            inactivityRestCount: inactivityRestCount
        )
    }

    private func dailyAnalyticsPoints(
        from summaries: [DailySummaryRecord],
        startDate: Date,
        dayCount: Int
    ) -> [DailyAnalyticsPoint] {
        guard dayCount > 0 else { return [] }
        let calendar = calendar

        let summariesByDay = Dictionary(summaries.map { ($0.dayKey, $0) }) { current, candidate in
            candidate.date >= current.date ? candidate : current
        }

        return (0..<dayCount).compactMap { dayOffset in
            guard let date = calendar.date(byAdding: .day, value: dayOffset, to: startDate) else {
                return nil
            }
            let day = calendar.startOfDay(for: date)
            let summary = summariesByDay[dayKey(for: day, calendar: calendar)]
            return DailyAnalyticsPoint(
                date: day,
                peakFatigue: summary?.peakFatigue ?? 0,
                overloadDuration: summary?.overloadDuration ?? 0,
                longestUsageDuration: summary?.longestUsageDuration ?? 0
            )
        }
    }

    private func downsample(
        _ samples: [FatigueSampleRecord],
        interval: TimeInterval
    ) -> [FatiguePoint] {
        guard interval > 0 else {
            return samples.map { FatiguePoint(timestamp: $0.timestamp, fatigue: $0.fatigue) }
        }

        var points: [FatiguePoint] = []
        var bucket: Int64?
        var peak: FatigueSampleRecord?
        var timestampLatest: FatigueSampleRecord?
        var arrivalLatest: FatigueSampleRecord?

        func appendBucket() {
            let latest: FatigueSampleRecord?
            if let arrivalLatest {
                latest = arrivalLatest
            } else if let timestampLatest {
                latest = timestampLatest
            } else {
                latest = nil
            }
            let samples: [FatigueSampleRecord]
            if let peak, let latest, peak.id != latest.id {
                samples = [peak, latest].sorted { $0.timestamp < $1.timestamp }
            } else if let peak {
                samples = [peak]
            } else if let latest {
                samples = [latest]
            } else {
                samples = []
            }
            points.append(contentsOf: samples.map {
                FatiguePoint(timestamp: $0.timestamp, fatigue: $0.fatigue)
            })
        }

        for sample in samples {
            let sampleBucket = Int64(
                floor(sample.timestamp.timeIntervalSince1970 / interval)
            )
            if let bucket, bucket != sampleBucket {
                appendBucket()
                peak = nil
                timestampLatest = nil
                arrivalLatest = nil
            }
            bucket = sampleBucket
            if peak == nil || sample.fatigue > (peak?.fatigue ?? -.infinity) {
                peak = sample
            }
            timestampLatest = sample
            if sample.isBucketLatest == true {
                arrivalLatest = sample
            }
        }
        if timestampLatest != nil {
            appendBucket()
        }
        return points
    }

    @discardableResult
    private func saveContext() -> Bool {
        do {
            try commitContext()
            return true
        } catch {
            Self.logger.error("Unable to save data: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    private func commitContext() throws {
        try contextSaveHook?()
        try context.save()
    }

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .autoupdatingCurrent
        return calendar
    }

    private func dayKey(for date: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(
            format: "%04d-%02d-%02d",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0
        )
    }
}
