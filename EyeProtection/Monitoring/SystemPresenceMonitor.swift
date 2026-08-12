import AppKit
import CoreGraphics
import Foundation

/// Tracks high-confidence system-level away signals. Ordinary input idleness is
/// intentionally not included here and must not start a rest by itself.
@MainActor
public final class SystemPresenceMonitor {
    public enum Reason: String, CaseIterable, Sendable {
        case active
        case systemSleep
        case screensAsleep
        case sessionInactive
    }

    public struct State: Equatable, Sendable {
        public let isAway: Bool
        public let reason: Reason
        public let timestamp: Date

        public init(isAway: Bool, reason: Reason, timestamp: Date) {
            self.isAway = isAway
            self.reason = reason
            self.timestamp = timestamp
        }
    }

    public typealias ChangeHandler = @MainActor @Sendable (State) -> Void

    public var onChange: ChangeHandler?
    public private(set) var isRunning = false
    public private(set) var state = State(isAway: false, reason: .active, timestamp: Date())

    private var activeReasons: Set<Reason> = []
    private var workspaceTokens: [NSObjectProtocol] = []
    private var distributedTokens: [NSObjectProtocol] = []

    public init() {}

    public func start() {
        guard !isRunning else { return }
        isRunning = true

        let workspaceCenter = NSWorkspace.shared.notificationCenter
        observe(workspaceCenter, name: NSWorkspace.willSleepNotification) { monitor in
            monitor.set(.systemSleep, active: true)
        }
        observe(workspaceCenter, name: NSWorkspace.didWakeNotification) { monitor in
            monitor.set(.systemSleep, active: false)
        }
        observe(workspaceCenter, name: NSWorkspace.screensDidSleepNotification) { monitor in
            monitor.set(.screensAsleep, active: true)
        }
        observe(workspaceCenter, name: NSWorkspace.screensDidWakeNotification) { monitor in
            monitor.set(.screensAsleep, active: false)
        }
        observe(workspaceCenter, name: NSWorkspace.sessionDidResignActiveNotification) { monitor in
            monitor.set(.sessionInactive, active: true)
        }
        observe(workspaceCenter, name: NSWorkspace.sessionDidBecomeActiveNotification) { monitor in
            monitor.set(.sessionInactive, active: false)
        }

        let distributedCenter = DistributedNotificationCenter.default()
        observe(distributedCenter, name: Notification.Name("com.apple.screenIsLocked")) { monitor in
            monitor.set(.sessionInactive, active: true)
        }
        observe(distributedCenter, name: Notification.Name("com.apple.screenIsUnlocked")) { monitor in
            monitor.set(.sessionInactive, active: false)
        }

        if CGDisplayIsAsleep(CGMainDisplayID()) != 0 {
            set(.screensAsleep, active: true)
        } else {
            publishIfChanged()
        }
    }

    public func stop() {
        guard isRunning else { return }

        let workspaceCenter = NSWorkspace.shared.notificationCenter
        workspaceTokens.forEach(workspaceCenter.removeObserver)
        workspaceTokens.removeAll()
        let distributedCenter = DistributedNotificationCenter.default()
        distributedTokens.forEach(distributedCenter.removeObserver)
        distributedTokens.removeAll()

        activeReasons.removeAll()
        isRunning = false
        publishIfChanged()
    }

    private func observe(
        _ center: NotificationCenter,
        name: Notification.Name,
        action: @escaping @MainActor @Sendable (SystemPresenceMonitor) -> Void
    ) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.isRunning else { return }
                action(self)
            }
        }
        workspaceTokens.append(token)
    }

    private func observe(
        _ center: DistributedNotificationCenter,
        name: Notification.Name,
        action: @escaping @MainActor @Sendable (SystemPresenceMonitor) -> Void
    ) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.isRunning else { return }
                action(self)
            }
        }
        distributedTokens.append(token)
    }

    private func set(_ reason: Reason, active: Bool) {
        guard reason != .active else { return }
        if active {
            activeReasons.insert(reason)
        } else {
            activeReasons.remove(reason)
        }
        publishIfChanged()
    }

    private func publishIfChanged() {
        let reason = primaryReason
        let isAway = reason != .active
        guard state.isAway != isAway || state.reason != reason else { return }

        state = State(isAway: isAway, reason: reason, timestamp: Date())
        onChange?(state)
    }

    private var primaryReason: Reason {
        // Keep the most explicit/high-confidence evidence when several system
        // transitions overlap during sleep or fast-user switching.
        if activeReasons.contains(.systemSleep) { return .systemSleep }
        if activeReasons.contains(.sessionInactive) { return .sessionInactive }
        if activeReasons.contains(.screensAsleep) { return .screensAsleep }
        return .active
    }

}
