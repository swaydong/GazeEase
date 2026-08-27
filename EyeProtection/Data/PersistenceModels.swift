import Foundation
import SwiftData

@Model
final class FatigueSampleRecord {
    @Attribute(.unique) var id: UUID
    var timestamp: Date
    var fatigue: Double
    var presenceState: String
    var isBucketLatest: Bool?

    init(
        timestamp: Date,
        fatigue: Double,
        presenceState: String,
        isBucketLatest: Bool? = nil
    ) {
        self.id = UUID()
        self.timestamp = timestamp
        self.fatigue = fatigue
        self.presenceState = presenceState
        self.isBucketLatest = isBucketLatest
    }
}

@Model
final class OverloadEpisodeRecord {
    @Attribute(.unique) var id: UUID
    var startedAt: Date
    var endedAt: Date?
    var peakFatigue: Double
    var firstResponseAt: Date?
    var responseKind: String?
    var completed: Bool

    init(id: UUID = UUID(), startedAt: Date, peakFatigue: Double) {
        self.id = id
        self.startedAt = startedAt
        self.peakFatigue = peakFatigue
        self.completed = false
    }
}

@Model
final class RestAttemptRecord {
    @Attribute(.unique) var id: UUID
    var overloadEpisodeID: UUID?
    var startedAt: Date
    var endedAt: Date
    var startFatigue: Double
    var endFatigue: Double
    var source: String
    var outcome: String
    var interruptionReason: String?

    init(
        id: UUID = UUID(),
        overloadEpisodeID: UUID?,
        startedAt: Date,
        endedAt: Date,
        startFatigue: Double,
        endFatigue: Double,
        source: String,
        outcome: String,
        interruptionReason: String?
    ) {
        self.id = id
        self.overloadEpisodeID = overloadEpisodeID
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.startFatigue = startFatigue
        self.endFatigue = endFatigue
        self.source = source
        self.outcome = outcome
        self.interruptionReason = interruptionReason
    }
}

@Model
final class DailySummaryRecord {
    @Attribute(.unique) var dayKey: String
    var date: Date
    var peakFatigue: Double
    var overloadDuration: TimeInterval
    var longestUsageDuration: TimeInterval
    var completedRestCount: Int
    var interruptedRestCount: Int
    var continuedWorkingCount: Int
    var manualRestCount: Int
    var systemRestCount: Int
    var responseDurationTotal: TimeInterval
    var responseCount: Int

    init(dayKey: String, date: Date) {
        self.dayKey = dayKey
        self.date = date
        self.peakFatigue = 0
        self.overloadDuration = 0
        self.longestUsageDuration = 0
        self.completedRestCount = 0
        self.interruptedRestCount = 0
        self.continuedWorkingCount = 0
        self.manualRestCount = 0
        self.systemRestCount = 0
        self.responseDurationTotal = 0
        self.responseCount = 0
    }
}

struct PendingRestAttempt: Codable, Sendable, Equatable, Identifiable {
    var attempt: RestAttempt
    var overloadEpisodeID: UUID?

    var id: UUID { attempt.id }
}

struct PersistedRuntimeState: Codable, Sendable {
    var fatigue: Double
    var restRequired: Bool
    var overloadStartedAt: Date?
    var overloadEpisodeID: UUID?
    var continuousUsageDuration: TimeInterval
    var activeRest: ActiveRestSession? = nil
    var pendingRestAttempts: [PendingRestAttempt]? = nil
    var reminderPromptState: ReminderPromptState? = nil
    var reminderDecisionPending: Bool? = nil
    var lastInactivityRestCompletedAt: Date? = nil
    var lastReminderMultiple: Int? = nil
    var savedAt: Date
}
