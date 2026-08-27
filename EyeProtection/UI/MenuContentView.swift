import AppKit
import Charts
import SwiftUI

enum EyePalette {
    static let calm = Color(red: 0.20, green: 0.66, blue: 0.58)
    static let watch = Color(red: 0.96, green: 0.60, blue: 0.20)
    static let overdue = Color(red: 0.91, green: 0.25, blue: 0.21)

    static func fatigueColor(_ fatigue: Double) -> Color {
        switch fatigue {
        case ..<70: calm
        case ..<100: watch
        default: overdue
        }
    }
}

enum EyeDurationFormatter {
    static func compact(
        _ duration: TimeInterval,
        language: AppLanguage = .zhHans
    ) -> String {
        AppLocalization.duration(duration, language: language)
    }
}

struct MenuContentPresentation: Equatable {
    let fatigue: Double
    let fatigueDisplay: String
    let restRequired: Bool
    let isResting: Bool
    let overloadDuration: TimeInterval
    let presenceDescription: String
    let isMonitoringComplete: Bool
    let restSecondsRemaining: TimeInterval
    let theme: ReminderTheme
    var inputPermissionGranted: Bool = true
    var language: AppLanguage = .zhHans
    var todayOverview: MenuTodayOverviewSummary = .empty
    var todayFatigue: MenuTodayFatigueSummary = .empty

    var fatigueProgress: Double {
        min(max(fatigue / 100, 0), 1)
    }

    var headerAccessibilityLabel: String {
        if restRequired {
            return AppLocalization.format(
                .menuHeaderAccessibilityRestRequired,
                language: language,
                arguments: [
                    fatigueDisplay,
                    EyeDurationFormatter.compact(overloadDuration, language: language)
                ]
            )
        }
        return AppLocalization.format(
            .menuHeaderAccessibilityCurrentFatigue,
            language: language,
            arguments: [fatigueDisplay]
        )
    }

    var todayOverviewAccessibilityLabel: String {
        todayOverview.overloadDisplay(language: language)
            + " "
            + todayFatigue.accessibilityLabel(language: language)
    }

    var monitoringIssueKey: L10nKey {
        inputPermissionGranted
            ? .menuMonitoringUnavailable
            : .menuMonitoringPermissionRequired
    }
}

struct MenuTodayFatiguePoint: Identifiable, Equatable {
    let timestamp: Date
    let fatigue: Double

    var id: Date { timestamp }
}

struct MenuTodayFatigueSummary: Equatable {
    static let maximumVisualPointCount = 96

    let points: [MenuTodayFatiguePoint]
    let visualPoints: [MenuTodayFatiguePoint]
    let currentFatigue: Double

    static let empty = MenuTodayFatigueSummary(points: [], currentFatigue: 0)

    init(
        points: [MenuTodayFatiguePoint],
        currentFatigue: Double,
        now: Date = Date(),
        calendar: Calendar = .current
    ) {
        let startOfDay = calendar.startOfDay(for: now)
        let normalizedCurrent = currentFatigue.isFinite ? max(0, currentFatigue) : 0
        let sorted = points
            .filter {
                $0.timestamp >= startOfDay
                    && $0.timestamp <= now
                    && $0.fatigue.isFinite
            }
            .map {
                MenuTodayFatiguePoint(
                    timestamp: $0.timestamp,
                    fatigue: max(0, $0.fatigue)
                )
            }
            .sorted { $0.timestamp < $1.timestamp }

        var normalized: [MenuTodayFatiguePoint] = []
        for point in sorted {
            if normalized.last?.timestamp == point.timestamp {
                normalized[normalized.count - 1] = point
            } else {
                normalized.append(point)
            }
        }

        if !normalized.isEmpty || normalizedCurrent > 0 {
            let livePoint = MenuTodayFatiguePoint(
                timestamp: now,
                fatigue: normalizedCurrent
            )
            if normalized.last?.timestamp == now {
                normalized[normalized.count - 1] = livePoint
            } else {
                normalized.append(livePoint)
            }
        }

        self.points = normalized
        self.visualPoints = Self.makeVisualPoints(normalized)
        self.currentFatigue = normalizedCurrent
    }

