import Foundation

enum AppLanguage: String, CaseIterable, Codable, Identifiable, Sendable {
    case system
    case zhHans
    case english

    static let defaultValue = AppLanguage.system

    var id: String { rawValue }

    func displayName(language: AppLanguage) -> String {
        let key: L10nKey
        switch self {
        case .system:
            key = .languageSystem
        case .zhHans:
            key = .languageSimplifiedChinese
        case .english:
            key = .languageEnglish
        }
        return AppLocalization.string(key, language: language)
    }

    static func restored(fromPersistedValue value: String?) -> AppLanguage {
        guard let value, let language = AppLanguage(rawValue: value) else {
            return .defaultValue
        }
        return language
    }

    func resolved(preferredLanguages: [String] = Locale.preferredLanguages) -> AppLanguage {
        guard self == .system else { return self }

        for identifier in preferredLanguages {
            let normalized = identifier
                .replacingOccurrences(of: "_", with: "-")
                .lowercased()
            if normalized == "zh"
                || normalized.hasPrefix("zh-hans")
                || normalized.hasPrefix("zh-cn")
                || normalized.hasPrefix("zh-sg")
                || normalized.hasPrefix("zh-my") {
                return .zhHans
            }
            if normalized == "en" || normalized.hasPrefix("en-") {
                return .english
            }
        }

        return .english
    }

    fileprivate var localizationIdentifier: String {
        switch resolved() {
        case .system:
            "en"
        case .zhHans:
            "zh-Hans"
        case .english:
            "en"
        }
    }

    fileprivate var localeIdentifier: String {
        switch resolved() {
        case .system, .english:
            "en_US"
        case .zhHans:
            "zh_CN"
        }
    }
}

enum L10nKey: String, CaseIterable, Sendable {
    case settingsSectionLanguage = "settings.section.language"
    case settingsLanguagePicker = "settings.language.picker"
    case settingsLanguageFooter = "settings.language.footer"
    case languageSystem = "language.system"
    case languageSimplifiedChinese = "language.zh_hans"
    case languageEnglish = "language.english"

    case appAnalyticsWindowTitle = "app.analytics.window_title"
    case menuBarStatusAccessibilityLabel = "menubar.status.accessibility_label"
    case menuBarStatusAccessibilityValue = "menubar.status.accessibility_value"
    case menuBarStatusAccessibilityValueMonitoringIncomplete =
        "menubar.status.accessibility_value.monitoring_incomplete"

    case presenceWaitingForFirstInput = "presence.waiting_first_input"
    case presenceResting = "presence.resting"
    case presenceActiveInteraction = "presence.active_interaction"
    case presencePassiveStatic = "presence.passive_static"
    case presenceIdleUncertain = "presence.idle_uncertain"
    case presenceUnobservable = "presence.unobservable"
    case presenceAwayConfirmed = "presence.away_confirmed"

    case reminderModeSystemNotificationName = "reminder.mode.system_notification.name"
    case reminderModeSystemNotificationDescription =
        "reminder.mode.system_notification.description"
    case reminderModeTopPanelName = "reminder.mode.top_panel.name"
    case reminderModeTopPanelDescription = "reminder.mode.top_panel.description"
    case reminderModeFullScreenName = "reminder.mode.full_screen.name"
    case reminderModeFullScreenDescription = "reminder.mode.full_screen.description"

