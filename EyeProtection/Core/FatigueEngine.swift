import Foundation

/// A deterministic fatigue state machine. Callers own the clock and provide elapsed
/// durations, which keeps sensor collection and persistence outside the domain layer.
public struct FatigueEngine: Sendable {
    public static let defaultUsageDurationForOneHundredPercent: TimeInterval = 20 * 60
    public static let defaultRequiredContinuousRestDuration: TimeInterval = 20

    public private(set) var snapshot: FatigueSnapshot
    public private(set) var usageDurationForOneHundredPercent: TimeInterval
    public private(set) var requiredContinuousRestDuration: TimeInterval

    public var isResting: Bool {
        snapshot.isResting
    }

    /// Normalized to 0...1 for the full-screen countdown UI.
    public var restProgress: Double {
        guard let activeRest = snapshot.activeRest else { return 0 }
        return min(
            1,
            max(0, activeRest.elapsed / requiredContinuousRestDuration)
        )
    }

    public var restRemaining: TimeInterval {
        guard let activeRest = snapshot.activeRest else { return 0 }
        return max(0, requiredContinuousRestDuration - activeRest.elapsed)
    }

    public init(
        snapshot: FatigueSnapshot = .initial,
        usageDurationForOneHundredPercent: TimeInterval = Self.defaultUsageDurationForOneHundredPercent,
        requiredContinuousRestDuration: TimeInterval = Self.defaultRequiredContinuousRestDuration
    ) {
        self.usageDurationForOneHundredPercent = Self.normalizedDuration(
            usageDurationForOneHundredPercent,
            fallback: Self.defaultUsageDurationForOneHundredPercent
        )
        self.requiredContinuousRestDuration = Self.normalizedDuration(
            requiredContinuousRestDuration,
            fallback: Self.defaultRequiredContinuousRestDuration
        )
        var normalized = snapshot
        if !normalized.fatiguePercent.isFinite || normalized.fatiguePercent < 0 {
            normalized.fatiguePercent = 0
        }
        if normalized.fatiguePercent >= 100 {
            normalized.restRequired = true
        }
        if normalized.overloadStartedAt == nil {
            normalized.overloadStartedAt = normalized.activeOverloadEpisode?.startedAt
        }
        if normalized.activeOverloadEpisode == nil,
           let overloadStartedAt = normalized.overloadStartedAt,
           normalized.restRequired {
            normalized.activeOverloadEpisode = OverloadEpisode(
                startedAt: overloadStartedAt,
                peakFatiguePercent: max(100, normalized.fatiguePercent)
            )
        }
        self.snapshot = normalized
    }

    /// Changes the usage and rest targets. Updating the usage target rescales current
    /// fatigue so it continues to represent the same accumulated usage time.
    /// An active rest keeps the duration it started with until it finishes or is interrupted.
    @discardableResult
    public mutating func updateDurations(
        usageDurationForOneHundredPercent: TimeInterval,
        requiredContinuousRestDuration: TimeInterval,
        at timestamp: Date
    ) -> [FatigueEvent]? {
        guard snapshot.activeRest == nil else { return nil }

        let previousUsageDuration = self.usageDurationForOneHundredPercent
        let updatedUsageDuration = Self.normalizedDuration(
            usageDurationForOneHundredPercent,
            fallback: Self.defaultUsageDurationForOneHundredPercent
        )
        self.usageDurationForOneHundredPercent = updatedUsageDuration
        self.requiredContinuousRestDuration = Self.normalizedDuration(
            requiredContinuousRestDuration,
            fallback: Self.defaultRequiredContinuousRestDuration
        )

        guard updatedUsageDuration != previousUsageDuration,
              snapshot.fatiguePercent > 0 else {
            return []
        }

        let previousFatigue = snapshot.fatiguePercent
        let updatedFatigue = previousFatigue * previousUsageDuration / updatedUsageDuration
        snapshot.fatiguePercent = updatedFatigue
        var events: [FatigueEvent] = [
            .fatigueChanged(from: previousFatigue, to: updatedFatigue, at: timestamp)
        ]

        if !snapshot.restRequired, updatedFatigue >= 100 {
            snapshot.restRequired = true
            let episode = OverloadEpisode(
                startedAt: timestamp,
                peakFatiguePercent: updatedFatigue
            )
            snapshot.overloadStartedAt = timestamp
            snapshot.activeOverloadEpisode = episode
            events.append(.restRequired(episode))
        } else if var episode = snapshot.activeOverloadEpisode {
            episode.peakFatiguePercent = max(episode.peakFatiguePercent, updatedFatigue)
            snapshot.activeOverloadEpisode = episode
        }

        return events
    }

