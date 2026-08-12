import AppKit
import Combine
import Foundation
import OSLog

@MainActor
final class AppModel: ObservableObject {
    private static var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    static let shared = AppModel()

    @Published private(set) var fatigue: Double
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
    private var restInputGraceUntil: Date?
    private var ticker: Timer?
    private var isStarted = false
    private var nextInputMonitorRetryAt = Date.distantPast
    private var inputMonitorRetryDelay: TimeInterval = 2
    private var nativeReminderDeliveryInFlight = false
    private var nativeReminderDeliveryMultiple: Int?
    private var pendingNativeReminderMultiple: Int?
    private var shouldDelayThemeRotationForSurfaceRetirement = false
    private var themeRotationSurfaceRetirementTask: Task<Void, Never>?

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
        let runtime = store.loadRuntimeState()
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
        self.restRequired = restoredSnapshot.restRequired
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
        self.reminderPromptState = ReminderPromptState.restored(
            savedState: runtime?.reminderPromptState,
            legacyDecisionPending: runtime?.reminderDecisionPending
        )
        self.notificationPermissionDenied = false
        self.randomThemeRotationEnabled = configuredRandomThemeRotationEnabled
        self.randomThemeRotationIntervalMinutes = configuredRandomThemeRotationIntervalMinutes
        self.reminderTheme = Preferences.reminderTheme
        self.reminderMode = Preferences.reminderMode

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
        eventStore.cleanExpiredData()
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
        updatePermissions(permissionCenter.refresh())
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
        let now = Date()
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

    func completeOnboarding() {
        guard !onboardingCompleted else { return }
        onboardingCompleted = true
        Preferences.onboardingCompleted = true
    }

    func showOnboarding() {
        onboardingWindowController.show()
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
        eventStore.clearAll()
        persist(at: Date(), force: true)
        refreshAnalytics()
    }

    func refreshAnalytics() {
        analytics = eventStore.analytics()
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
        pendingInput = true

        guard fatigueEngine.isResting else {
            return
        }

        if systemPresenceState.isAway {
            process(fatigueEngine.interruptRest(reason: .monitoringUnavailable, at: event.timestamp))
            publish(at: event.timestamp)
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
            let permissions = permissionCenter.refresh()
            if permissions.inputMonitoring != .authorized {
                process(fatigueEngine.interruptRest(reason: .monitoringUnavailable, at: state.timestamp))
            }
            // Account for timer suspension while the Mac was asleep before ending rest.
            tick(at: state.timestamp, allowLongInterval: true)
        }

        systemPresenceState = state

        if !wasAway, state.isAway {
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
        } else if wasAway, !state.isAway, fatigueEngine.isResting {
            process(fatigueEngine.interruptRest(reason: .cancelled, at: state.timestamp))
            publish(at: state.timestamp)
        }
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
        let presenceUpdate = presenceEngine.ingest(sample)
        var completedInactivityRest = false

        if fatigueEngine.isResting {
            if let activeRest = fatigueEngine.snapshot.activeRest,
               !monitoringPermissionsGranted ||
               (activeRest.trigger == .manual &&
                   !inputMonitor.isRunning) {
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
        persist(at: now, force: completedInactivityRest)
        if completedInactivityRest {
            refreshAnalytics()
        }
    }

    private func process(_ events: [FatigueEvent]) {
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
                guard activeOverloadEpisodeID != nil,
                      let multiple = fatigueReminderMilestones.consumeNewMilestone(
                          from: from,
                          to: to
                      ) else { break }

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

            case let .restCompleted(attempt):
                record(attempt)
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
                notificationService.clearReminder()
                if let id = activeOverloadEpisodeID {
                    eventStore.markOverloadResponse(id: id, kind: "continued", at: at)
                }
            }
        }
    }

    private func record(_ attempt: RestAttempt) {
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
        eventStore.recordRestAttempt(
            overloadEpisodeID: activeOverloadEpisodeID,
            startedAt: attempt.startedAt,
            endedAt: attempt.endedAt,
            startFatigue: attempt.startFatiguePercent,
            endFatigue: attempt.endFatiguePercent,
            source: attempt.trigger.rawValue,
            outcome: outcome,
            interruptionReason: reason
        )
        refreshAnalytics()
    }