    case themeQuietHorizonName = "theme.quiet_horizon.name"
    case themeQuietHorizonDescription = "theme.quiet_horizon.description"
    case themeForestLightName = "theme.forest_light.name"
    case themeForestLightDescription = "theme.forest_light.description"
    case themeAlpineMistName = "theme.alpine_mist.name"
    case themeAlpineMistDescription = "theme.alpine_mist.description"
    case themeTwilightDunesName = "theme.twilight_dunes.name"
    case themeTwilightDunesDescription = "theme.twilight_dunes.description"
    case themeMossGardenRainName = "theme.moss_garden_rain.name"
    case themeMossGardenRainDescription = "theme.moss_garden_rain.description"
    case themePolarNightGlowName = "theme.polar_night_glow.name"
    case themePolarNightGlowDescription = "theme.polar_night_glow.description"
    case themeMoonlitBambooName = "theme.moonlit_bamboo.name"
    case themeMoonlitBambooDescription = "theme.moonlit_bamboo.description"
    case themeRainwashedSeaCliffName = "theme.rainwashed_sea_cliff.name"
    case themeRainwashedSeaCliffDescription = "theme.rainwashed_sea_cliff.description"
    case themeCloudfieldWindName = "theme.cloudfield_wind.name"
    case themeCloudfieldWindDescription = "theme.cloudfield_wind.description"
    case themeCurrent = "theme.current"
    case themeSelectionManual = "theme.selection.manual"
    case themeSelectionAutomatic = "theme.selection.automatic"
    case themeSelectionAccessibilityManual = "theme.selection.accessibility.manual"
    case themeSelectionAccessibilityAutomatic = "theme.selection.accessibility.automatic"
    case themeCurrentAccessibility = "theme.current.accessibility"
    case themeBackgroundAccessibility = "theme.background.accessibility"
    case themeSelected = "theme.selected"
    case themeNotSelected = "theme.not_selected"

    case reminderActionDefer = "reminder.action.defer"
    case reminderActionBegin = "reminder.action.begin"
    case unitSecondOne = "unit.second.one"
    case unitSecondOther = "unit.second.other"
    case unitMinuteOne = "unit.minute.one"
    case unitMinuteOther = "unit.minute.other"
    case unitHourOne = "unit.hour.one"
    case unitHourOther = "unit.hour.other"
    case unitTimeOne = "unit.time.one"
    case unitTimeOther = "unit.time.other"
    case unitMinuteShort = "unit.minute.short"
    case unitSecondShort = "unit.second.short"

    case menuHeaderRestRequired = "menu.header.rest_required"
    case menuHeaderCurrentFatigue = "menu.header.current_fatigue"
    case menuHeaderAccessibilityRestRequired = "menu.header.accessibility.rest_required"
    case menuHeaderAccessibilityCurrentFatigue = "menu.header.accessibility.current_fatigue"
    case menuOverloadSince = "menu.overload_since"
    case menuActionBeginRest = "menu.action.begin_rest"
    case menuActionRestNow = "menu.action.rest_now"
    case menuActionBeginRestHintRequired = "menu.action.begin_rest.hint_required"
    case menuActionBeginRestHintOptional = "menu.action.begin_rest.hint_optional"
    case menuActionAnalytics = "menu.action.analytics"
    case menuActionSettings = "menu.action.settings"
    case menuActionQuit = "menu.action.quit"
    case menuResting = "menu.resting"
    case menuRestRemaining = "menu.rest_remaining"
    case menuMonitoringIncomplete = "menu.monitoring_incomplete"
    case menuMonitoringPermissionRequired = "menu.monitoring.permission_required"
    case menuMonitoringUnavailable = "menu.monitoring.unavailable"
    case menuMonitoringRepair = "menu.monitoring.repair"
    case menuMonitoringRepairAccessibilityHint =
        "menu.monitoring.repair.accessibility_hint"
    case menuTodayOverviewTitle = "menu.today_overview.title"
    case menuTodayOverviewOverload = "menu.today_overview.overload"
    case menuTodayOverviewOverloadClear = "menu.today_overview.overload_clear"
    case menuTodayFatiguePeak = "menu.today_fatigue.peak"
    case menuTodayFatigueAccessibility = "menu.today_fatigue.accessibility"

    case overduePanelTitle = "overdue_panel.title"
    case overduePanelDetail = "overdue_panel.detail"
    case overduePanelAccessibility = "overdue_panel.accessibility"

    case overlayDecisionTitle = "overlay.decision.title"
    case overlayDecisionDetail = "overlay.decision.detail"
    case overlayDecisionAccessibilityValue = "overlay.decision.accessibility_value"
    case overlayDecisionDeferHint = "overlay.decision.defer.hint"
    case overlayDecisionBeginHint = "overlay.decision.begin.hint"
    case overlayRestingSecondsUnit = "overlay.resting.seconds_unit"
    case overlayRestingTitle = "overlay.resting.title"
    case overlayRestingSubtitle = "overlay.resting.subtitle"
    case overlayRestingInterruptionNotice = "overlay.resting.interruption_notice"
    case overlayRestingAccessibility = "overlay.resting.accessibility"