    /// Adds verified computer-use time. Fatigue has no upper bound.
    ///
    /// If a rest is currently active, usage is ignored until the caller explicitly
    /// interrupts that rest. This avoids inventing an interruption reason.
    @discardableResult
    public mutating func accrueUsage(
        for duration: TimeInterval,
        endingAt timestamp: Date
    ) -> [FatigueEvent] {
        guard duration.isFinite, duration > 0, snapshot.activeRest == nil else {
            return []
        }

        let previousFatigue = snapshot.fatiguePercent
        let increase = duration / usageDurationForOneHundredPercent * 100
        let updatedFatigue = previousFatigue + increase
        snapshot.fatiguePercent = updatedFatigue

        var events: [FatigueEvent] = [
            .fatigueChanged(from: previousFatigue, to: updatedFatigue, at: timestamp)
        ]

        if !snapshot.restRequired, updatedFatigue >= 100 {
            snapshot.restRequired = true

            let secondsToThreshold = max(
                0,
                (100 - previousFatigue) / 100 * usageDurationForOneHundredPercent
            )
            let thresholdDate = timestamp.addingTimeInterval(
                -max(0, duration - secondsToThreshold)
            )
            let episode = OverloadEpisode(
                startedAt: thresholdDate,
                peakFatiguePercent: updatedFatigue
            )
            snapshot.activeOverloadEpisode = episode
            snapshot.overloadStartedAt = thresholdDate
            events.append(.restRequired(episode))
        } else if var episode = snapshot.activeOverloadEpisode {
            episode.peakFatiguePercent = max(episode.peakFatiguePercent, updatedFatigue)
            snapshot.activeOverloadEpisode = episode
        }

        return events
    }

    /// Starts a user-confirmed or system-confirmed rest. Ordinary inactivity must not
    /// call this method.
    @discardableResult
    public mutating func beginRest(
        trigger: RestTrigger,
        at timestamp: Date
    ) -> [FatigueEvent] {
        guard snapshot.activeRest == nil,
              snapshot.fatiguePercent > 0 || snapshot.restRequired else {
            return []
        }

        let rest = ActiveRestSession(
            trigger: trigger,
            startedAt: timestamp,
            startFatiguePercent: snapshot.fatiguePercent
        )
        snapshot.activeRest = rest

        if var episode = snapshot.activeOverloadEpisode,
           episode.firstRestStartedAt == nil {
            episode.firstRestStartedAt = timestamp
            snapshot.activeOverloadEpisode = episode
        }

        return [.restStarted(rest)]
    }

    /// Advances an already-confirmed rest. Recovery is based on the fatigue value at
    /// rest start, so ten continuous seconds always halves that starting value.
    @discardableResult
    public mutating func advanceRest(
        by duration: TimeInterval,
        endingAt timestamp: Date
    ) -> [FatigueEvent] {
        guard duration.isFinite, duration > 0, var rest = snapshot.activeRest else {
            return []
        }

        let previousFatigue = snapshot.fatiguePercent
        let rawElapsed = rest.elapsed + duration
        let completedElapsed = min(
            rawElapsed,
            requiredContinuousRestDuration
        )
        rest.elapsed = completedElapsed

        let recoveryFraction = completedElapsed / requiredContinuousRestDuration
        let updatedFatigue = max(
            0,
            rest.startFatiguePercent * (1 - recoveryFraction)
        )
        snapshot.fatiguePercent = updatedFatigue
        snapshot.activeRest = rest

        let overflow = max(0, rawElapsed - requiredContinuousRestDuration)
        let effectiveTimestamp = timestamp.addingTimeInterval(-overflow)
        var events: [FatigueEvent] = [
            .fatigueChanged(
                from: previousFatigue,
                to: updatedFatigue,
                at: effectiveTimestamp
            )
        ]

        guard completedElapsed >= requiredContinuousRestDuration else {
            return events
        }

        let attempt = RestAttempt(
            id: rest.id,
            trigger: rest.trigger,
            startedAt: rest.startedAt,
            endedAt: effectiveTimestamp,
            startFatiguePercent: rest.startFatiguePercent,
            duration: requiredContinuousRestDuration,
            endFatiguePercent: 0,
            outcome: .completed
        )
        snapshot.fatiguePercent = 0
        snapshot.activeRest = nil
        snapshot.restRequired = false
        snapshot.overloadStartedAt = nil
        events.append(.restCompleted(attempt))

        if var episode = snapshot.activeOverloadEpisode {
            episode.endedAt = effectiveTimestamp
            episode.completedBy = rest.trigger
            snapshot.activeOverloadEpisode = nil
            events.append(.overloadCompleted(episode))
        }

        return events
    }

