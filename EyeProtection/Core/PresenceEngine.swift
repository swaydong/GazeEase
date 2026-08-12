import Foundation

/// Converts privacy-preserving input samples into a conservative usage state.
/// Only a real input can start or extend a usage session.
public struct PresenceEngine: Sendable {
    public static let activeInteractionWindow: TimeInterval = 10
    public static let passiveStaticWindow: TimeInterval = 15 * 60

    public private(set) var state: PresenceState
    public private(set) var lastInputAt: Date?
    public private(set) var lastObservationAt: Date?

    private var hasInputStartedSession: Bool

    public init(
        state: PresenceState = .idleUncertain,
        lastInputAt: Date? = nil,
        lastObservationAt: Date? = nil
    ) {
        self.state = state
        self.lastInputAt = lastInputAt
        self.lastObservationAt = lastObservationAt
        self.hasInputStartedSession = lastInputAt != nil
    }

    @discardableResult
    public mutating func ingest(_ sample: PresenceSample) -> PresenceUpdate {
        if let lastObservationAt, sample.timestamp < lastObservationAt {
            return PresenceUpdate(
                state: state,
                events: [
                    .sampleRejected(
                        at: sample.timestamp,
                        reason: .nonMonotonicTimestamp
                    )
                ]
            )
        }

        let previousState = state
        var events: [PresenceEvent] = []

        // Revocation clears the session so restoring permission cannot revive stale activity.
        if !sample.authorization.isFullyGranted {
            if hasInputStartedSession {
                events.append(
                    .sessionEnded(at: sample.timestamp, reason: .authorizationLost)
                )
            }
            clearSession()
            state = .unobservable
        } else if sample.systemState.confirmsAway {
            if hasInputStartedSession {
                events.append(
                    .sessionEnded(at: sample.timestamp, reason: .systemAway)
                )
            }
            clearSession()
            state = .awayConfirmed
        } else {
            if sample.inputDetected {
                if !hasInputStartedSession {
                    hasInputStartedSession = true
                    events.append(.sessionStarted(at: sample.timestamp))
                }
                lastInputAt = sample.timestamp
            }

            state = classifyAuthorizedSample(sample, events: &events)
        }

        lastObservationAt = sample.timestamp
        if state != previousState {
            events.append(
                .stateChanged(
                    from: previousState,
                    to: state,
                    at: sample.timestamp
                )
            )
        }

        return PresenceUpdate(state: state, events: events)
    }

    /// A completed rest must require fresh input before usage can start again.
    public mutating func resetAfterCompletedRest(at timestamp: Date) {
        clearSession()
        state = .idleUncertain
        if let lastObservationAt {
            self.lastObservationAt = max(lastObservationAt, timestamp)
        } else {
            lastObservationAt = timestamp
        }
    }

    private mutating func classifyAuthorizedSample(
        _ sample: PresenceSample,
        events: inout [PresenceEvent]
    ) -> PresenceState {
        guard hasInputStartedSession, let lastInputAt else {
            return .idleUncertain
        }

        let elapsedSinceInput = max(0, sample.timestamp.timeIntervalSince(lastInputAt))
        if elapsedSinceInput <= Self.activeInteractionWindow {
            return .activeInteraction
        }
        if elapsedSinceInput <= Self.passiveStaticWindow {
            return .passiveStatic
        }
        if elapsedSinceInput > Self.passiveStaticWindow {
            events.append(.sessionEnded(at: sample.timestamp, reason: .inactivity))
            clearSession()
        }
        return .idleUncertain
    }

    private mutating func clearSession() {
        hasInputStartedSession = false
        lastInputAt = nil
    }
}