    private func publish(at now: Date, presenceState: PresenceState? = nil) {
        let snapshot = fatigueEngine.snapshot
        if isResting, !snapshot.isResting {
            shouldDelayThemeRotationForSurfaceRetirement = true
        }
        fatigue = snapshot.fatiguePercent
        restRequired = snapshot.restRequired
        isResting = snapshot.isResting
        restProgress = fatigueEngine.restProgress
        overloadDuration = snapshot.overloadStartedAt.map {
            max(0, now.timeIntervalSince($0))
        } ?? 0
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

    private func persist(at now: Date, force: Bool = false) {
        if !force, let lastPersistenceAt, now.timeIntervalSince(lastPersistenceAt) < 5 {
            return
        }
        let elapsed = lastPersistenceAt.map { max(0, now.timeIntervalSince($0)) } ?? 0
        lastPersistenceAt = now
        let snapshot = fatigueEngine.snapshot
        if let id = activeOverloadEpisodeID {
            eventStore.updateOverload(
                id: id,
                peakFatigue: snapshot.fatiguePercent,
                save: false
            )
        }
        eventStore.saveRuntimeState(PersistedRuntimeState(
            fatigue: snapshot.fatiguePercent,
            restRequired: snapshot.restRequired,
            overloadStartedAt: snapshot.overloadStartedAt,
            overloadEpisodeID: activeOverloadEpisodeID,
            continuousUsageDuration: continuousUsageDuration,
            reminderPromptState: reminderPromptState,
            reminderDecisionPending: reminderPromptState != .hidden,
            lastInactivityRestCompletedAt: lastInactivityRestCompletedAt,
            lastReminderMultiple: fatigueReminderMilestones.lastReminderMultiple,
            savedAt: now
        ))
        eventStore.recordSample(
            at: now,
            fatigue: snapshot.fatiguePercent,
            presenceState: presenceEngine.state.rawValue,
            elapsed: elapsed,
            continuousUsageDuration: continuousUsageDuration
        )
    }

    private func updatePermissions(_ state: PermissionState) {
        inputPermissionGranted = state.inputMonitoring == .authorized

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
        isMonitoringComplete = status.isComplete
    }

    private func handleReminderModeChange() {
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
        guard reminderMode == .systemNotification,
              reminderPromptState == .initialDecision,
              snapshot.restRequired,
              let episodeID = activeOverloadEpisodeID else { return }

        let deliveryMultiple = max(1, fatigueReminderMilestones.lastReminderMultiple)
        if nativeReminderDeliveryInFlight {
            queueNativeReminderIfNeeded(for: deliveryMultiple)
            return
        }

        nativeReminderDeliveryInFlight = true
        nativeReminderDeliveryMultiple = deliveryMultiple
        let display = FatigueValueFormatter.display(snapshot.fatiguePercent)
        Task { @MainActor [weak self] in
            guard let self else { return }
            let result = await notificationService.deliver(
                fatigueDisplay: display,
                episodeID: episodeID,
                reminderMultiple: deliveryMultiple,
                language: resolvedLanguage
            )
            nativeReminderDeliveryInFlight = false
            nativeReminderDeliveryMultiple = nil

            if fatigueEngine.isResting {
                clearQueuedNativeReminder()
                notificationService.clearReminder()
                return
            }

            guard isStarted,
                  reminderMode == .systemNotification,
                  reminderPromptState == .initialDecision,
                  fatigueEngine.snapshot.restRequired,
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
        pendingNativeReminderMultiple = nil
        nativeReminderDeliveryMultiple = nil
    }

    private func handleNotificationOpen(episodeID: UUID) {
        guard episodeID == activeOverloadEpisodeID,
              fatigueEngine.snapshot.restRequired,
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
        if isResting {
            presenceDescription = AppLocalization.string(
                L10nKey.presenceResting,
                language: resolvedLanguage
            )
        } else if let lastPresenceState {
            presenceDescription = description(for: lastPresenceState)
        } else {
            presenceDescription = AppLocalization.string(
                L10nKey.presenceWaitingForFirstInput,
                language: resolvedLanguage
            )
        }
    }

    private func openPrivacySettings(anchor: String) {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)"
        ) else { return }
        NSWorkspace.shared.open(url)
    }
}
