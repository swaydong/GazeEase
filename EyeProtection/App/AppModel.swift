import AppKit
import Combine
import Foundation
import OSLog

enum AnalyticsRefreshPolicy {
    static func shouldRefresh(
        lastRefreshAt: Date?,
        now: Date,
        maxAge: TimeInterval,
        calendar: Calendar = .current
    ) -> Bool {
        guard let lastRefreshAt else { return true }
        guard calendar.isDate(lastRefreshAt, inSameDayAs: now) else {
            return true
        }
        let age = now.timeIntervalSince(lastRefreshAt)
        return age < 0 || age >= max(0, maxAge)
    }
}

enum AnalyticsSamplingPolicy {
    static let persistenceInterval: TimeInterval = 5 * 60

    static func shouldFlush(
        lastFlushAt: Date?,
        now: Date,
        force: Bool,
        interval: TimeInterval = persistenceInterval
    ) -> Bool {
        if force { return true }
        guard let lastFlushAt else { return true }
        let elapsed = now.timeIntervalSince(lastFlushAt)
        return elapsed < 0 || elapsed >= max(0, interval)
    }

    static func shouldCommitUsageSessionEnd(tailFlushSucceeded: Bool) -> Bool {
        tailFlushSucceeded
    }
}

enum AppModelPublicationPolicy {
    static func shouldPublishFatigue(current: Double, updated: Double) -> Bool {
        let normalizedCurrent = current.isFinite ? max(0, current) : 0
        let normalizedUpdated = updated.isFinite ? max(0, updated) : 0
        if normalizedUpdated == 0, normalizedCurrent != 0 {
            return true
        }
        return fatigueBucket(current) != fatigueBucket(updated)
    }

    static func shouldPublishDuration(
        current: TimeInterval,
        updated: TimeInterval
    ) -> Bool {
        let normalizedCurrent = current.isFinite ? max(0, current) : 0
        let normalizedUpdated = updated.isFinite ? max(0, updated) : 0
        if normalizedUpdated == 0, normalizedCurrent != 0 {
            return true
        }
        return durationBucket(current) != durationBucket(updated)
    }

    private enum FatigueBucket: Equatable {
        case percent(Int)
        case compactTenth(Int)
    }

    private static func fatigueBucket(_ fatigue: Double) -> FatigueBucket {
        let value = fatigue.isFinite ? max(0, fatigue) : 0
        if value <= 999 {
            let displayedValue = value < 100 ? value.rounded(.down) : value.rounded()
            return .percent(Int(displayedValue))
        }
        return .compactTenth(Int((value / 100).rounded()))
    }

    private static func durationBucket(_ duration: TimeInterval) -> Int {
        let seconds = duration.isFinite ? max(0, Int(duration.rounded())) : 0
        return seconds < 60 ? seconds : 60 + seconds / 60
    }
}

enum RestRuntimePolicy {
    static func restoredPromptState(from runtime: PersistedRuntimeState?) -> ReminderPromptState {
        guard let runtime, runtime.restRequired, runtime.fatigue >= 100 else {
            return .hidden
        }
        if runtime.activeRest != nil {
            return .manualRetry
        }
        if runtime.reminderPromptState == nil,
           runtime.reminderDecisionPending == nil {
            return .initialDecision
        }
        let restored = ReminderPromptState.restored(
            savedState: runtime.reminderPromptState,
            legacyDecisionPending: runtime.reminderDecisionPending
        )
        return restored
    }

    static func shouldIgnoreInput(systemAway: Bool) -> Bool {
        systemAway
    }

    static func shouldInterruptForUnavailableMonitoring(
        activeRestTrigger: RestTrigger?,
        inputPermissionGranted: Bool,
        inputMonitorRunning: Bool
    ) -> Bool {
        activeRestTrigger == .manual &&
            (!inputPermissionGranted || !inputMonitorRunning)
    }

    static func promptStateAfterInterruptedSystemRest(
        restRequired: Bool
    ) -> ReminderPromptState {
        restRequired ? .manualRetry : .hidden
    }

    static func interruptedAttemptForRecovery(
        from runtime: PersistedRuntimeState?
    ) -> RestAttempt? {
        guard let runtime, let activeRest = runtime.activeRest else { return nil }
        let duration = activeRest.elapsed.isFinite ? max(0, activeRest.elapsed) : 0
        let endFatigue = runtime.fatigue.isFinite ? max(0, runtime.fatigue) : 0
        return RestAttempt(
            id: activeRest.id,
            trigger: activeRest.trigger,
            startedAt: activeRest.startedAt,
            endedAt: activeRest.startedAt.addingTimeInterval(duration),
            startFatiguePercent: activeRest.startFatiguePercent,
            duration: duration,
            endFatiguePercent: endFatigue,
            outcome: .interrupted(.cancelled)
        )
    }
}

enum RestAttemptOutboxPolicy {
    static func normalized(_ attempts: [PendingRestAttempt]) -> [PendingRestAttempt] {
        var seen = Set<UUID>()
        return attempts.filter { seen.insert($0.id).inserted }
    }

    @discardableResult
    static func enqueue(
        _ pendingAttempt: PendingRestAttempt,
        into attempts: inout [PendingRestAttempt]
    ) -> Bool {
        guard !attempts.contains(where: { $0.id == pendingAttempt.id }) else {
            return false
        }
        attempts.append(pendingAttempt)
        return true
    }

    static func discardAll(_ attempts: inout [PendingRestAttempt]) {
        attempts.removeAll(keepingCapacity: false)
    }

    @discardableResult
    static func drain(
        _ attempts: inout [PendingRestAttempt],
        persist: (PendingRestAttempt) -> Bool
    ) -> Bool {
        var removedAttempt = false
        while let pendingAttempt = attempts.first,
              persist(pendingAttempt) {
            attempts.removeFirst()
            removedAttempt = true
        }
        return removedAttempt
    }
}

@MainActor
final class AppModel: ObservableObject {
    private static var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    static let shared = AppModel()