    private static func makeVisualPoints(
        _ points: [MenuTodayFatiguePoint]
    ) -> [MenuTodayFatiguePoint] {
        guard points.count > maximumVisualPointCount else { return points }

        let first = points[0]
        let last = points[points.count - 1]
        let interior = points.dropFirst().dropLast()
        let bucketCount = (maximumVisualPointCount - 2) / 2
        var sampled = [first]
        sampled.reserveCapacity(maximumVisualPointCount)

        for bucketIndex in 0..<bucketCount {
            let lowerBound = interior.startIndex
                + bucketIndex * interior.count / bucketCount
            let upperBound = interior.startIndex
                + (bucketIndex + 1) * interior.count / bucketCount
            let bucket = interior[lowerBound..<upperBound]
            guard let latest = bucket.last else { continue }

            let peak = bucket.max { left, right in
                left.fatigue < right.fatigue
            } ?? latest
            if peak.timestamp < latest.timestamp {
                sampled.append(peak)
                sampled.append(latest)
            } else if peak.timestamp > latest.timestamp {
                sampled.append(latest)
                sampled.append(peak)
            } else {
                sampled.append(latest)
            }
        }

        sampled.append(last)
        return sampled
    }

    var peakFatigue: Double {
        points.map(\.fatigue).max() ?? currentFatigue
    }

    var upperBound: Double {
        max(120, ceil(max(100, peakFatigue * 1.08) / 20) * 20)
    }

    func peakDisplay(language: AppLanguage) -> String {
        AppLocalization.format(
            .menuTodayFatiguePeak,
            language: language,
            arguments: [FatigueValueFormatter.display(peakFatigue)]
        )
    }

    func accessibilityLabel(language: AppLanguage) -> String {
        AppLocalization.format(
            .menuTodayFatigueAccessibility,
            language: language,
            arguments: [
                points.count,
                FatigueValueFormatter.display(peakFatigue),
                FatigueValueFormatter.display(currentFatigue)
            ]
        )
    }
}

struct MenuTodayOverviewSummary: Equatable {
    let overloadDuration: TimeInterval

    static let empty = MenuTodayOverviewSummary(overloadDuration: 0)

    func overloadDisplay(language: AppLanguage) -> String {
        guard overloadDuration > 0 else {
            return AppLocalization.string(
                .menuTodayOverviewOverloadClear,
                language: language
            )
        }
        return AppLocalization.format(
            .menuTodayOverviewOverload,
            language: language,
            arguments: [EyeDurationFormatter.compact(overloadDuration, language: language)]
        )
    }
}

enum MenuRefreshPolicy {
    static let visibleRefreshInterval: TimeInterval = 20

    static func shouldRun(isMenuVisible: Bool) -> Bool {
        isMenuVisible
    }
}

enum MenuHostWindowVisibilityPolicy {
    static func isVisible(
        isWindowVisible: Bool,
        isKeyWindow: Bool
    ) -> Bool {
        isWindowVisible && isKeyWindow
    }

    static func isEventForHostWindow(
        eventWindow: NSWindow?,
        hostWindow: NSWindow?
    ) -> Bool {
        guard let eventWindow, let hostWindow else { return false }
        return eventWindow === hostWindow
    }
}

struct MenuContentView: View {
    @ObservedObject var model: AppModel
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings
    @State private var todayFatigue = MenuTodayFatigueSummary.empty
    @State private var isMenuVisible = false

