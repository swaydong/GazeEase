import Foundation

enum FatigueValueFormatter {
    static func display(_ fatigue: Double) -> String {
        let value = fatigue.isFinite ? max(0, fatigue) : 0
        if value <= 999 {
            let displayedValue = value < 100 ? value.rounded(.down) : value.rounded()
            return "\(Int(displayedValue))%"
        }
        return String(format: "%.1fk%%", locale: Locale(identifier: "en_US_POSIX"), value / 1_000)
    }
}

enum ReminderMode: String, CaseIterable, Identifiable, Codable, Sendable {
    case systemNotification = "nativeNotification"
    case topPanel
    case fullScreen

    var id: String { rawValue }

    var displayName: String {
        displayName(language: .zhHans)
    }

    func displayName(language: AppLanguage) -> String {
        switch self {
        case .systemNotification:
            AppLocalization.string(
                L10nKey.reminderModeSystemNotificationName,
                language: language
            )
        case .topPanel:
            AppLocalization.string(L10nKey.reminderModeTopPanelName, language: language)
        case .fullScreen:
            AppLocalization.string(L10nKey.reminderModeFullScreenName, language: language)
        }
    }

    var description: String {
        description(language: .zhHans)
    }

    func description(language: AppLanguage) -> String {
        switch self {
        case .systemNotification:
            AppLocalization.string(
                L10nKey.reminderModeSystemNotificationDescription,
                language: language
            )
        case .topPanel:
            AppLocalization.string(
                L10nKey.reminderModeTopPanelDescription,
                language: language
            )
        case .fullScreen:
            AppLocalization.string(
                L10nKey.reminderModeFullScreenDescription,
                language: language
            )
        }
    }

    var presentsFullScreenDecision: Bool {
        self == .fullScreen
    }

    static func restored(fromPersistedValue value: String?) -> ReminderMode {
        switch value {
        case ReminderMode.systemNotification.rawValue:
            .systemNotification
        case ReminderMode.fullScreen.rawValue:
            .fullScreen
        case ReminderMode.topPanel.rawValue, "progressive", "systemNotification":
            .topPanel
        default:
            .topPanel
        }
    }
}

enum ReminderTheme: String, CaseIterable, Identifiable, Codable, Sendable {
    case quietHorizon
    case forestLight
    case alpineMist
    case twilightDunes

    static let defaultValue = ReminderTheme.quietHorizon

    var id: String { rawValue }

    var displayName: String {
        displayName(language: .zhHans)
    }

    func displayName(language: AppLanguage) -> String {
        switch self {
        case .quietHorizon:
            AppLocalization.string(L10nKey.themeQuietHorizonName, language: language)
        case .forestLight:
            AppLocalization.string(L10nKey.themeForestLightName, language: language)
        case .alpineMist:
            AppLocalization.string(L10nKey.themeAlpineMistName, language: language)
        case .twilightDunes:
            AppLocalization.string(L10nKey.themeTwilightDunesName, language: language)
        }
    }

    var description: String {
        description(language: .zhHans)
    }

    func description(language: AppLanguage) -> String {
        switch self {
        case .quietHorizon:
            AppLocalization.string(L10nKey.themeQuietHorizonDescription, language: language)
        case .forestLight:
            AppLocalization.string(L10nKey.themeForestLightDescription, language: language)
        case .alpineMist:
            AppLocalization.string(L10nKey.themeAlpineMistDescription, language: language)
        case .twilightDunes:
            AppLocalization.string(L10nKey.themeTwilightDunesDescription, language: language)
        }
    }

    var backgroundAssetName: String {
        switch self {
        case .quietHorizon: "RestHorizon"
        case .forestLight: "RestForest"
        case .alpineMist: "RestAlpine"
        case .twilightDunes: "RestDunes"
        }
    }

    var previewAssetName: String {
        switch self {
        case .quietHorizon: "ThemeLakePreview"
        case .forestLight: "ThemeForestPreview"
        case .alpineMist: "ThemeAlpinePreview"
        case .twilightDunes: "ThemeDunesPreview"
        }
    }