    case notificationMilestoneTitle = "notification.milestone.title"
    case notificationMilestoneBody = "notification.milestone.body"

    case settingsSectionAppearance = "settings.section.appearance"
    case settingsThemeRandomRotation = "settings.theme.random_rotation"
    case settingsThemeRotationInterval = "settings.theme.rotation_interval"
    case settingsThemeRotationIntervalAccessibilityLabel =
        "settings.theme.rotation_interval.accessibility_label"
    case settingsThemeRotationIntervalAccessibilityHint =
        "settings.theme.rotation_interval.accessibility_hint"
    case settingsThemeRotationFooter = "settings.theme.rotation_footer"
    case settingsSectionEyeRules = "settings.section.eye_rules"
    case settingsWorkDuration = "settings.work_duration"
    case settingsWorkDurationAccessibilityHint = "settings.work_duration.accessibility_hint"
    case settingsRestDuration = "settings.rest_duration"
    case settingsRestDurationAccessibilityHint = "settings.rest_duration.accessibility_hint"
    case settingsDurationEditingDisabled = "settings.duration.editing_disabled"
    case settingsDurationFooter = "settings.duration.footer"
    case settingsInactivityEnabled = "settings.inactivity.enabled"
    case settingsInactivityDuration = "settings.inactivity.duration"
    case settingsInactivityDurationAccessibilityLabel =
        "settings.inactivity.duration.accessibility_label"
    case settingsInactivityDurationAccessibilityHint =
        "settings.inactivity.duration.accessibility_hint"
    case settingsInactivityFooter = "settings.inactivity.footer"
    case settingsReminderMode = "settings.reminder_mode"
    case settingsNotificationDenied = "settings.notification.denied"
    case settingsNotificationOpen = "settings.notification.open"
    case settingsSectionMonitoringPermission = "settings.section.monitoring_permission"
    case settingsInputMonitoringTitle = "settings.input_monitoring.title"
    case settingsInputMonitoringDescription = "settings.input_monitoring.description"
    case settingsInputMonitoringRequired = "settings.input_monitoring.required"
    case settingsInputMonitoringStalePermission = "settings.input_monitoring.stale_permission"
    case settingsInputMonitoringStarting = "settings.input_monitoring.starting"
    case settingsInputMonitoringRunning = "settings.input_monitoring.running"
    case settingsInputMonitoringUnavailable = "settings.input_monitoring.unavailable"
    case settingsInputMonitoringRepair = "settings.input_monitoring.repair"
    case settingsInputMonitoringRecheck = "settings.input_monitoring.recheck"
    case settingsInputMonitoringCheckPermissionRequired =
        "settings.input_monitoring.check.permission_required"
    case settingsInputMonitoringCheckUnavailable =
        "settings.input_monitoring.check.unavailable"
    case settingsInputMonitoringCheckRunning = "settings.input_monitoring.check.running"
    case settingsInputMonitoringTestReminder = "settings.input_monitoring.test_reminder"
    case settingsInputMonitoringTestReminderAccessibilityHint =
        "settings.input_monitoring.test_reminder.accessibility_hint"
    case settingsPermissionGranted = "settings.permission.granted"
    case settingsPermissionAuthorize = "settings.permission.authorize"
    case settingsSectionGeneral = "settings.section.general"
    case settingsLaunchAtLogin = "settings.launch_at_login"
    case settingsShowOnboarding = "settings.show_onboarding"
    case settingsDataStorage = "settings.data_storage"
    case settingsDataStorageLocalOnly = "settings.data_storage.local_only"
    case settingsClearData = "settings.clear_data"
    case settingsSectionPrivacy = "settings.section.privacy"
    case settingsPrivacyDescription = "settings.privacy.description"
    case settingsClearDataAlertTitle = "settings.clear_data.alert_title"
    case settingsClearDataCancel = "settings.clear_data.cancel"
    case settingsClearDataConfirm = "settings.clear_data.confirm"
    case settingsClearDataAlertMessage = "settings.clear_data.alert_message"