    var body: some View {
        MenuContentScene(
            presentation: MenuContentPresentation(
                fatigue: model.fatigue,
                fatigueDisplay: model.fatigueDisplay,
                restRequired: model.restRequired,
                isResting: model.isResting,
                overloadDuration: model.overloadDuration,
                presenceDescription: model.presenceDescription,
                isMonitoringComplete: model.isMonitoringComplete,
                restSecondsRemaining: model.restSecondsRemaining,
                theme: model.reminderTheme,
                inputPermissionGranted: model.inputPermissionGranted,
                language: model.resolvedLanguage,
                todayOverview: MenuTodayOverviewSummary(
                    overloadDuration: model.analytics.today.overloadDuration
                ),
                todayFatigue: todayFatigue
            ),
            onBeginRest: model.beginRest,
            onOpenAnalytics: {
                model.refreshAnalytics()
                NSApp.activate(ignoringOtherApps: true)
                openWindow(id: "analytics")
            },
            onOpenSettings: {
                NSApp.activate(ignoringOtherApps: true)
                openSettings()
            },
            onQuit: model.quit,
            onRepairMonitoring: {
                NSApp.activate(ignoringOtherApps: true)
                model.repairInputMonitoring()
            }
        )
        .background {
            MenuHostWindowVisibilityReader { isVisible in
                guard isMenuVisible != isVisible else { return }
                isMenuVisible = isVisible
            }
            .accessibilityHidden(true)
        }
        .task(id: isMenuVisible) {
            guard MenuRefreshPolicy.shouldRun(isMenuVisible: isMenuVisible) else {
                return
            }
            refreshTodayFatigue()
            do {
                try await Task.sleep(for: .milliseconds(120))
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            model.refreshAnalyticsIfNeeded()
            refreshTodayFatigue()

            while !Task.isCancelled {
                do {
                    try await Task.sleep(
                        for: .seconds(MenuRefreshPolicy.visibleRefreshInterval)
                    )
                } catch {
                    return
                }
                guard !Task.isCancelled else { return }
                model.refreshAnalyticsIfNeeded()
                refreshTodayFatigue()
            }
        }
    }

    private func refreshTodayFatigue(at now: Date = Date()) {
        let updatedSummary = MenuTodayFatigueSummary(
            points: model.analytics.fatiguePoints.map {
                MenuTodayFatiguePoint(
                    timestamp: $0.timestamp,
                    fatigue: $0.fatigue
                )
            },
            currentFatigue: model.fatigue,
            now: now
        )
        guard todayFatigue != updatedSummary else { return }
        todayFatigue = updatedSummary
    }
}

private struct MenuHostWindowVisibilityReader: NSViewRepresentable {
    let onVisibilityChange: (Bool) -> Void

    func makeNSView(context: Context) -> MenuHostWindowVisibilityProbeView {
        let view = MenuHostWindowVisibilityProbeView()
        view.onVisibilityChange = onVisibilityChange
        return view
    }

    func updateNSView(
        _ nsView: MenuHostWindowVisibilityProbeView,
        context: Context
    ) {
        nsView.onVisibilityChange = onVisibilityChange
        nsView.publishCurrentVisibility()
    }

    static func dismantleNSView(
        _ nsView: MenuHostWindowVisibilityProbeView,
        coordinator: Void
    ) {
        nsView.stopObservingWindow()
    }
}

@MainActor
private final class MenuHostWindowVisibilityProbeView: NSView {
    var onVisibilityChange: ((Bool) -> Void)?

    private weak var observedWindow: NSWindow?
    private var lastPublishedVisibility: Bool?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        observe(window)
    }

    func publishCurrentVisibility() {
        let isVisible = observedWindow.map {
            MenuHostWindowVisibilityPolicy.isVisible(
                isWindowVisible: $0.isVisible,
                isKeyWindow: $0.isKeyWindow
            )
        } ?? false
        guard lastPublishedVisibility != isVisible else { return }
        lastPublishedVisibility = isVisible
        onVisibilityChange?(isVisible)
    }

    func stopObservingWindow() {
        NotificationCenter.default.removeObserver(self)
        observedWindow = nil
        lastPublishedVisibility = nil
    }

    private func observe(_ window: NSWindow?) {
        guard observedWindow !== window else {
            publishCurrentVisibility()
            return
        }

        stopObservingWindow()
        observedWindow = window
        guard let window else {
            publishCurrentVisibility()
            return
        }

        let notificationCenter = NotificationCenter.default
        notificationCenter.addObserver(
            self,
            selector: #selector(windowVisibilityDidChange(_:)),
            name: NSWindow.didBecomeKeyNotification,
            object: window
        )
        notificationCenter.addObserver(
            self,
            selector: #selector(windowVisibilityDidChange(_:)),
            name: NSWindow.didResignKeyNotification,
            object: window
        )
        notificationCenter.addObserver(
            self,
            selector: #selector(windowVisibilityDidChange(_:)),
            name: NSWindow.didChangeOcclusionStateNotification,
            object: window
        )
        notificationCenter.addObserver(
            self,
            selector: #selector(windowVisibilityDidChange(_:)),
            name: NSWindow.willCloseNotification,
            object: window
        )
        publishCurrentVisibility()
    }