    @Published private(set) var fatigue: Double
    /// Current reminder eligibility; the engine retains the unfinished episode for analytics.
    @Published private(set) var restRequired: Bool
    @Published private(set) var isResting: Bool
    @Published private(set) var restProgress: Double
    @Published private(set) var overloadDuration: TimeInterval
    @Published private(set) var presenceDescription: String
    @Published private(set) var appLanguage: AppLanguage
    @Published private(set) var onboardingCompleted: Bool
    @Published private(set) var isMonitoringComplete: Bool
    @Published private(set) var inputPermissionGranted: Bool
    @Published private(set) var launchAtLogin: Bool
    @Published private(set) var workMinutes: Int
    @Published private(set) var restSeconds: Int
    @Published private(set) var inactivityRestEnabled: Bool
    @Published private(set) var inactivityRestMinutes: Int
    @Published private(set) var reminderPromptState: ReminderPromptState
    @Published private(set) var notificationPermissionDenied: Bool
    @Published private(set) var randomThemeRotationEnabled: Bool
    @Published private(set) var randomThemeRotationIntervalMinutes: Int
    @Published private(set) var reminderTheme: ReminderTheme {
        didSet {
            Preferences.reminderTheme = reminderTheme
        }
    }
    @Published private(set) var analytics: AnalyticsSnapshot = .empty

    @Published var reminderMode: ReminderMode {
        didSet {
            Preferences.reminderMode = reminderMode
            guard isStarted else { return }
            handleReminderModeChange()
        }
    }

    var fatigueDisplay: String {
        FatigueValueFormatter.display(fatigue)
    }

    var menuBarText: String {
        fatigueDisplay
    }

    var resolvedLanguage: AppLanguage {
        appLanguage.resolved()
    }

    private var shouldPresentOnboarding: Bool {
        !onboardingCompleted && !Self.isRunningTests
    }

    var restSecondsRemaining: TimeInterval {
        guard isResting else { return 0 }
        return fatigueEngine.restRemaining
    }

    var activeRestTrigger: RestTrigger? {
        fatigueEngine.snapshot.activeRest?.trigger
    }

    private static let logger = Logger(subsystem: "com.local.EyeProtection", category: "AppModel")

    private let eventStore: EventStore
    private let inputMonitor: InputActivityMonitor
    private let systemMonitor: SystemPresenceMonitor
    private let permissionCenter: PermissionCenter
    private let notificationService: ReminderNotificationService

    private var fatigueEngine: FatigueEngine
    private var presenceEngine = PresenceEngine()
    private var continuousUsageDuration: TimeInterval
    private var activeOverloadEpisodeID: UUID?
    private var lastInactivityRestCompletedAt: Date?
    private var fatigueReminderMilestones: FatigueReminderMilestones
    private var reminderThemeRotationScheduler: ReminderThemeRotationScheduler
    private var lastPresenceState: PresenceState?
    private var pendingInput = false
    private var systemPresenceState = SystemPresenceMonitor.State(
        isAway: false,
        reason: .active,
        timestamp: Date()
    )
    private var lastTickAt: Date?
    private var lastPersistenceAt: Date?
    private var lastAnalyticsSampleFlushAt: Date?
    private var lastAnalyticsRefreshAt: Date?
    private var restInputGraceUntil: Date?
    private var ticker: Timer?
    private var analyticsMaintenanceTask: Task<Void, Never>?
    private var isStarted = false
    private var nextInputMonitorRetryAt = Date.distantPast
    private var inputMonitorRetryDelay: TimeInterval = 2
    private var nativeReminderDeliveryInFlight = false
    private var nativeReminderGeneration = UUID()
    private var nativeReminderDeliveryMultiple: Int?
    private var pendingNativeReminderMultiple: Int?
    private var shouldDelayThemeRotationForSurfaceRetirement = false
    private var themeRotationSurfaceRetirementTask: Task<Void, Never>?
    private var pendingRestAttempts: [PendingRestAttempt]

    private lazy var overduePanelController = OverduePanelController(model: self)
    private lazy var restOverlayController = RestOverlayController(model: self)
    private lazy var onboardingWindowController = OnboardingWindowController(model: self)

