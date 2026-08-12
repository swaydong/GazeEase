import Foundation
import OSLog
import SwiftData

@MainActor
final class EventStore {
    private static let logger = Logger(subsystem: "com.local.EyeProtection", category: "EventStore")
    private static let runtimeStateKey = "runtimeState.v1"

    let container: ModelContainer
    private let context: ModelContext
    private let defaults: UserDefaults
    private let calendar: Calendar

    init(inMemory: Bool = false, defaults: UserDefaults = .standard) throws {
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
        self.context = ModelContext(container)
        self.defaults = defaults
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        self.calendar = calendar
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

    func saveRuntimeState(_ state: PersistedRuntimeState) {
        do {
            defaults.set(try JSONEncoder().encode(state), forKey: Self.runtimeStateKey)
        } catch {
            Self.logger.error("Unable to encode runtime state: \(error.localizedDescription, privacy: .public)")
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
        context.insert(FatigueSampleRecord(timestamp: date, fatigue: fatigue, presenceState: presenceState))
        let summary = summaryRecord(for: date)
        summary.peakFatigue = max(summary.peakFatigue, fatigue)
        if fatigue >= 100 {
            summary.overloadDuration += max(0, elapsed)
        }
        summary.longestUsageDuration = max(summary.longestUsageDuration, continuousUsageDuration)
        saveContext()
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

    func recordRestAttempt(
        overloadEpisodeID: UUID?,
        startedAt: Date,
        endedAt: Date,
        startFatigue: Double,
        endFatigue: Double,
        source: String,
        outcome: String,
        interruptionReason: String?
    ) {
        context.insert(RestAttemptRecord(
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
        saveContext()
    }

    func analytics(now: Date = Date()) -> AnalyticsSnapshot {
        let startOfToday = calendar.startOfDay(for: now)
        let sevenDaysAgo = calendar.date(byAdding: .day, value: -6, to: startOfToday) ?? startOfToday
        let sampleDescriptor = FetchDescriptor<FatigueSampleRecord>(
            predicate: #Predicate { $0.timestamp >= sevenDaysAgo },
            sortBy: [SortDescriptor(\.timestamp)]
        )
        let samples = (try? context.fetch(sampleDescriptor)) ?? []

        let summaryDescriptor = FetchDescriptor<DailySummaryRecord>(
            predicate: #Predicate { $0.date >= sevenDaysAgo },
            sortBy: [SortDescriptor(\.date)]
        )
        let summaries = (try? context.fetch(summaryDescriptor)) ?? []
        let todaySummaries = summaries.filter { calendar.isDate($0.date, inSameDayAs: now) }

        let attemptDescriptor = FetchDescriptor<RestAttemptRecord>(
            predicate: #Predicate { $0.endedAt >= sevenDaysAgo },
            sortBy: [SortDescriptor(\.endedAt)]
        )
        let attempts = (try? context.fetch(attemptDescriptor)) ?? []
        let todayAttempts = attempts.filter { calendar.isDate($0.endedAt, inSameDayAs: now) }

        return AnalyticsSnapshot(
            fatiguePoints: downsample(samples, interval: 5 * 60),
            dailyPeaks: summaries.map { DailyPeak(date: $0.date, peak: $0.peakFatigue) },
            today: metrics(from: todaySummaries, attempts: todayAttempts),
            week: metrics(from: summaries, attempts: attempts)
        )
    }

    func cleanExpiredData(now: Date = Date()) {
        let sampleCutoff = now.addingTimeInterval(-7 * 24 * 60 * 60)
        let detailCutoff = now.addingTimeInterval(-30 * 24 * 60 * 60)
        let summaryCutoff = now.addingTimeInterval(-365 * 24 * 60 * 60)
        delete(FatigueSampleRecord.self, before: sampleCutoff, keyPath: \.timestamp)
        delete(OverloadEpisodeRecord.self, before: detailCutoff, keyPath: \.startedAt)
        delete(RestAttemptRecord.self, before: detailCutoff, keyPath: \.startedAt)
        delete(DailySummaryRecord.self, before: summaryCutoff, keyPath: \.date)
        saveContext()
    }

    func clearAll() {
        do {
            try context.delete(model: FatigueSampleRecord.self)
            try context.delete(model: OverloadEpisodeRecord.self)
            try context.delete(model: RestAttemptRecord.self)
            try context.delete(model: DailySummaryRecord.self)
            defaults.removeObject(forKey: Self.runtimeStateKey)
            try context.save()
        } catch {
            Self.logger.error("Unable to clear data: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func summaryRecord(for date: Date) -> DailySummaryRecord {
        let day = calendar.startOfDay(for: date)
        let dayKey = Self.dayFormatter.string(from: day)
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

    private func downsample(
        _ samples: [FatigueSampleRecord],
        interval: TimeInterval
    ) -> [FatiguePoint] {
        guard interval > 0 else {
            return samples.map { FatiguePoint(timestamp: $0.timestamp, fatigue: $0.fatigue) }
        }

        var points: [FatiguePoint] = []
        var bucket: Int64?
        var latest: FatigueSampleRecord?

        for sample in samples {
            let sampleBucket = Int64(floor(sample.timestamp.timeIntervalSince1970 / interval))
            if let bucket, bucket != sampleBucket, let latest {
                points.append(FatiguePoint(timestamp: latest.timestamp, fatigue: latest.fatigue))
            }
            bucket = sampleBucket
            latest = sample
        }
        if let latest {
            points.append(FatiguePoint(timestamp: latest.timestamp, fatigue: latest.fatigue))
        }
        return points
    }

    private func delete<T: PersistentModel>(
        _ type: T.Type,
        before cutoff: Date,
        keyPath: KeyPath<T, Date>
    ) {
        let descriptor = FetchDescriptor<T>()
        guard let records = try? context.fetch(descriptor) else { return }
        for record in records where record[keyPath: keyPath] < cutoff {
            context.delete(record)
        }
    }

    private func saveContext() {
        do {
            try context.save()
        } catch {
            Self.logger.error("Unable to save data: \(error.localizedDescription, privacy: .public)")
        }
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}
