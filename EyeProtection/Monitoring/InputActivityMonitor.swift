import CoreGraphics
import Foundation

public enum InputActivityMonitorError: LocalizedError {
    case permissionRequired
    case eventTapCreationFailed
    case runLoopSourceCreationFailed

    public var errorDescription: String? {
        switch self {
        case .permissionRequired:
            "需要开启输入监控权限。"
        case .eventTapCreationFailed:
            "无法创建只读输入事件监听。"
        case .runLoopSourceCreationFailed:
            "无法启动输入事件监听。"
        }
    }
}

/// Reports only an input category and timestamp. Key values, characters and
/// pointer coordinates never leave this monitor.
@MainActor
public final class InputActivityMonitor {
    public enum ActivityKind: String, Sendable {
        case keyboard
        case pointerButton
        case pointerMovement
        case scrolling
    }

    public struct Event: Equatable, Sendable {
        public let kind: ActivityKind
        public let timestamp: Date

        public init(kind: ActivityKind, timestamp: Date) {
            self.kind = kind
            self.timestamp = timestamp
        }
    }

    public typealias ActivityHandler = @MainActor @Sendable (Event) -> Void
    public typealias PermissionHandler = @MainActor @Sendable (PermissionAuthorization) -> Void

    public var onActivity: ActivityHandler?
    public var onPermissionChange: PermissionHandler?

    public private(set) var isRunning = false

    private let pointerMovementThreshold: CGFloat
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var lastPointerLocation: CGPoint?
    private var accumulatedPointerTravel: CGFloat = 0

    public init(pointerMovementThreshold: CGFloat = 30) {
        self.pointerMovementThreshold = max(1, pointerMovementThreshold)
    }

    public static var permission: PermissionAuthorization {
        CGPreflightListenEventAccess() ? .authorized : .notAuthorized
    }

    /// WindowServer's time since any keyboard, pointer or scrolling event. No key
    /// values or pointer coordinates are read or retained.
    public static var systemIdleDuration: TimeInterval? {
        guard let anyInputEvent = CGEventType(rawValue: UInt32.max) else {
            return nil
        }
        let duration = CGEventSource.secondsSinceLastEventType(
            .combinedSessionState,
            eventType: anyInputEvent
        )
        guard duration.isFinite, duration >= 0 else { return nil }
        return duration
    }

    @discardableResult
    public static func requestPermission() -> Bool {
        CGRequestListenEventAccess()
    }

    @discardableResult
    public func refreshPermission() -> PermissionAuthorization {
        let permission = Self.permission
        onPermissionChange?(permission)
        return permission
    }

    @discardableResult
    public func requestPermission() -> Bool {
        let granted = Self.requestPermission()
        _ = refreshPermission()
        return granted
    }

    public func start() throws {
        guard !isRunning else { return }
        guard Self.permission == .authorized else {
            throw InputActivityMonitorError.permissionRequired
        }

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: Self.eventMask,
            callback: Self.eventTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            throw InputActivityMonitorError.eventTapCreationFailed
        }

        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            CFMachPortInvalidate(tap)
            throw InputActivityMonitorError.runLoopSourceCreationFailed
        }

        eventTap = tap
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        isRunning = true
    }

    public func stop() {
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            CFRunLoopSourceInvalidate(source)
        }
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }

        eventTap = nil
        runLoopSource = nil
        lastPointerLocation = nil
        accumulatedPointerTravel = 0
        isRunning = false
    }

    private func receive(
        type: CGEventType,
        isAutoRepeat: Bool,
        pointerLocation: CGPoint?,
        timestamp: Date
    ) {
        switch type {
        case .keyDown:
            // Ignore key repeat so holding a key cannot manufacture activity.
            guard !isAutoRepeat else { return }
            emit(.keyboard, at: timestamp)

        case .flagsChanged:
            emit(.keyboard, at: timestamp)

        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            emit(.pointerButton, at: timestamp)

        case .scrollWheel:
            emit(.scrolling, at: timestamp)

        case .mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged:
            if let pointerLocation {
                receivePointerLocation(pointerLocation, at: timestamp)
            }

        default:
            break
        }
    }

    private func receivePointerLocation(_ location: CGPoint, at timestamp: Date) {
        defer { lastPointerLocation = location }
        guard let previous = lastPointerLocation else { return }

        accumulatedPointerTravel += hypot(location.x - previous.x, location.y - previous.y)
        guard accumulatedPointerTravel >= pointerMovementThreshold else { return }

        accumulatedPointerTravel.formTruncatingRemainder(dividingBy: pointerMovementThreshold)
        emit(.pointerMovement, at: timestamp)
    }

    private func emit(_ kind: ActivityKind, at timestamp: Date) {
        onActivity?(Event(kind: kind, timestamp: timestamp))
    }

    private func recoverDisabledTap() {
        guard let eventTap else { return }
        CGEvent.tapEnable(tap: eventTap, enable: true)
    }

    private static let eventMask: CGEventMask = [
        CGEventType.keyDown,
        .flagsChanged,
        .leftMouseDown,
        .rightMouseDown,
        .otherMouseDown,
        .mouseMoved,
        .leftMouseDragged,
        .rightMouseDragged,
        .otherMouseDragged,
        .scrollWheel
    ].reduce(0) { mask, type in
        mask | (CGEventMask(1) << type.rawValue)
    }

    private static let eventTapCallback: CGEventTapCallBack = { _, type, event, userInfo in
        guard let userInfo else { return Unmanaged.passUnretained(event) }
        let monitor = Unmanaged<InputActivityMonitor>.fromOpaque(userInfo).takeUnretainedValue()

        // Extract only primitive values while the borrowed CGEvent is valid. Passing
        // the Core Graphics object into an actor-isolated closure is neither needed
        // nor accepted by Swift 6's strict concurrency checks.
        let isAutoRepeat = type == .keyDown &&
            event.getIntegerValueField(.keyboardEventAutorepeat) != 0
        let pointerLocation: CGPoint? = switch type {
        case .mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged:
            event.location
        default:
            nil
        }
        let timestamp = Date()

        // The tap source is installed on the main run loop, so its callback is
        // guaranteed to execute on the same executor as this monitor.
        MainActor.assumeIsolated {
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                monitor.recoverDisabledTap()
            } else {
                monitor.receive(
                    type: type,
                    isAutoRepeat: isAutoRepeat,
                    pointerLocation: pointerLocation,
                    timestamp: timestamp
                )
            }
        }

        return Unmanaged.passUnretained(event)
    }

}