    @objc private func windowVisibilityDidChange(_ notification: Notification) {
        guard MenuHostWindowVisibilityPolicy.isEventForHostWindow(
            eventWindow: notification.object as? NSWindow,
            hostWindow: observedWindow
        ) else { return }
        publishCurrentVisibility()
    }
}

struct MenuContentScene: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    let presentation: MenuContentPresentation
    let onBeginRest: () -> Void
    let onOpenAnalytics: () -> Void
    let onOpenSettings: () -> Void
    let onQuit: () -> Void
    var onRepairMonitoring: () -> Void = {}
    var reduceTransparencyOverride: Bool? = nil

    var body: some View {
        VStack(spacing: 0) {
            fatigueHeader

            themedDivider

            VStack(spacing: 10) {
                statusRow

                Button(action: onBeginRest) {
                    Label(
                        localized(
                            presentation.restRequired
                                ? .menuActionBeginRest
                                : .menuActionRestNow
                        ),
                        systemImage: "leaf.fill"
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(MenuRestButtonStyle(
                    style: presentation.theme.style,
                    isPrimary: presentation.restRequired,
                    reduceTransparency: effectiveReduceTransparency
                ))
                .accessibilityHint(
                    presentation.restRequired
                        ? localized(.menuActionBeginRestHintRequired)
                        : localized(.menuActionBeginRestHintOptional)
                )

                todayOverview
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 13)

            themedDivider

            VStack(spacing: 2) {
                MenuActionButton(
                    title: localized(.menuActionAnalytics),
                    systemImage: "chart.xyaxis.line",
                    style: presentation.theme.style,
                    action: onOpenAnalytics
                )

                MenuActionButton(
                    title: localized(.menuActionSettings),
                    systemImage: "gearshape",
                    style: presentation.theme.style,
                    action: onOpenSettings
                )

                MenuActionButton(
                    title: localized(.menuActionQuit),
                    systemImage: "power",
                    style: presentation.theme.style,
                    action: onQuit
                )
                .keyboardShortcut("q")
            }
            .padding(6)
        }
        .frame(width: 320)
        .frame(minHeight: 425, alignment: .top)
        .background {
            MenuContentBackground(
                theme: presentation.theme,
                reduceTransparency: effectiveReduceTransparency
            )
        }
        .foregroundStyle(.white.opacity(0.90))
    }

    private var fatigueHeader: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .stroke(.white.opacity(effectiveReduceTransparency ? 0.16 : 0.10), lineWidth: 7)

                Circle()
                    .trim(from: 0, to: presentation.fatigueProgress)
                    .stroke(
                        LinearGradient(
                            colors: [
                                presentation.theme.style.accentHighlight,
                                presentation.theme.style.accent
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        style: StrokeStyle(lineWidth: 7, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))

                Image("MenuBarTaiji")
                    .resizable()
                    .renderingMode(.template)
                    .scaledToFit()
                    .foregroundStyle(presentation.theme.style.accentHighlight)
                    .frame(width: 20, height: 20)
            }
            .frame(width: 58, height: 58)
            .fixedSize()
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(localized(
                    presentation.restRequired
                        ? .menuHeaderRestRequired
                        : .menuHeaderCurrentFatigue
                ))
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white.opacity(effectiveReduceTransparency ? 0.78 : 0.64))
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)

                Text(presentation.fatigueDisplay)
                    .font(.system(size: 31, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(presentation.theme.style.accentHighlight)
                    .lineLimit(1)
                    .minimumScaleFactor(0.80)

                if presentation.restRequired {
                    Text(AppLocalization.format(
                        .menuOverloadSince,
                        language: presentation.language,
                        arguments: [EyeDurationFormatter.compact(
                            presentation.overloadDuration,
                            language: presentation.language
                        )]
                    ))
                        .font(.caption.weight(.medium))
                        .foregroundStyle(presentation.theme.style.accent.opacity(0.92))
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(presentation.headerAccessibilityLabel)
    }

    private var statusRow: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(
                    presentation.isMonitoringComplete
                        ? presentation.theme.style.accent
                        : EyePalette.watch
                )
                .frame(width: 7, height: 7)
                .accessibilityHidden(true)

            if !presentation.isResting, !presentation.isMonitoringComplete {
                Text(localized(presentation.monitoringIssueKey))
                    .foregroundStyle(EyePalette.watch)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
            } else {
                Text(
                    presentation.isResting
                        ? localized(.menuResting)
                        : presentation.presenceDescription
                )
                .lineLimit(1)
            }

            Spacer(minLength: 8)

            if presentation.isResting {
                Text(AppLocalization.format(
                    .menuRestRemaining,
                    language: presentation.language,
                    arguments: [Int(ceil(presentation.restSecondsRemaining))]
                ))
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.62))
                    .lineLimit(1)
            } else if !presentation.isMonitoringComplete {
                Button(localized(.menuMonitoringRepair), action: onRepairMonitoring)
                    .buttonStyle(.plain)
                    .fontWeight(.semibold)
                    .foregroundStyle(EyePalette.watch)
                    .lineLimit(1)
                    .accessibilityHint(localized(.menuMonitoringRepairAccessibilityHint))
            }
        }
        .font(.caption)
        .foregroundStyle(.white.opacity(effectiveReduceTransparency ? 0.86 : 0.72))
    }

    private var todayOverview: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "sun.horizon.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(presentation.theme.style.accentHighlight)
                    .accessibilityHidden(true)

                Text(localized(.menuTodayOverviewTitle))
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)

                Spacer(minLength: 8)

                Text(presentation.todayOverview.overloadDisplay(
                    language: presentation.language
                ))
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(presentation.theme.style.accentHighlight)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
                    .layoutPriority(1)
            }

            HStack(spacing: 8) {
                Text(localized(.analyticsChartTitle))
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(
                        effectiveReduceTransparency ? 0.82 : 0.66
                    ))
                    .lineLimit(1)

                Spacer(minLength: 8)

                Text(presentation.todayFatigue.peakDisplay(
                    language: presentation.language
                ))
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(presentation.theme.style.accentHighlight)
                    .lineLimit(1)
            }

            MenuTodayFatigueChart(
                summary: presentation.todayFatigue,
                theme: presentation.theme,
                language: presentation.language,
                reduceTransparency: effectiveReduceTransparency
            )
            .equatable()
            .frame(height: 58)
            .accessibilityHidden(true)

        }
        .padding(11)
        .background {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(presentation.theme.style.surface.opacity(
                    effectiveReduceTransparency ? 1 : 0.72
                ))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(
                    presentation.theme.style.accent.opacity(
                        effectiveReduceTransparency ? 0.48 : 0.28
                    ),
                    lineWidth: 1
                )
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(presentation.todayOverviewAccessibilityLabel)
    }

    private var themedDivider: some View {
        Rectangle()
            .fill(
                presentation.theme.style.accent.opacity(
                    effectiveReduceTransparency ? 0.26 : 0.14
                )
            )
            .frame(height: 1)
            .accessibilityHidden(true)
    }

    private var effectiveReduceTransparency: Bool {
        reduceTransparencyOverride ?? reduceTransparency
    }

    private func localized(_ key: L10nKey) -> String {
        AppLocalization.string(key, language: presentation.language)
    }
}