    private init() {
        let store: EventStore
        if Self.isRunningTests,
           let testDefaults = UserDefaults(
               suiteName: "com.local.EyeProtection.tests.\(ProcessInfo.processInfo.processIdentifier)"
           ),
           let inMemoryStore = try? EventStore(inMemory: true, defaults: testDefaults) {
            store = inMemoryStore
        } else {
            store = EventStore.makeDefault()
        }
        var runtime = store.loadRuntimeState()
        let restoredPendingAttempts = runtime?.pendingRestAttempts ?? []
        var pendingRestAttempts = RestAttemptOutboxPolicy.normalized(
            restoredPendingAttempts
        )
        var runtimeNeedsSave = pendingRestAttempts.count != restoredPendingAttempts.count
        let interruptedAttempt = RestRuntimePolicy.interruptedAttemptForRecovery(
            from: runtime
        )
        var pendingAttemptsAreDurable = true
        if let interruptedAttempt {
            RestAttemptOutboxPolicy.enqueue(
                PendingRestAttempt(
                    attempt: interruptedAttempt,
                    overloadEpisodeID: runtime?.overloadEpisodeID
                ),
                into: &pendingRestAttempts
            )
            if var normalizedRuntime = runtime {
                normalizedRuntime.activeRest = nil
                normalizedRuntime.reminderPromptState = normalizedRuntime.restRequired &&
                    normalizedRuntime.fatigue >= 100
                    ? .manualRetry
                    : .hidden
                normalizedRuntime.reminderDecisionPending =
                    normalizedRuntime.reminderPromptState != .hidden
                normalizedRuntime.pendingRestAttempts = pendingRestAttempts
                normalizedRuntime.savedAt = Date()
                pendingAttemptsAreDurable = store.saveRuntimeState(normalizedRuntime)
                runtime = normalizedRuntime
                runtimeNeedsSave = false
            }
        }
        let persistedPendingAttempts = pendingAttemptsAreDurable
            ? RestAttemptOutboxPolicy.drain(
                &pendingRestAttempts
            ) { pendingAttempt in
                Self.persist(pendingAttempt, to: store)
            }
            : false
        if (runtimeNeedsSave || persistedPendingAttempts), var normalizedRuntime = runtime {
            normalizedRuntime.pendingRestAttempts = pendingRestAttempts
            normalizedRuntime.savedAt = Date()
            store.saveRuntimeState(normalizedRuntime)
            runtime = normalizedRuntime
        }
        let configuredWorkMinutes = Preferences.workMinutes
        let configuredRestSeconds = Preferences.restSeconds
        let configuredInactivityRestEnabled = Preferences.inactivityRestEnabled
        let configuredInactivityRestMinutes = Preferences.inactivityRestMinutes
        let configuredRandomThemeRotationEnabled = Preferences.randomThemeRotationEnabled
        let configuredRandomThemeRotationIntervalMinutes =
            Preferences.randomThemeRotationIntervalMinutes
        let configuredAppLanguage = Preferences.appLanguage
        let overloadID = runtime?.overloadEpisodeID
        let overloadEpisode: OverloadEpisode?
        if let startedAt = runtime?.overloadStartedAt, runtime?.restRequired == true {
            overloadEpisode = OverloadEpisode(
                id: overloadID ?? UUID(),
                startedAt: startedAt,
                peakFatiguePercent: max(100, runtime?.fatigue ?? 100)
            )
        } else {
            overloadEpisode = nil
        }

        let restoredSnapshot = FatigueSnapshot(
            fatiguePercent: runtime?.fatigue ?? 0,
            restRequired: runtime?.restRequired ?? false,
            overloadStartedAt: runtime?.overloadStartedAt,
            activeRest: nil,
            activeOverloadEpisode: overloadEpisode
        )

        self.eventStore = store
        self.inputMonitor = InputActivityMonitor()
        self.systemMonitor = SystemPresenceMonitor()
        self.permissionCenter = PermissionCenter()
        self.notificationService = ReminderNotificationService.shared
        self.fatigueEngine = FatigueEngine(
            snapshot: restoredSnapshot,
            usageDurationForOneHundredPercent: TimeInterval(configuredWorkMinutes * 60),
            requiredContinuousRestDuration: TimeInterval(configuredRestSeconds)
        )
        self.continuousUsageDuration = runtime?.continuousUsageDuration ?? 0
        self.activeOverloadEpisodeID = overloadEpisode?.id
        self.lastInactivityRestCompletedAt = runtime?.lastInactivityRestCompletedAt
        self.fatigueReminderMilestones = FatigueReminderMilestones(
            restoredLastReminderMultiple: runtime?.lastReminderMultiple,
            restRequired: restoredSnapshot.restRequired,
            fatigue: restoredSnapshot.fatiguePercent
        )
        self.reminderThemeRotationScheduler = ReminderThemeRotationScheduler(
            nextChangeAt: Preferences.randomThemeRotationNextChangeAt,
            pendingTheme: Preferences.randomThemeRotationPendingTheme
        )
        self.fatigue = restoredSnapshot.fatiguePercent
        self.restRequired = restoredSnapshot.needsRestReminder
        self.isResting = false
        self.restProgress = 0
        self.overloadDuration = restoredSnapshot.overloadStartedAt.map {
            max(0, Date().timeIntervalSince($0))
        } ?? 0
        self.presenceDescription = AppLocalization.string(
            L10nKey.presenceWaitingForFirstInput,
            language: configuredAppLanguage.resolved()
        )
        self.appLanguage = configuredAppLanguage
        self.onboardingCompleted = Preferences.onboardingCompleted
        self.isMonitoringComplete = false
        self.inputPermissionGranted = PermissionState.current.inputMonitoring == .authorized
        self.launchAtLogin = LaunchAtLoginService.isEnabled
        self.workMinutes = configuredWorkMinutes
        self.restSeconds = configuredRestSeconds
        self.inactivityRestEnabled = configuredInactivityRestEnabled
        self.inactivityRestMinutes = configuredInactivityRestMinutes
        self.reminderPromptState = RestRuntimePolicy.restoredPromptState(from: runtime)
        self.notificationPermissionDenied = false
        self.randomThemeRotationEnabled = configuredRandomThemeRotationEnabled
        self.randomThemeRotationIntervalMinutes = configuredRandomThemeRotationIntervalMinutes
        self.reminderTheme = Preferences.reminderTheme
        self.reminderMode = Preferences.reminderMode
        self.pendingRestAttempts = pendingRestAttempts

        if let episode = overloadEpisode, overloadID == nil {
            activeOverloadEpisodeID = store.beginOverload(
                at: episode.startedAt,
                fatigue: episode.peakFatiguePercent,
                id: episode.id
            )
        }
    }