    case onboardingWindowTitle = "onboarding.window_title"
    case onboardingLanguageLabel = "onboarding.language.label"
    case onboardingLanguageAccessibilityLabel = "onboarding.language.accessibility_label"
    case onboardingTitle = "onboarding.title"
    case onboardingSubtitle = "onboarding.subtitle"
    case onboardingPermissionTitle = "onboarding.permission.title"
    case onboardingPermissionDescription = "onboarding.permission.description"
    case onboardingPermissionAuthorize = "onboarding.permission.authorize"
    case onboardingPermissionAuthorizeAccessibilityHint =
        "onboarding.permission.authorize.accessibility_hint"
    case onboardingPermissionRecheck = "onboarding.permission.recheck"
    case onboardingPermissionRecheckAccessibilityHint =
        "onboarding.permission.recheck.accessibility_hint"
    case onboardingPermissionRepair = "onboarding.permission.repair"
    case onboardingPermissionTestReminder = "onboarding.permission.test_reminder"
    case onboardingPermissionTestReminderAccessibilityHint =
        "onboarding.permission.test_reminder.accessibility_hint"
    case onboardingPermissionStatusAuthorizationRequired =
        "onboarding.permission.status.authorization_required"
    case onboardingPermissionStatusStarting = "onboarding.permission.status.starting"
    case onboardingPermissionStatusReady = "onboarding.permission.status.ready"
    case onboardingPrivacyTitle = "onboarding.privacy.title"
    case onboardingPrivacyDescription = "onboarding.privacy.description"
    case onboardingFinish = "onboarding.finish"
    case onboardingFinishAccessibilityHint = "onboarding.finish.accessibility_hint"

