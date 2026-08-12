import CoreGraphics
import Foundation

/// Privacy-sensitive capabilities used by the activity monitors.
public enum MonitoringPermission: String, CaseIterable, Sendable {
    case inputMonitoring
}

/// Core Graphics does not expose a reliable distinction between "not requested"
/// and "denied", so callers should present both as requiring user action.
public enum PermissionAuthorization: String, Sendable {
    case authorized
    case notAuthorized
}

public struct PermissionState: Equatable, Sendable {
    public var inputMonitoring: PermissionAuthorization

    public init(inputMonitoring: PermissionAuthorization) {
        self.inputMonitoring = inputMonitoring
    }

    public subscript(permission: MonitoringPermission) -> PermissionAuthorization {
        switch permission {
        case .inputMonitoring:
            inputMonitoring
        }
    }

    public static var current: PermissionState {
        PermissionState(
            inputMonitoring: CGPreflightListenEventAccess() ? .authorized : .notAuthorized
        )
    }
}

/// Centralizes permission checks so UI and monitors report the same state.
@MainActor
public final class PermissionCenter {
    public typealias ChangeHandler = @MainActor @Sendable (PermissionState) -> Void

    public private(set) var state: PermissionState
    public var onChange: ChangeHandler?

    private var pollingTimer: Timer?

    public init() {
        state = .current
    }

    @discardableResult
    public func refresh() -> PermissionState {
        let newState = PermissionState.current
        guard newState != state else { return state }

        state = newState
        onChange?(newState)
        return newState
    }

    public func authorization(for permission: MonitoringPermission) -> PermissionAuthorization {
        refresh()[permission]
    }

    /// Requests the selected permission and immediately refreshes the observable state.
    /// macOS may still require the app to be restarted before a newly granted permission works.
    @discardableResult
    public func request(_ permission: MonitoringPermission) -> Bool {
        let granted: Bool
        switch permission {
        case .inputMonitoring:
            granted = CGRequestListenEventAccess()
        }

        _ = refresh()
        return granted
    }

    @discardableResult
    public func requestInputMonitoring() -> Bool {
        request(.inputMonitoring)
    }

    /// Polling is useful because System Settings can change permissions while the app is open.
    public func startObserving(interval: TimeInterval = 2) {
        stopObserving()

        let interval = max(0.5, interval)
        pollingTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refresh()
            }
        }
    }

    public func stopObserving() {
        pollingTimer?.invalidate()
        pollingTimer = nil
    }

}