private struct MenuTodayFatigueChart: View, Equatable {
    let summary: MenuTodayFatigueSummary
    let theme: ReminderTheme
    let language: AppLanguage
    let reduceTransparency: Bool

    var body: some View {
        let style = theme.style
        Group {
            if summary.visualPoints.isEmpty {
                Text(AppLocalization.string(
                    .analyticsChartEmptyTitle,
                    language: language
                ))
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(reduceTransparency ? 0.80 : 0.60))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Chart {
                    ForEach(summary.visualPoints) { point in
                        AreaMark(
                            x: .value("Time", point.timestamp),
                            yStart: .value("Threshold", 100),
                            yEnd: .value("Overload", max(100, point.fatigue))
                        )
                        .foregroundStyle(style.accent.opacity(
                            reduceTransparency ? 0.30 : 0.18
                        ))

                        if summary.visualPoints.count > 1 {
                            LineMark(
                                x: .value("Time", point.timestamp),
                                y: .value("Fatigue", point.fatigue)
                            )
                            .foregroundStyle(style.accentHighlight)
                            .lineStyle(StrokeStyle(
                                lineWidth: 2,
                                lineCap: .round,
                                lineJoin: .round
                            ))
                            .interpolationMethod(.linear)
                        }
                    }

                    RuleMark(y: .value("Rest Threshold", 100))
                        .foregroundStyle(style.accent.opacity(
                            reduceTransparency ? 0.82 : 0.52
                        ))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                        .annotation(position: .top, alignment: .leading) {
                            Text("100%")
                                .font(.system(size: 8, weight: .medium, design: .rounded))
                                .monospacedDigit()
                                .foregroundStyle(.white.opacity(
                                    reduceTransparency ? 0.78 : 0.54
                                ))
                        }

                    if let current = summary.visualPoints.last {
                        PointMark(
                            x: .value("Current Time", current.timestamp),
                            y: .value("Current Fatigue", current.fatigue)
                        )
                        .foregroundStyle(style.accentHighlight)
                        .symbolSize(22)
                    }
                }
                .chartYScale(domain: 0...summary.upperBound)
                .chartXAxis(.hidden)
                .chartYAxis(.hidden)
            }
        }
    }
}