    case analyticsTitle = "analytics.title"
    case analyticsDisclaimer = "analytics.disclaimer"
    case analyticsRangeLabel = "analytics.range.label"
    case analyticsRangeToday = "analytics.range.today"
    case analyticsRangeWeek = "analytics.range.week"
    case analyticsCurrentFatigue = "analytics.current_fatigue"
    case analyticsSummaryAccessibility = "analytics.summary.accessibility"
    case analyticsWaitingForRest = "analytics.waiting_for_rest"
    case analyticsOverloadSince = "analytics.overload_since"
    case analyticsRestFrequency = "analytics.rest_frequency"
    case analyticsChartTitle = "analytics.chart.title"
    case analyticsChartThreshold = "analytics.chart.threshold"
    case analyticsChartOverloadZone = "analytics.chart.overload_zone"
    case analyticsTrendTodayTitle = "analytics.trend.today.title"
    case analyticsTrendTodaySubtitle = "analytics.trend.today.subtitle"
    case analyticsTrendWeekTitle = "analytics.trend.week.title"
    case analyticsTrendWeekSubtitle = "analytics.trend.week.subtitle"
    case analyticsTrendWeekOverloadTitle = "analytics.trend.week.overload_title"
    case analyticsTrendWeekPeakTitle = "analytics.trend.week.peak_title"
    case analyticsChartTodayAccessibility = "analytics.chart.today.accessibility"
    case analyticsChartWeekAccessibility = "analytics.chart.week.accessibility"
    case analyticsChartEmptyTitle = "analytics.chart.empty.title"
    case analyticsChartEmptyDescription = "analytics.chart.empty.description"
    case analyticsZeroTodayTitle = "analytics.zero.today.title"
    case analyticsZeroTodayDescription = "analytics.zero.today.description"
    case analyticsZeroWeekTitle = "analytics.zero.week.title"
    case analyticsZeroWeekDescription = "analytics.zero.week.description"
    case analyticsChartAxisTime = "analytics.chart.axis.time"
    case analyticsChartAxisFatigue = "analytics.chart.axis.fatigue"
    case analyticsChartAxisDate = "analytics.chart.axis.date"
    case analyticsChartDailyPeak = "analytics.chart.daily_peak"
    case analyticsChartRestLine = "analytics.chart.rest_line"
    case analyticsMetricPeakFatigueTitle = "analytics.metric.peak_fatigue.title"
    case analyticsMetricPeakFatigueDetail = "analytics.metric.peak_fatigue.detail"
    case analyticsMetricPeakFatigueZero = "analytics.metric.peak_fatigue.zero"
    case analyticsMetricOverloadDurationTitle = "analytics.metric.overload_duration.title"
    case analyticsMetricOverloadDurationDetail = "analytics.metric.overload_duration.detail"
    case analyticsMetricOverloadDurationZero = "analytics.metric.overload_duration.zero"
    case analyticsMetricLongestUsageTitle = "analytics.metric.longest_usage.title"
    case analyticsMetricLongestUsageDetail = "analytics.metric.longest_usage.detail"
    case analyticsMetricLongestUsageZero = "analytics.metric.longest_usage.zero"
    case analyticsMetricCompletedRestTitle = "analytics.metric.completed_rest.title"
    case analyticsMetricCompletedRestDetail = "analytics.metric.completed_rest.detail"
    case analyticsMetricInterruptedRestTitle = "analytics.metric.interrupted_rest.title"
    case analyticsMetricInterruptedRestDetail = "analytics.metric.interrupted_rest.detail"
    case analyticsMetricAverageResponseTitle = "analytics.metric.average_response.title"
    case analyticsMetricAverageResponseDetail = "analytics.metric.average_response.detail"
    case analyticsMetricAverageResponseNoData = "analytics.metric.average_response.no_data"
    case analyticsRestSummaryTitle = "analytics.rest.summary.title"
    case analyticsRestCompletedRatio = "analytics.rest.completed_ratio"
    case analyticsRestCompletedRatioCaption = "analytics.rest.completed_ratio.caption"
    case analyticsRestNoAttempts = "analytics.rest.no_attempts"
    case analyticsRestSourcesTitle = "analytics.rest.sources.title"
    case analyticsRestSummaryAccessibility = "analytics.rest.summary.accessibility"
    case analyticsRestSummaryAccessibilityEmpty = "analytics.rest.summary.accessibility.empty"
    case analyticsEvidenceManualRest = "analytics.evidence.manual_rest"
    case analyticsEvidenceLockOrSleep = "analytics.evidence.lock_or_sleep"
    case analyticsEvidenceInactivityRest = "analytics.evidence.inactivity_rest"
    case analyticsEvidenceDeferredRest = "analytics.evidence.deferred_rest"
}

enum AppLocalization {
    private static let tableName = "Localizable"
    private static let localizedBundleCache = LocalizationBundleCache()

    static func string(
        _ key: L10nKey,
        language: AppLanguage,
        bundle: Bundle = .main
    ) -> String {
        string(key.rawValue, language: language, bundle: bundle)
    }

    static func string(
        _ key: String,
        language: AppLanguage,
        bundle: Bundle = .main
    ) -> String {
        let resolvedLanguage = language.resolved()
        guard let localizedBundle = localizedBundle(
            for: resolvedLanguage,
            in: bundle
        ) else {
            return bundle.localizedString(forKey: key, value: key, table: tableName)
        }

        return localizedBundle.localizedString(forKey: key, value: key, table: tableName)
    }

    static func localizedResourceURL(
        for language: AppLanguage,
        bundle: Bundle = .main
    ) -> URL? {
        localizedBundle(for: language.resolved(), in: bundle)?.url(
            forResource: tableName,
            withExtension: "strings"
        )
    }

    static func format(
        _ key: L10nKey,
        language: AppLanguage,
        arguments: [CVarArg],
        bundle: Bundle = .main
    ) -> String {
        format(key.rawValue, language: language, arguments: arguments, bundle: bundle)
    }

    static func format(
        _ key: String,
        language: AppLanguage,
        arguments: [CVarArg],
        bundle: Bundle = .main
    ) -> String {
        let resolvedLanguage = language.resolved()
        let format = string(key, language: resolvedLanguage, bundle: bundle)
        return String(
            format: format,
            locale: Locale(identifier: resolvedLanguage.localeIdentifier),
            arguments: arguments
        )
    }