    static func restored(fromPersistedValue value: String?) -> ReminderTheme {
        guard let value, let theme = ReminderTheme(rawValue: value) else {
            return .defaultValue
        }
        return theme
    }
}

struct ReminderThemeRotationScheduler: Equatable, Sendable {
    private(set) var nextChangeAt: Date?
    private(set) var pendingTheme: ReminderTheme?

    init(
        nextChangeAt: Date? = nil,
        pendingTheme: ReminderTheme? = nil
    ) {
        self.nextChangeAt = nextChangeAt
        self.pendingTheme = pendingTheme
    }

    mutating func configure(
        enabled: Bool,
        interval: TimeInterval,
        at now: Date
    ) {
        pendingTheme = nil
        nextChangeAt = enabled
            ? now.addingTimeInterval(Self.normalizedInterval(interval))
            : nil
    }

    /// Returns a theme only when it can be applied without changing a visible reminder.
    /// A due change while blocked is retained and applied once the reminder is gone.
    mutating func advance(
        enabled: Bool,
        interval: TimeInterval,
        at now: Date,
        currentTheme: ReminderTheme,
        shouldDefer: Bool,
        randomValue: UInt64
    ) -> ReminderTheme? {
        guard enabled else {
            nextChangeAt = nil
            pendingTheme = nil
            return nil
        }

        let normalizedInterval = Self.normalizedInterval(interval)

        if let pendingTheme {
            guard !shouldDefer else { return nil }
            let theme = pendingTheme == currentTheme
                ? Self.randomTheme(excluding: currentTheme, randomValue: randomValue)
                : pendingTheme
            self.pendingTheme = nil
            nextChangeAt = now.addingTimeInterval(normalizedInterval)
            return theme
        }

        guard let nextChangeAt else {
            self.nextChangeAt = now.addingTimeInterval(normalizedInterval)
            return nil
        }
        guard now >= nextChangeAt else { return nil }

        let theme = Self.randomTheme(excluding: currentTheme, randomValue: randomValue)
        guard let theme else {
            self.nextChangeAt = now.addingTimeInterval(normalizedInterval)
            return nil
        }

        if shouldDefer {
            pendingTheme = theme
            self.nextChangeAt = nil
            return nil
        }

        self.nextChangeAt = now.addingTimeInterval(normalizedInterval)
        return theme
    }

    private static func randomTheme(
        excluding currentTheme: ReminderTheme,
        randomValue: UInt64
    ) -> ReminderTheme? {
        let alternatives = ReminderTheme.allCases.filter { $0 != currentTheme }
        guard !alternatives.isEmpty else { return nil }
        let index = Int(randomValue % UInt64(alternatives.count))
        return alternatives[index]
    }

    private static func normalizedInterval(_ interval: TimeInterval) -> TimeInterval {
        guard interval.isFinite else { return 1 }
        return max(1, interval)
    }
}

enum ReminderPromptState: String, Codable, Equatable, Sendable {
    case hidden
    case initialDecision
    case manualRetry

    static func restored(
        savedState: ReminderPromptState?,
        legacyDecisionPending: Bool?
    ) -> ReminderPromptState {
        if let savedState {
            return savedState
        }
        return legacyDecisionPending == true ? .initialDecision : .hidden
    }

    func applying(_ event: FatigueEvent) -> ReminderPromptState {
        switch event {
        case .restRequired:
            .initialDecision
        case let .restStarted(rest):
            rest.trigger == .manual ? .hidden : self
        case let .restInterrupted(attempt):
            attempt.trigger == .manual ? .manualRetry : self
        case .restCompleted, .overloadCompleted, .continuedWorking:
            .hidden
        case .fatigueChanged:
            self
        }
    }
}

struct FatigueReminderMilestones: Equatable, Sendable {
    private(set) var lastReminderMultiple: Int

    init(
        restoredLastReminderMultiple: Int? = nil,
        restRequired: Bool = false,
        fatigue: Double = 0
    ) {
        guard restRequired else {
            lastReminderMultiple = 0
            return
        }

        let inferredMultiple = max(1, Self.multiple(for: fatigue))
        if let restoredLastReminderMultiple, restoredLastReminderMultiple >= 0 {
            lastReminderMultiple = max(restoredLastReminderMultiple, inferredMultiple)
        } else {
            lastReminderMultiple = inferredMultiple
        }
    }

