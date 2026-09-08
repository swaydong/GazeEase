import Foundation

// MARK: - Presence

public enum PresenceState: String, Codable, Sendable, Equatable, CaseIterable {
    case activeInteraction
    case passiveStatic
    case idleUncertain
    case unobservable
    case awayConfirmed

    public var contributesToFatigue: Bool {
        switch self {
        case .activeInteraction, .passiveStatic:
            true
        case .idleUncertain, .unobservable, .awayConfirmed:
            false
        }
    }
}

public enum SystemPresenceState: String, Codable, Sendable, Equatable {
    case available
    case locked
    case displayAsleep
    case systemAsleep

    public var confirmsAway: Bool {
        self != .available
    }
}

public struct MonitoringAuthorization: Codable, Sendable, Equatable {
    public var inputMonitoringGranted: Bool

    public init(inputMonitoringGranted: Bool) {
        self.inputMonitoringGranted = inputMonitoringGranted
    }

    public static let fullyGranted = MonitoringAuthorization(
        inputMonitoringGranted: true
    )

    public var isFullyGranted: Bool {
        inputMonitoringGranted
    }
}

/// Runtime health is separate from TCC authorization.
struct MonitoringRuntimeStatus: Sendable, Equatable {
    var inputMonitorRunning: Bool

    var authorization: MonitoringAuthorization {
        MonitoringAuthorization(
            inputMonitoringGranted: inputMonitorRunning
        )
    }

    var isComplete: Bool {
        inputMonitorRunning
    }
}

/// A privacy-preserving aggregate sample. It deliberately contains no key values,
/// text or pointer coordinates.
public struct PresenceSample: Codable, Sendable, Equatable {
    public var timestamp: Date
    public var inputDetected: Bool
    public var authorization: MonitoringAuthorization
    public var systemState: SystemPresenceState

    public init(
        timestamp: Date,
        inputDetected: Bool,
        authorization: MonitoringAuthorization = .fullyGranted,
        systemState: SystemPresenceState = .available
    ) {
        self.timestamp = timestamp
        self.inputDetected = inputDetected
        self.authorization = authorization
        self.systemState = systemState
    }
}

public enum PresenceSessionEndReason: String, Codable, Sendable, Equatable {
    case authorizationLost
    case inactivity
    case systemAway
}

public enum PresenceSampleRejectionReason: String, Codable, Sendable, Equatable {
    case nonMonotonicTimestamp
}

public enum PresenceEvent: Codable, Sendable, Equatable {
    case sessionStarted(at: Date)
    case sessionEnded(at: Date, reason: PresenceSessionEndReason)
    case stateChanged(from: PresenceState, to: PresenceState, at: Date)
    case sampleRejected(at: Date, reason: PresenceSampleRejectionReason)
}

public struct PresenceUpdate: Codable, Sendable, Equatable {
    public var state: PresenceState
    public var events: [PresenceEvent]

    public init(state: PresenceState, events: [PresenceEvent]) {
        self.state = state
        self.events = events
    }
}

// MARK: - Fatigue and rest

public enum RestTrigger: String, Codable, Sendable, Equatable {
    case manual
    case inactivity
    case screenLocked
    case displayAsleep
    case systemSleep
}

public enum RestInterruptionReason: String, Codable, Sendable, Equatable {
    case keyboard
    case pointerMovement
    case click
    case scroll
    case monitoringUnavailable
    case cancelled
}

public enum RestAttemptOutcome: Codable, Sendable, Equatable {
    case completed
    case interrupted(RestInterruptionReason)
}

public struct ActiveRestSession: Codable, Sendable, Equatable, Identifiable {
    public var id: UUID
    public var trigger: RestTrigger
    public var startedAt: Date
    public var startFatiguePercent: Double
    public var elapsed: TimeInterval

    public init(
        id: UUID = UUID(),
        trigger: RestTrigger,
        startedAt: Date,
        startFatiguePercent: Double,
        elapsed: TimeInterval = 0
    ) {
        self.id = id
        self.trigger = trigger
        self.startedAt = startedAt
        self.startFatiguePercent = startFatiguePercent
        self.elapsed = elapsed
    }
}

public struct RestAttempt: Codable, Sendable, Equatable, Identifiable {
    public var id: UUID
    public var trigger: RestTrigger
    public var startedAt: Date
    public var endedAt: Date
    public var startFatiguePercent: Double
    public var duration: TimeInterval
    public var endFatiguePercent: Double
    public var outcome: RestAttemptOutcome

    public init(
        id: UUID,
        trigger: RestTrigger,
        startedAt: Date,
        endedAt: Date,
        startFatiguePercent: Double,
        duration: TimeInterval,
        endFatiguePercent: Double,
        outcome: RestAttemptOutcome
    ) {
        self.id = id
        self.trigger = trigger
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.startFatiguePercent = startFatiguePercent
        self.duration = duration
        self.endFatiguePercent = endFatiguePercent
        self.outcome = outcome
    }
}

public struct OverloadEpisode: Codable, Sendable, Equatable, Identifiable {
    public var id: UUID
    public var startedAt: Date
    public var endedAt: Date?
    public var peakFatiguePercent: Double
    public var firstRestStartedAt: Date?
    public var completedBy: RestTrigger?

    public init(
        id: UUID = UUID(),
        startedAt: Date,
        endedAt: Date? = nil,
        peakFatiguePercent: Double,
        firstRestStartedAt: Date? = nil,
        completedBy: RestTrigger? = nil
    ) {
        self.id = id
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.peakFatiguePercent = peakFatiguePercent
        self.firstRestStartedAt = firstRestStartedAt
        self.completedBy = completedBy
    }
}

/// The complete persistable state needed to restore fatigue and a latched rest requirement.
public struct FatigueSnapshot: Codable, Sendable, Equatable {
    public var fatiguePercent: Double
    public var restRequired: Bool
    public var overloadStartedAt: Date?
    public var activeRest: ActiveRestSession?
    public var activeOverloadEpisode: OverloadEpisode?

    public init(
        fatiguePercent: Double = 0,
        restRequired: Bool = false,
        overloadStartedAt: Date? = nil,
        activeRest: ActiveRestSession? = nil,
        activeOverloadEpisode: OverloadEpisode? = nil
    ) {
        self.fatiguePercent = fatiguePercent
        self.restRequired = restRequired
        self.overloadStartedAt = overloadStartedAt ?? activeOverloadEpisode?.startedAt
        self.activeRest = activeRest
        self.activeOverloadEpisode = activeOverloadEpisode
    }

    public static let initial = FatigueSnapshot()

    public var isResting: Bool {
        activeRest != nil
    }

    /// Partial recovery pauses reminders without completing the recorded rest episode.
    public var needsRestReminder: Bool {
        restRequired && fatiguePercent >= 100
    }

}

public enum FatigueEvent: Codable, Sendable, Equatable {
    case fatigueChanged(from: Double, to: Double, at: Date)
    case restRequired(OverloadEpisode)
    case restStarted(ActiveRestSession)
    case restInterrupted(RestAttempt)
    case restCompleted(RestAttempt)
    case overloadCompleted(OverloadEpisode)
    case continuedWorking(at: Date)
}