    static func duration(
        _ duration: TimeInterval,
        language: AppLanguage,
        bundle: Bundle = .main
    ) -> String {
        let seconds = duration.isFinite ? max(0, Int(duration.rounded())) : 0
        if seconds < 60 {
            return quantity(
                seconds,
                singularKey: "unit.second.one",
                pluralKey: "unit.second.other",
                language: language,
                bundle: bundle
            )
        }

        let minutes = seconds / 60
        if minutes < 60 {
            return quantity(
                minutes,
                singularKey: "unit.minute.one",
                pluralKey: "unit.minute.other",
                language: language,
                bundle: bundle
            )
        }

        let hours = minutes / 60
        let remainingMinutes = minutes % 60
        let hourText = quantity(
            hours,
            singularKey: "unit.hour.one",
            pluralKey: "unit.hour.other",
            language: language,
            bundle: bundle
        )
        guard remainingMinutes > 0 else { return hourText }
        let minuteText = quantity(
            remainingMinutes,
            singularKey: "unit.minute.one",
            pluralKey: "unit.minute.other",
            language: language,
            bundle: bundle
        )
        return "\(hourText) \(minuteText)"
    }

    static func times(
        _ count: Int,
        language: AppLanguage,
        bundle: Bundle = .main
    ) -> String {
        quantity(
            count,
            singularKey: "unit.time.one",
            pluralKey: "unit.time.other",
            language: language,
            bundle: bundle
        )
    }

    static func fatiguePercent(
        _ value: Double,
        language: AppLanguage
    ) -> String {
        let normalized = value.isFinite ? max(0, value) : 0
        return normalized.formatted(
            .percent
                .scale(1)
                .precision(.fractionLength(0))
                .locale(Locale(identifier: language.resolved().localeIdentifier))
        )
    }

    private static func quantity(
        _ count: Int,
        singularKey: String,
        pluralKey: String,
        language: AppLanguage,
        bundle: Bundle
    ) -> String {
        format(
            count == 1 ? singularKey : pluralKey,
            language: language,
            arguments: [count],
            bundle: bundle
        )
    }

    private static func localizedBundle(
        for language: AppLanguage,
        in bundle: Bundle
    ) -> Bundle? {
        let identifier = language.localizationIdentifier
        let cacheKey = "\(bundle.bundleURL.standardizedFileURL.path)|\(identifier)" as NSString
        if let cached = localizedBundleCache.entry(forKey: cacheKey) {
            return cached.bundle
        }

        let roots = [bundle, Bundle(for: LocalizationBundleToken.self)]
        for root in roots {
            if let path = root.path(forResource: identifier, ofType: "lproj"),
               let localizedBundle = Bundle(path: path) {
                localizedBundleCache.insert(
                    LocalizationBundleCacheEntry(bundle: localizedBundle),
                    forKey: cacheKey
                )
                return localizedBundle
            }
            if let resourceURL = root.resourceURL {
                let containingBundle = resourceURL
                    .deletingLastPathComponent()
                    .deletingLastPathComponent()
                let candidate = containingBundle.appendingPathComponent(
                    "\(identifier).lproj",
                    isDirectory: true
                )
                if let localizedBundle = Bundle(url: candidate) {
                    localizedBundleCache.insert(
                        LocalizationBundleCacheEntry(bundle: localizedBundle),
                        forKey: cacheKey
                    )
                    return localizedBundle
                }
            }
        }
        localizedBundleCache.insert(
            LocalizationBundleCacheEntry(bundle: nil),
            forKey: cacheKey
        )
        return nil
    }
}

private final class LocalizationBundleCacheEntry: NSObject {
    let bundle: Bundle?

    init(bundle: Bundle?) {
        self.bundle = bundle
    }
}

private final class LocalizationBundleCache: @unchecked Sendable {
    private let storage = NSCache<NSString, LocalizationBundleCacheEntry>()

    func entry(forKey key: NSString) -> LocalizationBundleCacheEntry? {
        storage.object(forKey: key)
    }

    func insert(_ entry: LocalizationBundleCacheEntry, forKey key: NSString) {
        storage.setObject(entry, forKey: key)
    }
}

private final class LocalizationBundleToken {}