    @discardableResult
    mutating func registerInitialReminder(fatigue: Double) -> Int? {
        let multiple = max(1, Self.multiple(for: fatigue))
        guard multiple > lastReminderMultiple else { return nil }
        lastReminderMultiple = multiple
        return multiple
    }

    @discardableResult
    mutating func consumeNewMilestone(from previousFatigue: Double, to fatigue: Double) -> Int? {
        guard fatigue > previousFatigue else { return nil }
        let multiple = Self.multiple(for: fatigue)
        guard multiple >= 1, multiple > lastReminderMultiple else { return nil }
        lastReminderMultiple = multiple
        return multiple
    }

    mutating func reset() {
        lastReminderMultiple = 0
    }

    private static func multiple(for fatigue: Double) -> Int {
        guard fatigue.isFinite, fatigue >= 100 else { return 0 }
        return Int(floor((fatigue + 0.000_001) / 100))
    }
}

enum ReminderDecisionAction: CaseIterable, Equatable {
    case deferRest
    case beginRest

    var title: String {
        title(language: .zhHans)
    }

    func title(language: AppLanguage) -> String {
        switch self {
        case .deferRest:
            AppLocalization.string(L10nKey.reminderActionDefer, language: language)
        case .beginRest:
            AppLocalization.string(L10nKey.reminderActionBegin, language: language)
        }
    }
}

enum ReminderOverlayPhase: Equatable {
    case decision
    case resting
}

struct ReminderPanelPresentation: Equatable {
    var showsDeferAction: Bool {
        true
    }

    var contentWidth: CGFloat {
        502
    }

    var panelSize: CGSize {
        CGSize(width: contentWidth + 12, height: 108)
    }
}

struct ReminderPresentationPolicy {
    static func panel(
        restRequired: Bool,
        isResting: Bool,
        promptState: ReminderPromptState,
        reminderMode: ReminderMode
    ) -> ReminderPanelPresentation? {
        guard restRequired,
              !isResting,
              promptState != .hidden else { return nil }

        if promptState == .initialDecision,
           reminderMode != .topPanel {
            return nil
        }
        return ReminderPanelPresentation()
    }

    static func overlay(
        restRequired: Bool,
        isResting: Bool,
        promptState: ReminderPromptState,
        reminderMode: ReminderMode
    ) -> ReminderOverlayPhase? {
        if isResting {
            return .resting
        }
        if restRequired,
           promptState == .initialDecision,
           reminderMode.presentsFullScreenDecision {
            return .decision
        }
        return nil
    }
}

struct FatiguePoint: Identifiable, Sendable {
    let timestamp: Date
    let fatigue: Double

    var id: Date { timestamp }
}

struct DailyPeak: Identifiable, Sendable {
    let date: Date
    let peak: Double

    var id: Date { date }
}

struct AnalyticsMetrics: Sendable {
    var peakFatigue: Double
    var overloadDuration: TimeInterval
    var longestUsageDuration: TimeInterval
    var completedRestCount: Int
    var interruptedRestCount: Int
    var continuedWorkingCount: Int
    var averageResponseDuration: TimeInterval?
    var manualRestCount: Int
    var systemRestCount: Int
    var inactivityRestCount: Int

    static let empty = AnalyticsMetrics(
        peakFatigue: 0,
        overloadDuration: 0,
        longestUsageDuration: 0,
        completedRestCount: 0,
        interruptedRestCount: 0,
        continuedWorkingCount: 0,
        averageResponseDuration: nil,
        manualRestCount: 0,
        systemRestCount: 0,
        inactivityRestCount: 0
    )
}

struct AnalyticsSnapshot: Sendable {
    var fatiguePoints: [FatiguePoint]
    var dailyPeaks: [DailyPeak]
    var today: AnalyticsMetrics
    var week: AnalyticsMetrics

    static let empty = AnalyticsSnapshot(
        fatiguePoints: [],
        dailyPeaks: [],
        today: .empty,
        week: .empty
    )
}