private struct MenuContentBackground: View {
    let theme: ReminderTheme
    let reduceTransparency: Bool

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .top) {
                LinearGradient(
                    colors: [theme.style.panelTop, theme.style.panelBottom],
                    startPoint: .top,
                    endPoint: .bottom
                )

                if !reduceTransparency {
                    let treatment = theme.menuBackdropTreatment
                    let imageHeight = min(206, proxy.size.height)

                    Image(theme.previewAssetName)
                        .resizable()
                        .scaledToFill()
                        .frame(
                            width: proxy.size.width,
                            height: imageHeight,
                            alignment: treatment.imageAlignment
                        )
                        .saturation(treatment.saturation)
                        .contrast(treatment.contrast)
                        .brightness(treatment.brightness)
                        .clipped()
                        .overlay {
                            LinearGradient(
                                colors: [
                                    theme.style.panelTop.opacity(treatment.topWashOpacity),
                                    theme.style.backdrop.opacity(treatment.bottomWashOpacity)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        }
                        .opacity(treatment.imageOpacity)
                        .mask {
                            LinearGradient(
                                stops: [
                                    .init(color: .white, location: 0),
                                    .init(color: .white, location: 0.58),
                                    .init(color: .white.opacity(0.72), location: 0.78),
                                    .init(color: .clear, location: 1)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        }

                    RadialGradient(
                        colors: [
                            theme.style.accentHighlight.opacity(treatment.lightOpacity),
                            .clear
                        ],
                        center: treatment.lightCenter,
                        startRadius: 2,
                        endRadius: treatment.lightRadius
                    )
                    .frame(height: imageHeight)
                    .blendMode(.screen)
                    .mask {
                        LinearGradient(
                            colors: [.white, .white.opacity(0.42), .clear],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    }
                }
            }
        }
        .clipped()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

struct MenuThemeBackdropTreatment: Equatable {
    let imageAlignment: Alignment
    let imageOpacity: Double
    let saturation: Double
    let contrast: Double
    let brightness: Double
    let topWashOpacity: Double
    let bottomWashOpacity: Double
    let lightCenter: UnitPoint
    let lightOpacity: Double
    let lightRadius: CGFloat
}

extension ReminderTheme {
    var menuBackdropTreatment: MenuThemeBackdropTreatment {
        switch self {
        case .quietHorizon:
            MenuThemeBackdropTreatment(
                imageAlignment: .center,
                imageOpacity: 0.62,
                saturation: 0.80,
                contrast: 1.10,
                brightness: 0,
                topWashOpacity: 0.34,
                bottomWashOpacity: 0.54,
                lightCenter: .bottom,
                lightOpacity: 0.18,
                lightRadius: 176
            )
        case .forestLight:
            MenuThemeBackdropTreatment(
                imageAlignment: .top,
                imageOpacity: 0.72,
                saturation: 0.88,
                contrast: 1.18,
                brightness: 0.02,
                topWashOpacity: 0.24,
                bottomWashOpacity: 0.52,
                lightCenter: .top,
                lightOpacity: 0.24,
                lightRadius: 154
            )
        case .alpineMist:
            MenuThemeBackdropTreatment(
                imageAlignment: .trailing,
                imageOpacity: 0.60,
                saturation: 0.76,
                contrast: 1.08,
                brightness: -0.02,
                topWashOpacity: 0.32,
                bottomWashOpacity: 0.50,
                lightCenter: .topTrailing,
                lightOpacity: 0.19,
                lightRadius: 170
            )
        case .twilightDunes:
            MenuThemeBackdropTreatment(
                imageAlignment: .bottomTrailing,
                imageOpacity: 0.68,
                saturation: 0.92,
                contrast: 1.14,
                brightness: 0,
                topWashOpacity: 0.28,
                bottomWashOpacity: 0.48,
                lightCenter: .bottomTrailing,
                lightOpacity: 0.23,
                lightRadius: 164
            )
        case .mossGardenRain:
            MenuThemeBackdropTreatment(
                imageAlignment: .bottom,
                imageOpacity: 0.66,
                saturation: 0.72,
                contrast: 1.12,
                brightness: -0.04,
                topWashOpacity: 0.34,
                bottomWashOpacity: 0.58,
                lightCenter: .bottom,
                lightOpacity: 0.16,
                lightRadius: 160
            )
        case .polarNightGlow:
            MenuThemeBackdropTreatment(
                imageAlignment: .bottom,
                imageOpacity: 0.64,
                saturation: 0.70,
                contrast: 1.15,
                brightness: -0.05,
                topWashOpacity: 0.30,
                bottomWashOpacity: 0.56,
                lightCenter: .bottom,
                lightOpacity: 0.20,
                lightRadius: 180
            )
        case .moonlitBamboo:
            MenuThemeBackdropTreatment(
                imageAlignment: .top,
                imageOpacity: 0.70,
                saturation: 0.78,
                contrast: 1.16,
                brightness: -0.04,
                topWashOpacity: 0.26,
                bottomWashOpacity: 0.56,
                lightCenter: .top,
                lightOpacity: 0.18,
                lightRadius: 150
            )
        case .rainwashedSeaCliff:
            MenuThemeBackdropTreatment(
                imageAlignment: .bottom,
                imageOpacity: 0.58,
                saturation: 0.74,
                contrast: 1.14,
                brightness: -0.08,
                topWashOpacity: 0.42,
                bottomWashOpacity: 0.60,
                lightCenter: .bottom,
                lightOpacity: 0.12,
                lightRadius: 174
            )
        case .cloudfieldWind:
            MenuThemeBackdropTreatment(
                imageAlignment: .bottom,
                imageOpacity: 0.62,
                saturation: 0.66,
                contrast: 1.10,
                brightness: -0.05,
                topWashOpacity: 0.30,
                bottomWashOpacity: 0.58,
                lightCenter: .bottom,
                lightOpacity: 0.15,
                lightRadius: 168
            )
        }
    }
}

private struct MenuRestButtonStyle: ButtonStyle {
    let style: ReminderThemeStyle
    let isPrimary: Bool
    let reduceTransparency: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold, design: .rounded))
            .foregroundStyle(isPrimary ? style.backdrop.opacity(0.98) : .white.opacity(0.84))
            .frame(maxWidth: .infinity, minHeight: 40)
            .background {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(fillStyle)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(borderColor, lineWidth: 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .opacity(configuration.isPressed ? 0.78 : 1)
    }

    private var fillStyle: AnyShapeStyle {
        if isPrimary {
            return AnyShapeStyle(
                LinearGradient(
                    colors: [style.accentHighlight, style.accent],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        }
        return AnyShapeStyle(style.surface.opacity(reduceTransparency ? 1 : 0.72))
    }

    private var borderColor: Color {
        isPrimary
            ? .white.opacity(reduceTransparency ? 0.24 : 0.14)
            : style.accent.opacity(reduceTransparency ? 0.80 : 0.56)
    }
}

private struct MenuActionButton: View {
    let title: String
    let systemImage: String
    let style: ReminderThemeStyle
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .foregroundStyle(style.accent)
                    .frame(width: 16)
                    .accessibilityHidden(true)

                Text(title)

                Spacer(minLength: 0)
            }
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.white.opacity(0.84))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(style.surface.opacity(isHovering ? 0.84 : 0))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .accessibilityLabel(title)
    }
}
