import Foundation

struct InactivityRestPolicy: Sendable {
    static func thresholdReached(
        enabled: Bool,
        thresholdMinutes: Int,
        idleDuration: TimeInterval?,
        now: Date,
        lastCompletedAt: Date?,
        monitoringAvailable: Bool,
        systemAway: Bool,
        isResting: Bool
    ) -> Bool {
        guard enabled,
              thresholdMinutes > 0,
              monitoringAvailable,
              !systemAway,
              !isResting,
              let idleDuration,
              idleDuration.isFinite,
              idleDuration >= 0 else {
            return false
        }

        guard idleDuration >= TimeInterval(thresholdMinutes * 60) else {
            return false
        }

        if let lastCompletedAt {
            let idleStartedAt = now.addingTimeInterval(-idleDuration)
            guard idleStartedAt > lastCompletedAt else { return false }
        }
        return true
    }
}
