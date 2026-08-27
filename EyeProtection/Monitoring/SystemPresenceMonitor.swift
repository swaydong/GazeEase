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
    typealias CurrentReasonsProvider = @MainActor @Sendable () -> Set<Reason>

    public var onChange: ChangeHandler?
    public private(set) var isRunning = false
    public private(set) var state = State(isAway: false, reason: .active, timestamp: Date())

    private let activeTransitionDelay: Duration
    private let currentReasonsProvider: CurrentReasonsProvider
    private var activeReasons: Set<Reason> = []
    private var workspaceTokens: [NSObjectProtocol] = []
    private var distributedTokens: [NSObjectProtocol] = []
    private var activeTransitionTask: Task<Void, Never>?
    private var currentReasonsRecheckTask: Task<Void, Never>?

    public convenience init() {
        self.init(
            activeTransitionDelay: .milliseconds(300),
            currentReasonsProvider: Self.currentSystemReasons
        )
    }

    init(
        activeTransitionDelay: Duration,
        currentReasonsProvider: @escaping CurrentReasonsProvider
    ) {
        self.activeTransitionDelay = activeTransitionDelay
        self.currentReasonsProvider = currentReasonsProvider
    }

    public func start() {
        guard !isRunning else { return }
        isRunning = true

        let workspaceCenter = NSWorkspace.shared.notificationCenter
        observe(workspaceCenter, name: NSWorkspace.willSleepNotification) { monitor in
            monitor.record(.systemSleep, active: true)
        }
        observe(workspaceCenter, name: NSWorkspace.didWakeNotification) { monitor in
            monitor.record(.systemSleep, active: false)
        }
        observe(workspaceCenter, name: NSWorkspace.screensDidSleepNotification) { monitor in
            monitor.record(.screensAsleep, active: true)
        }
        observe(workspaceCenter, name: NSWorkspace.screensDidWakeNotification) { monitor in
            monitor.record(.screensAsleep, active: false)
        }
        observe(workspaceCenter, name: NSWorkspace.sessionDidResignActiveNotification) { monitor in
            monitor.record(.sessionInactive, active: true)
        }
        observe(workspaceCenter, name: NSWorkspace.sessionDidBecomeActiveNotification) { monitor in
            monitor.record(.sessionInactive, active: false)
        }

        let distributedCenter = DistributedNotificationCenter.default()
        observe(distributedCenter, name: Notification.Name("com.apple.screenIsLocked")) { monitor in
            monitor.record(.sessionInactive, active: true)
        }
        observe(distributedCenter, name: Notification.Name("com.apple.screenIsUnlocked")) { monitor in
            monitor.record(.sessionInactive, active: false)
        }

        activeReasons.formUnion(currentReasonsProvider())
        publishIfChanged(at: Date())
        if !activeReasons.isEmpty {
            scheduleCurrentReasonsRecheck()
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

        activeTransitionTask?.cancel()
        activeTransitionTask = nil
        currentReasonsRecheckTask?.cancel()
        currentReasonsRecheckTask = nil
        activeReasons.removeAll()
        isRunning = false
        state = State(isAway: false, reason: .active, timestamp: Date())
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

    func record(_ reason: Reason, active: Bool, at timestamp: Date = Date()) {
        guard reason != .active else { return }
        if active {
            activeTransitionTask?.cancel()
            activeTransitionTask = nil
            currentReasonsRecheckTask?.cancel()
            currentReasonsRecheckTask = nil
            activeReasons.insert(reason)
            publishIfChanged(at: timestamp)
        } else {
            activeReasons.remove(reason)
            if activeReasons.isEmpty {
                currentReasonsRecheckTask?.cancel()
                currentReasonsRecheckTask = nil
                scheduleActiveTransition()
            } else {
                publishIfChanged(at: timestamp)
            }
        }
    }

    func completePendingActiveTransition(at timestamp: Date = Date()) {
        activeTransitionTask?.cancel()
        activeTransitionTask = nil
        guard activeReasons.isEmpty else { return }

        activeReasons.formUnion(currentReasonsProvider())
        publishIfChanged(at: timestamp)
        if !activeReasons.isEmpty {
            scheduleCurrentReasonsRecheck()
        }
    }

    func recheckCurrentReasons(at timestamp: Date = Date()) {
        currentReasonsRecheckTask?.cancel()
        currentReasonsRecheckTask = nil
        activeReasons = currentReasonsProvider()
        publishIfChanged(at: timestamp)
    }

    private func scheduleActiveTransition() {
        activeTransitionTask?.cancel()
        activeTransitionTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: self?.activeTransitionDelay ?? .zero)
            } catch {
                return
            }
            guard let self, self.isRunning else { return }
            self.activeTransitionTask = nil
            self.completePendingActiveTransition()
        }
    }

    private func scheduleCurrentReasonsRecheck() {
        currentReasonsRecheckTask?.cancel()
        currentReasonsRecheckTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: self?.activeTransitionDelay ?? .zero)
            } catch {
                return
            }
            guard let self, self.isRunning else { return }
            self.currentReasonsRecheckTask = nil
            self.recheckCurrentReasons()
        }
    }

    private func publishIfChanged(at timestamp: Date) {
        let reason = primaryReason
        let isAway = reason != .active
        guard state.isAway != isAway || state.reason != reason else { return }

        state = State(isAway: isAway, reason: reason, timestamp: timestamp)
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

    private static func currentSystemReasons() -> Set<Reason> {
        var reasons: Set<Reason> = []
        if CGDisplayIsAsleep(CGMainDisplayID()) != 0 {
            reasons.insert(.screensAsleep)
        }
        if isCurrentSessionInactive {
            reasons.insert(.sessionInactive)
        }
        return reasons
    }

    private static var isCurrentSessionInactive: Bool {
        guard let session = CGSessionCopyCurrentDictionary() as? [String: Any] else {
            return false
        }
        let isLocked = session["CGSSessionScreenIsLocked"] as? Bool ?? false
        let isOnConsole = session["kCGSSessionOnConsoleKey"] as? Bool ?? true
        return isLocked || !isOnConsole
    }

}