    func start() {
        guard !isStarted else { return }
        isStarted = true

        notificationService.configure()
        configureCallbacks()
        permissionCenter.startObserving()
        systemMonitor.start()
        if eventStore.cleanExpiredData() {
            startAnalyticsMaintenancePump()
        }
        refreshAnalytics()

        _ = overduePanelController
        _ = restOverlayController
        _ = onboardingWindowController

        let now = Date()
        updateRandomThemeRotation(
            at: now,
            isResting: fatigueEngine.snapshot.isResting
        )
        lastTickAt = now
        lastPersistenceAt = now
        ticker = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.tick(at: Date())
            }
        }

        updatePermissions(permissionCenter.refresh())
        handleReminderModeChange()
        if shouldPresentOnboarding {
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(350))
                guard let self, self.isStarted, self.shouldPresentOnboarding else { return }
                self.onboardingWindowController.showIfNeeded()
            }
        }
    }

    func stop() {
        guard isStarted else { return }
        isStarted = false
        analyticsMaintenanceTask?.cancel()
        analyticsMaintenanceTask = nil
        cancelThemeRotationSurfaceRetirement()
        persist(at: Date(), force: true)
        ticker?.invalidate()
        ticker = nil
        inputMonitor.stop()
        systemMonitor.stop()
        permissionCenter.stopObserving()
        overduePanelController.hide()
        restOverlayController.hide()
        onboardingWindowController.close()
        cancelThemeRotationSurfaceRetirement()
    }

    func beginRest() {
        let now = Date()
        let events = fatigueEngine.beginRest(trigger: .manual, at: now)
        guard !events.isEmpty else { return }

        // The click that invoked this action may arrive at the event tap just after
        // the button handler. It must not immediately cancel the new rest.
        restInputGraceUntil = now.addingTimeInterval(0.75)
        lastTickAt = now
        process(events)
        publish(at: now)
        persist(at: now, force: true)
    }

    func continueWorking() {
        let now = Date()
        let events = fatigueEngine.recordContinueWorking(at: now)
        guard !events.isEmpty else { return }

        process(events)
        restOverlayController.hide()
        publish(at: now)
        persist(at: now, force: true)
    }

    func requestInputPermission() {
        let granted = permissionCenter.requestInputMonitoring()
        updatePermissions(permissionCenter.refresh())
        if !granted {
            openPrivacySettings(anchor: "Privacy_ListenEvent")
        }
    }

    func refreshMonitoringStatus() {
        nextInputMonitorRetryAt = .distantPast
        inputMonitorRetryDelay = 2
        updatePermissions(permissionCenter.refresh())
    }

    func repairInputMonitoring() {
        refreshMonitoringStatus()
        guard !isMonitoringComplete else { return }
        openInputMonitoringSettings()
    }

    func openNotificationSettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension"
        ) else { return }
        NSWorkspace.shared.open(url)
    }

    func setWorkMinutes(_ minutes: Int) {
        guard !fatigueEngine.isResting else { return }
        let normalized = Preferences.normalizedWorkMinutes(minutes)
        guard normalized != workMinutes else { return }
        let now = Date()
        flushAnalyticsSample(
            at: now,
            presenceState: presenceEngine.state,
            elapsed: lastPersistenceAt.map { max(0, now.timeIntervalSince($0)) } ?? 0
        )
        guard let events = fatigueEngine.updateDurations(
            usageDurationForOneHundredPercent: TimeInterval(normalized * 60),
            requiredContinuousRestDuration: TimeInterval(restSeconds),
            at: now
        ) else { return }

        workMinutes = normalized
        Preferences.workMinutes = normalized
        process(events)
        publish(at: now)
        persist(at: now, force: true)
        refreshAnalytics()
    }

    func setAppLanguage(_ language: AppLanguage) {
        guard appLanguage != language else {
            refreshPresenceDescription()
            return
        }
        appLanguage = language
        Preferences.appLanguage = language
        refreshPresenceDescription()
    }

    @discardableResult
    func completeOnboarding() -> Bool {
        guard inputPermissionGranted, isMonitoringComplete else { return false }
        if !onboardingCompleted {
            onboardingCompleted = true
            Preferences.onboardingCompleted = true
        }
        return true
    }

    func showOnboarding() {
        onboardingWindowController.show()
    }

    func openInputMonitoringSettings() {
        openPrivacySettings(anchor: "Privacy_ListenEvent")
    }

    func showTestReminderPreview() {
        guard canShowTestReminderPreview else { return }
        overduePanelController.showPreview()
    }

    var canShowTestReminderPreview: Bool {
        isMonitoringComplete &&
            !fatigueEngine.isResting &&
            !fatigueEngine.snapshot.needsRestReminder
    }

    func setRestSeconds(_ seconds: Int) {
        guard !fatigueEngine.isResting else { return }
        let normalized = Preferences.normalizedRestSeconds(seconds)
        guard fatigueEngine.updateDurations(
            usageDurationForOneHundredPercent: TimeInterval(workMinutes * 60),
            requiredContinuousRestDuration: TimeInterval(normalized),
            at: Date()
        ) != nil else { return }

        restSeconds = normalized
        Preferences.restSeconds = normalized
    }

    func setInactivityRestEnabled(_ enabled: Bool) {
        inactivityRestEnabled = enabled
        Preferences.inactivityRestEnabled = enabled
    }

    func setInactivityRestMinutes(_ minutes: Int) {
        let normalized = Preferences.normalizedInactivityRestMinutes(minutes)
        inactivityRestMinutes = normalized
        Preferences.inactivityRestMinutes = normalized
    }

    func setReminderTheme(_ theme: ReminderTheme) {
        guard reminderTheme != theme else { return }
        cancelThemeRotationSurfaceRetirement()
        if randomThemeRotationEnabled {
            reminderThemeRotationScheduler.configure(
                enabled: true,
                interval: randomThemeRotationInterval,
                at: Date()
            )
            persistRandomThemeRotationSchedule()
        }
        reminderTheme = theme
    }

    func setRandomThemeRotationEnabled(_ enabled: Bool) {
        guard randomThemeRotationEnabled != enabled else { return }
        cancelThemeRotationSurfaceRetirement()
        randomThemeRotationEnabled = enabled
        Preferences.randomThemeRotationEnabled = enabled
        reminderThemeRotationScheduler.configure(
            enabled: enabled,
            interval: randomThemeRotationInterval,
            at: Date()
        )
        persistRandomThemeRotationSchedule()
    }

    func setRandomThemeRotationIntervalMinutes(_ minutes: Int) {
        let normalized = Preferences.normalizedRandomThemeRotationIntervalMinutes(minutes)
        guard randomThemeRotationIntervalMinutes != normalized else { return }
        cancelThemeRotationSurfaceRetirement()
        randomThemeRotationIntervalMinutes = normalized
        Preferences.randomThemeRotationIntervalMinutes = normalized
        reminderThemeRotationScheduler.configure(
            enabled: randomThemeRotationEnabled,
            interval: randomThemeRotationInterval,
            at: Date()
        )
        persistRandomThemeRotationSchedule()
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            try LaunchAtLoginService.setEnabled(enabled)
            launchAtLogin = LaunchAtLoginService.isEnabled
        } catch {
            launchAtLogin = LaunchAtLoginService.isEnabled
            Self.logger.error("Unable to update login item: \(error.localizedDescription, privacy: .public)")
        }
    }

    func clearData() {
        guard eventStore.clearAll() else { return }
        RestAttemptOutboxPolicy.discardAll(&pendingRestAttempts)
        lastAnalyticsSampleFlushAt = nil
        persist(at: Date(), force: true)
        refreshAnalytics()
    }

    func refreshAnalytics() {
        refreshAnalytics(at: Date())
    }

    func refreshAnalytics(at now: Date) {
        analytics = eventStore.analytics(now: now)
        lastAnalyticsRefreshAt = now
    }

    func refreshAnalyticsIfNeeded(
        at now: Date = Date(),
        maxAge: TimeInterval = 60
    ) {
        guard AnalyticsRefreshPolicy.shouldRefresh(
            lastRefreshAt: lastAnalyticsRefreshAt,
            now: now,
            maxAge: maxAge
        ) else { return }
        refreshAnalytics(at: now)
    }

    func quit() {
        persist(at: Date(), force: true)
        NSApp.terminate(nil)
    }

    private func configureCallbacks() {
        inputMonitor.onActivity = { [weak self] event in
            self?.handleInput(event)
        }
        inputMonitor.onPermissionChange = { [weak self] _ in
            guard let self else { return }
            self.updatePermissions(self.permissionCenter.refresh())
        }

        systemMonitor.onChange = { [weak self] state in
            self?.handleSystemPresence(state)
        }
        permissionCenter.onChange = { [weak self] state in
            self?.updatePermissions(state)
        }
        notificationService.onOpen = { [weak self] episodeID in
            self?.handleNotificationOpen(episodeID: episodeID)
        }
    }

    private func handleInput(_ event: InputActivityMonitor.Event) {
        guard !RestRuntimePolicy.shouldIgnoreInput(
            systemAway: systemPresenceState.isAway
        ) else { return }

        pendingInput = true

        guard fatigueEngine.isResting else {
            return
        }

        guard event.timestamp >= (restInputGraceUntil ?? .distantPast) else { return }

        if monitoringPermissionsGranted {
            advanceRest(to: event.timestamp)
        }
        guard fatigueEngine.isResting else {
            publish(at: event.timestamp)
            return
        }

        let reason: RestInterruptionReason = switch event.kind {
        case .keyboard: .keyboard
        case .pointerButton: .click
        case .pointerMovement: .pointerMovement
        case .scrolling: .scroll
        }
        process(fatigueEngine.interruptRest(reason: reason, at: event.timestamp))
        publish(at: event.timestamp)
    }

    private func handleSystemPresence(_ state: SystemPresenceMonitor.State) {
        let wasAway = systemPresenceState.isAway

        if wasAway, !state.isAway {
            // Account for timer suspension while the Mac was asleep before ending rest.
            tick(at: state.timestamp, allowLongInterval: true)
            systemPresenceState = state

            if fatigueEngine.isResting {
                let events = fatigueEngine.interruptRest(
                    reason: .cancelled,
                    at: state.timestamp
                )
                reminderPromptState = RestRuntimePolicy.promptStateAfterInterruptedSystemRest(
                    restRequired: fatigueEngine.snapshot.needsRestReminder
                )
                process(events)
                publish(at: state.timestamp)
                persist(at: state.timestamp, force: true)
            }
            return
        }

        if !wasAway, state.isAway {
            // PresenceEngine must observe the away state before the final usage
            // sample is recorded, otherwise the previous session can remain open
            // until the Mac wakes again.
            systemPresenceState = state
            // End the active usage segment immediately instead of waiting for the
            // next timer sample after the screen has already locked or gone to sleep.
            tick(at: state.timestamp)
            let trigger: RestTrigger = switch state.reason {
            case .systemSleep: .systemSleep
            case .screensAsleep: .displayAsleep
            case .sessionInactive: .screenLocked
            case .active: .screenLocked
            }
            process(fatigueEngine.beginRest(trigger: trigger, at: state.timestamp))
            lastTickAt = state.timestamp
            restInputGraceUntil = nil
            publish(at: state.timestamp)
            persist(at: state.timestamp, force: true)
            return
        }

        systemPresenceState = state
    }

    private func tick(at now: Date, allowLongInterval: Bool = false) {
        guard isStarted else { return }
        let previousTick = lastTickAt ?? now
        var elapsed = max(0, now.timeIntervalSince(previousTick))
        if !allowLongInterval, !systemPresenceState.isAway {
            elapsed = min(elapsed, 2)
        }
        lastTickAt = now

        if inputPermissionGranted, !inputMonitor.isRunning {
            startInputMonitoringIfNeeded(at: now)
        }

        let runtimeStatus = MonitoringRuntimeStatus(
            inputMonitorRunning: inputMonitor.isRunning
        )
        let inputDetected = pendingInput
        let sample = PresenceSample(
            timestamp: now,
            inputDetected: inputDetected,
            authorization: runtimeStatus.authorization,
            systemState: domainSystemState
        )
        pendingInput = false
        let previousPresenceState = presenceEngine.state
        let presenceUpdate = presenceEngine.ingest(sample)
        var endedUsageSession = false
        for event in presenceUpdate.events {
            guard case let .sessionEnded(at, _) = event else { continue }
            let tailFlushSucceeded = flushAnalyticsSample(
                at: at,
                presenceState: previousPresenceState,
                elapsed: lastPersistenceAt.map { max(0, at.timeIntervalSince($0)) } ?? 0
            )
            if AnalyticsSamplingPolicy.shouldCommitUsageSessionEnd(
                tailFlushSucceeded: tailFlushSucceeded
            ) {
                eventStore.recordUsageSessionEnded(at: at)
            }
            continuousUsageDuration = 0
            endedUsageSession = true
        }
        var completedInactivityRest = false

        if fatigueEngine.isResting {
            if RestRuntimePolicy.shouldInterruptForUnavailableMonitoring(
                activeRestTrigger: fatigueEngine.snapshot.activeRest?.trigger,
                inputPermissionGranted: monitoringPermissionsGranted,
                inputMonitorRunning: inputMonitor.isRunning
            ) {
                process(fatigueEngine.interruptRest(reason: .monitoringUnavailable, at: now))
            } else {
                process(fatigueEngine.advanceRest(by: elapsed, endingAt: now))
            }
        } else {
            let idleDuration = inputDetected ? 0 : InputActivityMonitor.systemIdleDuration
            if InactivityRestPolicy.thresholdReached(
                enabled: inactivityRestEnabled,
                thresholdMinutes: inactivityRestMinutes,
                idleDuration: idleDuration,
                now: now,
                lastCompletedAt: lastInactivityRestCompletedAt,
                monitoringAvailable: runtimeStatus.isComplete,
                systemAway: systemPresenceState.isAway,
                isResting: false
            ) {
                let qualifyingDuration = TimeInterval(inactivityRestMinutes * 60)
                flushAnalyticsSample(
                    at: now,
                    presenceState: presenceUpdate.state,
                    elapsed: lastPersistenceAt.map { max(0, now.timeIntervalSince($0)) } ?? 0
                )
                process(fatigueEngine.completeConfirmedRest(
                    trigger: .inactivity,
                    qualifyingDuration: qualifyingDuration,
                    endingAt: now
                ))
                lastInactivityRestCompletedAt = now
                continuousUsageDuration = 0
                presenceEngine.resetAfterCompletedRest(at: now)
                completedInactivityRest = true
            } else if presenceUpdate.state.contributesToFatigue {
                continuousUsageDuration += elapsed
                process(fatigueEngine.accrueUsage(for: elapsed, endingAt: now))
            }
        }

        publish(at: now, presenceState: presenceEngine.state)
        persist(at: now, force: completedInactivityRest || endedUsageSession)
        if completedInactivityRest {
            refreshAnalytics()
        }
    }

    private func process(_ events: [FatigueEvent]) {
        var latestRestAttemptEnd: Date?
        for event in events {
            let previousPromptState = reminderPromptState
            let nextPromptState = previousPromptState.applying(event)
            if nextPromptState != previousPromptState {
                reminderPromptState = nextPromptState
                if nextPromptState == .hidden,
                   previousPromptState != .hidden {
                    shouldDelayThemeRotationForSurfaceRetirement = true
                }
            }

            switch event {
            case let .fatigueChanged(from, to, _):
                guard activeOverloadEpisodeID != nil else { break }
                let newMilestone = fatigueReminderMilestones.consumeNewMilestone(
                    from: from,
                    to: to
                )
                if to < 100 {
                    if from >= 100 {
                        clearQueuedNativeReminder()
                        notificationService.clearReminder()
                    }
                    break
                }
                guard let multiple = newMilestone else { break }

                if reminderPromptState == .hidden {
                    reminderPromptState = .initialDecision
                }
                if reminderMode == .systemNotification {
                    queueNativeReminderIfNeeded(for: multiple)
                    deliverNativeReminderIfNeeded()
                }

            case let .restRequired(episode):
                fatigueReminderMilestones.registerInitialReminder(
                    fatigue: episode.peakFatiguePercent
                )
                activeOverloadEpisodeID = eventStore.beginOverload(
                    at: episode.startedAt,
                    fatigue: episode.peakFatiguePercent,
                    id: episode.id
                )
                deliverNativeReminderIfNeeded()

            case let .restStarted(rest):
                clearQueuedNativeReminder()
                notificationService.clearReminder()
                if let id = activeOverloadEpisodeID {
                    eventStore.markOverloadResponse(
                        id: id,
                        kind: rest.trigger.rawValue,
                        at: rest.startedAt
                    )
                }

            case let .restInterrupted(attempt):
                record(attempt)
                latestRestAttemptEnd = max(
                    latestRestAttemptEnd ?? attempt.endedAt,
                    attempt.endedAt
                )
                if attempt.trigger != .manual,
                   reminderPromptState == .initialDecision {
                    deliverNativeReminderIfNeeded()
                }

            case let .restCompleted(attempt):
                record(attempt)
                latestRestAttemptEnd = max(
                    latestRestAttemptEnd ?? attempt.endedAt,
                    attempt.endedAt
                )
                fatigueReminderMilestones.reset()
                clearQueuedNativeReminder()
                notificationService.clearReminder()
                continuousUsageDuration = 0
                presenceEngine.resetAfterCompletedRest(at: attempt.endedAt)

            case let .overloadCompleted(episode):
                let id = activeOverloadEpisodeID ?? episode.id
                eventStore.completeOverload(id: id, at: episode.endedAt ?? Date())
                activeOverloadEpisodeID = nil
                fatigueReminderMilestones.reset()
                clearQueuedNativeReminder()
                notificationService.clearReminder()

            case let .continuedWorking(at):
                clearQueuedNativeReminder()
                notificationService.clearReminder()
                if let id = activeOverloadEpisodeID {
                    eventStore.markOverloadResponse(id: id, kind: "continued", at: at)
                }
            }
        }
        if let latestRestAttemptEnd {
            flushAnalyticsSample(
                at: latestRestAttemptEnd,
                presenceState: presenceEngine.state,
                elapsed: lastPersistenceAt.map {
                    max(0, latestRestAttemptEnd.timeIntervalSince($0))
                } ?? 0
            )
            persistRestAttemptOutbox(at: latestRestAttemptEnd)
        }
    }

    private func record(_ attempt: RestAttempt) {
        RestAttemptOutboxPolicy.enqueue(
            PendingRestAttempt(
                attempt: attempt,
                overloadEpisodeID: activeOverloadEpisodeID
            ),
            into: &pendingRestAttempts
        )
    }

    private func publish(at now: Date, presenceState: PresenceState? = nil) {
        let snapshot = fatigueEngine.snapshot
        if isResting, !snapshot.isResting {
            shouldDelayThemeRotationForSurfaceRetirement = true
        }
        if AppModelPublicationPolicy.shouldPublishFatigue(
            current: fatigue,
            updated: snapshot.fatiguePercent
        ) {
            fatigue = snapshot.fatiguePercent
        }
        updatePublished(\.restRequired, to: snapshot.needsRestReminder)
        updatePublished(\.isResting, to: snapshot.isResting)
        updatePublished(\.restProgress, to: fatigueEngine.restProgress)
        let updatedOverloadDuration = snapshot.overloadStartedAt.map {
            max(0, now.timeIntervalSince($0))
        } ?? 0
        if AppModelPublicationPolicy.shouldPublishDuration(
            current: overloadDuration,
            updated: updatedOverloadDuration
        ) {
            overloadDuration = updatedOverloadDuration
        }
        if let presenceState {
            lastPresenceState = presenceState
        }
        refreshPresenceDescription()
        updateMonitoringCompleteness()

        let shouldDeferTheme = snapshot.isResting || reminderPromptState != .hidden
        if shouldDelayThemeRotationForSurfaceRetirement, !shouldDeferTheme {
            shouldDelayThemeRotationForSurfaceRetirement = false
            if randomThemeRotationEnabled {
                scheduleRandomThemeRotationUpdateAfterSurfaceRetires()
                return
            }
        }
        guard themeRotationSurfaceRetirementTask == nil else {
            return
        }
        updateRandomThemeRotation(at: now, isResting: snapshot.isResting)
    }

    private var randomThemeRotationInterval: TimeInterval {
        TimeInterval(randomThemeRotationIntervalMinutes * 60)
    }

    private func scheduleRandomThemeRotationUpdateAfterSurfaceRetires() {
        themeRotationSurfaceRetirementTask?.cancel()
        themeRotationSurfaceRetirementTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(250))
            } catch {
                return
            }
            guard !Task.isCancelled, let self, self.isStarted else { return }
            self.themeRotationSurfaceRetirementTask = nil
            self.updateRandomThemeRotation(
                at: Date(),
                isResting: self.fatigueEngine.snapshot.isResting
            )
        }
    }

    private func cancelThemeRotationSurfaceRetirement() {
        themeRotationSurfaceRetirementTask?.cancel()
        themeRotationSurfaceRetirementTask = nil
        shouldDelayThemeRotationForSurfaceRetirement = false
    }

    private func updateRandomThemeRotation(at now: Date, isResting: Bool) {
        let previousSchedule = reminderThemeRotationScheduler
        let nextTheme = reminderThemeRotationScheduler.advance(
            enabled: randomThemeRotationEnabled,
            interval: randomThemeRotationInterval,
            at: now,
            currentTheme: reminderTheme,
            shouldDefer: isResting || reminderPromptState != .hidden,
            randomValue: UInt64.random(in: UInt64.min...UInt64.max)
        )
        if reminderThemeRotationScheduler != previousSchedule {
            persistRandomThemeRotationSchedule()
        }
        if let nextTheme, nextTheme != reminderTheme {
            reminderTheme = nextTheme
        }
    }

    private func persistRandomThemeRotationSchedule() {
        Preferences.randomThemeRotationNextChangeAt =
            reminderThemeRotationScheduler.nextChangeAt
        Preferences.randomThemeRotationPendingTheme =
            reminderThemeRotationScheduler.pendingTheme
    }

    private func startAnalyticsMaintenancePump() {
        analyticsMaintenanceTask?.cancel()
        analyticsMaintenanceTask = Task(priority: .utility) { @MainActor [weak self] in
            guard let self else { return }
            while self.isStarted, !Task.isCancelled {
                do {
                    try await Task.sleep(for: .milliseconds(50))
                } catch {
                    break
                }
                guard self.eventStore.cleanExpiredData() else { break }
                await Task.yield()
            }
            self.analyticsMaintenanceTask = nil
        }
    }

    private func persist(at now: Date, force: Bool = false) {
        if !force,
           let lastPersistenceAt,
           now >= lastPersistenceAt,
           now.timeIntervalSince(lastPersistenceAt) < 5 {
            return
        }
        let elapsed = lastPersistenceAt.map { max(0, now.timeIntervalSince($0)) } ?? 0
        lastPersistenceAt = now
        let runtimeSaved = saveRuntimeState(at: now)
        let persistedPendingAttempts = runtimeSaved && drainPendingRestAttempts()
        if persistedPendingAttempts {
            saveRuntimeState(at: now)
        }
        checkpointAnalyticsSample(
            at: now,
            presenceState: presenceEngine.state.rawValue,
            elapsed: elapsed,
            force: force
        )
        if persistedPendingAttempts {
            refreshAnalytics()
        }
    }

    @discardableResult
    private func checkpointAnalyticsSample(
        at now: Date,
        presenceState: String,
        elapsed: TimeInterval,
        force: Bool
    ) -> Bool {
        let snapshot = fatigueEngine.snapshot
        eventStore.stageSample(
            at: now,
            fatigue: snapshot.fatiguePercent,
            presenceState: presenceState,
            elapsed: elapsed,
            continuousUsageDuration: continuousUsageDuration
        )
        guard AnalyticsSamplingPolicy.shouldFlush(
            lastFlushAt: lastAnalyticsSampleFlushAt,
            now: now,
            force: force
        ) else { return true }
        if let id = activeOverloadEpisodeID {
            eventStore.updateOverload(
                id: id,
                peakFatigue: snapshot.fatiguePercent,
                save: false
            )
        }
        let flushSucceeded = eventStore.flushStagedSamples()
        if flushSucceeded {
            lastAnalyticsSampleFlushAt = now
        }
        return flushSucceeded
    }

    @discardableResult
    private func flushAnalyticsSample(
        at now: Date,
        presenceState: PresenceState,
        elapsed: TimeInterval
    ) -> Bool {
        checkpointAnalyticsSample(
            at: now,
            presenceState: presenceState.rawValue,
            elapsed: elapsed,
            force: true
        )
    }

    @discardableResult
    private func saveRuntimeState(at now: Date) -> Bool {
        let snapshot = fatigueEngine.snapshot
        return eventStore.saveRuntimeState(PersistedRuntimeState(
            fatigue: snapshot.fatiguePercent,
            restRequired: snapshot.restRequired,
            overloadStartedAt: snapshot.overloadStartedAt,
            overloadEpisodeID: activeOverloadEpisodeID,
            continuousUsageDuration: continuousUsageDuration,
            activeRest: snapshot.activeRest,
            pendingRestAttempts: pendingRestAttempts,
            reminderPromptState: reminderPromptState,
            reminderDecisionPending: reminderPromptState != .hidden,
            lastInactivityRestCompletedAt: lastInactivityRestCompletedAt,
            lastReminderMultiple: fatigueReminderMilestones.lastReminderMultiple,
            savedAt: now
        ))
    }

    private func persistRestAttemptOutbox(at now: Date) {
        guard saveRuntimeState(at: now) else { return }
        guard drainPendingRestAttempts() else { return }
        saveRuntimeState(at: now)
        refreshAnalytics()
    }

    private func drainPendingRestAttempts() -> Bool {
        RestAttemptOutboxPolicy.drain(&pendingRestAttempts) { [eventStore] pendingAttempt in
            Self.persist(pendingAttempt, to: eventStore)
        }
    }

    private static func persist(
        _ pendingAttempt: PendingRestAttempt,
        to store: EventStore
    ) -> Bool {
        let attempt = pendingAttempt.attempt
        let outcome: String
        let reason: String?
        switch attempt.outcome {
        case .completed:
            outcome = "completed"
            reason = nil
        case let .interrupted(interruption):
            outcome = "interrupted"
            reason = interruption.rawValue
        }
        return store.recordRestAttempt(
            id: attempt.id,
            overloadEpisodeID: pendingAttempt.overloadEpisodeID,
            startedAt: attempt.startedAt,
            endedAt: attempt.endedAt,
            startFatigue: attempt.startFatiguePercent,
            endFatigue: attempt.endFatiguePercent,
            source: attempt.trigger.rawValue,
            outcome: outcome,
            interruptionReason: reason
        )
    }

    private func updatePermissions(_ state: PermissionState) {
        updatePublished(
            \.inputPermissionGranted,
            to: state.inputMonitoring == .authorized
        )

        if inputPermissionGranted {
            startInputMonitoringIfNeeded()
        } else {
            inputMonitor.stop()
            nextInputMonitorRetryAt = .distantPast
            inputMonitorRetryDelay = 2
        }
        updateMonitoringCompleteness()
    }

    private func startInputMonitoringIfNeeded(at now: Date = Date()) {
        guard !inputMonitor.isRunning,
              now >= nextInputMonitorRetryAt else { return }
        do {
            try inputMonitor.start()
            inputMonitorRetryDelay = 2
            nextInputMonitorRetryAt = .distantPast
        } catch {
            Self.logger.error("Input monitor failed: \(error.localizedDescription, privacy: .public)")
            nextInputMonitorRetryAt = now.addingTimeInterval(inputMonitorRetryDelay)
            inputMonitorRetryDelay = min(inputMonitorRetryDelay * 2, 60)
        }
    }

    private func updateMonitoringCompleteness() {
        let status = MonitoringRuntimeStatus(
            inputMonitorRunning: inputMonitor.isRunning
        )
        updatePublished(\.isMonitoringComplete, to: status.isComplete)
    }

    private func handleReminderModeChange() {
        clearQueuedNativeReminder()
        notificationService.clearReminder()
        guard reminderMode == .systemNotification else { return }

        if reminderPromptState == .initialDecision {
            deliverNativeReminderIfNeeded()
            return
        }

        Task { @MainActor [weak self] in
            guard let self else { return }
            let authorized = await notificationService.ensureAuthorization()
            guard isStarted, reminderMode == .systemNotification else { return }
            notificationPermissionDenied = !authorized
            if !authorized {
                reminderMode = .topPanel
            }
        }
    }

    private func deliverNativeReminderIfNeeded() {
        let snapshot = fatigueEngine.snapshot
        guard isStarted,
              reminderMode == .systemNotification,
              reminderPromptState == .initialDecision,
              snapshot.needsRestReminder,
              !snapshot.isResting,
              let episodeID = activeOverloadEpisodeID else { return }

        let deliveryMultiple = max(1, fatigueReminderMilestones.lastReminderMultiple)
        if nativeReminderDeliveryInFlight {
            queueNativeReminderIfNeeded(for: deliveryMultiple)
            return
        }

        nativeReminderDeliveryInFlight = true
        nativeReminderDeliveryMultiple = deliveryMultiple
        let deliveryGeneration = nativeReminderGeneration
        let display = FatigueValueFormatter.display(snapshot.fatiguePercent)
        Task { @MainActor [weak self] in
            guard let self else { return }
            let result = await notificationService.deliver(
                fatigueDisplay: display,
                episodeID: episodeID,
                reminderMultiple: deliveryMultiple,
                language: resolvedLanguage,
                isStillRelevant: { [weak self] in
                    guard let self else { return false }
                    // A successful submission consumes the prompt before the banner
                    // may appear. Recovery or dismissal invalidates the generation.
                    return self.isStarted &&
                        self.nativeReminderGeneration == deliveryGeneration &&
                        self.reminderMode == .systemNotification &&
                        self.fatigueEngine.snapshot.needsRestReminder &&
                        !self.fatigueEngine.isResting &&
                        self.activeOverloadEpisodeID == episodeID
                }
            )
            nativeReminderDeliveryInFlight = false
            nativeReminderDeliveryMultiple = nil

            if deliveryGeneration != nativeReminderGeneration {
                // A partial recovery can re-arm 100% while an older notification
                // is awaiting authorization. Retry from the current cycle, even
                // when its milestone is lower than the stale request's milestone.
                notificationService.clearReminder()
                pendingNativeReminderMultiple = nil
                deliverNativeReminderIfNeeded()
                return
            }

            if fatigueEngine.isResting {
                clearQueuedNativeReminder()
                notificationService.clearReminder()
                return
            }

            guard isStarted,
                  reminderMode == .systemNotification,
                  reminderPromptState == .initialDecision,
                  fatigueEngine.snapshot.needsRestReminder,
                  activeOverloadEpisodeID == episodeID else {
                clearQueuedNativeReminder()
                notificationService.clearReminder()
                return
            }

            switch result {
            case .delivered:
                notificationPermissionDenied = false
                reminderPromptState = .hidden
                if let pendingMultiple = pendingNativeReminderMultiple,
                   pendingMultiple > deliveryMultiple {
                    pendingNativeReminderMultiple = nil
                    reminderPromptState = .initialDecision
                    deliverNativeReminderIfNeeded()
                } else {
                    pendingNativeReminderMultiple = nil
                }
            case .notAuthorized:
                clearQueuedNativeReminder()
                notificationPermissionDenied = true
                reminderMode = .topPanel
            case .failed:
                clearQueuedNativeReminder()
                notificationPermissionDenied = false
                reminderMode = .topPanel
            case .cancelled:
                clearQueuedNativeReminder()
            }
            persist(at: Date(), force: true)
        }
    }

    private func queueNativeReminderIfNeeded(for multiple: Int) {
        guard nativeReminderDeliveryInFlight,
              multiple > (nativeReminderDeliveryMultiple ?? 0) else { return }
        pendingNativeReminderMultiple = max(pendingNativeReminderMultiple ?? 0, multiple)
    }

    private func clearQueuedNativeReminder() {
        nativeReminderGeneration = UUID()
        pendingNativeReminderMultiple = nil
        nativeReminderDeliveryMultiple = nil
    }

    private func handleNotificationOpen(episodeID: UUID) {
        guard episodeID == activeOverloadEpisodeID,
              fatigueEngine.snapshot.needsRestReminder,
              !fatigueEngine.isResting else { return }
        beginRest()
    }

    private var monitoringPermissionsGranted: Bool {
        inputPermissionGranted
    }

    private func advanceRest(to timestamp: Date) {
        guard let lastTickAt, timestamp > lastTickAt else { return }
        let elapsed = timestamp.timeIntervalSince(lastTickAt)
        process(fatigueEngine.advanceRest(by: elapsed, endingAt: timestamp))
        self.lastTickAt = timestamp
    }

    private var domainSystemState: SystemPresenceState {
        switch systemPresenceState.reason {
        case .active: .available
        case .systemSleep: .systemAsleep
        case .screensAsleep: .displayAsleep
        case .sessionInactive: .locked
        }
    }

    private func description(for state: PresenceState) -> String {
        switch state {
        case .activeInteraction:
            AppLocalization.string(
                L10nKey.presenceActiveInteraction,
                language: resolvedLanguage
            )
        case .passiveStatic:
            AppLocalization.string(L10nKey.presencePassiveStatic, language: resolvedLanguage)
        case .idleUncertain:
            AppLocalization.string(L10nKey.presenceIdleUncertain, language: resolvedLanguage)
        case .unobservable:
            AppLocalization.string(L10nKey.presenceUnobservable, language: resolvedLanguage)
        case .awayConfirmed:
            AppLocalization.string(L10nKey.presenceAwayConfirmed, language: resolvedLanguage)
        }
    }

    private func refreshPresenceDescription() {
        let updatedDescription: String
        if isResting {
            updatedDescription = AppLocalization.string(
                L10nKey.presenceResting,
                language: resolvedLanguage
            )
        } else if let lastPresenceState {
            updatedDescription = description(for: lastPresenceState)
        } else {
            updatedDescription = AppLocalization.string(
                L10nKey.presenceWaitingForFirstInput,
                language: resolvedLanguage
            )
        }
        updatePublished(\.presenceDescription, to: updatedDescription)
    }

    private func updatePublished<Value: Equatable>(
        _ keyPath: ReferenceWritableKeyPath<AppModel, Value>,
        to updatedValue: Value
    ) {
        guard self[keyPath: keyPath] != updatedValue else { return }
        self[keyPath: keyPath] = updatedValue
    }

    private func openPrivacySettings(anchor: String) {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)"
        ) else { return }
        NSWorkspace.shared.open(url)
    }
}