    /// Completes a rest that has already been verified by an external signal, such
    /// as a configured period with no keyboard, pointer or trackpad input. This is
    /// independent of the countdown used by an explicitly started rest.
    @discardableResult
    public mutating func completeConfirmedRest(
        trigger: RestTrigger,
        qualifyingDuration: TimeInterval,
        endingAt timestamp: Date
    ) -> [FatigueEvent] {
        guard qualifyingDuration.isFinite,
              qualifyingDuration > 0,
              snapshot.activeRest == nil,
              snapshot.fatiguePercent > 0 || snapshot.restRequired else {
            return []
        }

        let previousFatigue = snapshot.fatiguePercent
        let rest = ActiveRestSession(
            trigger: trigger,
            startedAt: timestamp,
            startFatiguePercent: previousFatigue,
            elapsed: qualifyingDuration
        )

        if var episode = snapshot.activeOverloadEpisode,
           episode.firstRestStartedAt == nil {
            episode.firstRestStartedAt = timestamp
            snapshot.activeOverloadEpisode = episode
        }

        let attempt = RestAttempt(
            id: rest.id,
            trigger: trigger,
            startedAt: timestamp.addingTimeInterval(-qualifyingDuration),
            endedAt: timestamp,
            startFatiguePercent: previousFatigue,
            duration: qualifyingDuration,
            endFatiguePercent: 0,
            outcome: .completed
        )

        snapshot.fatiguePercent = 0
        snapshot.activeRest = nil
        snapshot.restRequired = false
        snapshot.overloadStartedAt = nil

        var events: [FatigueEvent] = [
            .restStarted(rest),
            .fatigueChanged(from: previousFatigue, to: 0, at: timestamp),
            .restCompleted(attempt),
        ]

        if var episode = snapshot.activeOverloadEpisode {
            episode.endedAt = timestamp
            episode.completedBy = trigger
            snapshot.activeOverloadEpisode = nil
            events.append(.overloadCompleted(episode))
        }
        return events
    }

    /// Ends a partial rest while preserving the fatigue already recovered. A latched
    /// rest requirement remains set even when the partial rest drops fatigue below 100%.
    @discardableResult
    public mutating func interruptRest(
        reason: RestInterruptionReason,
        at timestamp: Date
    ) -> [FatigueEvent] {
        guard let rest = snapshot.activeRest else {
            return []
        }

        let attempt = RestAttempt(
            id: rest.id,
            trigger: rest.trigger,
            startedAt: rest.startedAt,
            endedAt: timestamp,
            startFatiguePercent: rest.startFatiguePercent,
            duration: rest.elapsed,
            endFatiguePercent: snapshot.fatiguePercent,
            outcome: .interrupted(reason)
        )
        snapshot.activeRest = nil
        return [.restInterrupted(attempt)]
    }

    /// Records the explicit choice to keep working without changing or postponing the
    /// latched requirement.
    @discardableResult
    public mutating func recordContinueWorking(at timestamp: Date) -> [FatigueEvent] {
        guard snapshot.restRequired else {
            return []
        }
        return [.continuedWorking(at: timestamp)]
    }

    private static func normalizedDuration(
        _ duration: TimeInterval,
        fallback: TimeInterval
    ) -> TimeInterval {
        guard duration.isFinite, duration > 0 else { return fallback }
        return max(1, duration)
    }
}
