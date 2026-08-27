import Charts
import SwiftUI

struct DashboardView: View {
    @ObservedObject var model: AppModel
    @State private var range: DashboardRange = .today

    var body: some View {
        DashboardScene(
            presentation: presentation,
            range: $range
        )
        .onAppear(perform: model.refreshAnalytics)
    }

    private var presentation: DashboardPresentation {
        let calendar = Calendar.current
        let metrics = range == .today ? model.analytics.today : model.analytics.week
        let fatiguePoints = model.analytics.fatiguePoints
            .filter { range == .week || calendar.isDateInToday($0.timestamp) }
            .map {
                DashboardFatiguePoint(timestamp: $0.timestamp, fatigue: $0.fatigue)
            }
        let cutoff = calendar.date(
            byAdding: .day,
            value: -6,
            to: calendar.startOfDay(for: Date())
        ) ?? .distantPast
        let dailyPoints = model.analytics.dailyPoints
            .filter { $0.date >= cutoff }
            .map {
                DashboardDailyPoint(
                    date: $0.date,
                    peakFatigue: $0.peakFatigue,
                    overloadDuration: $0.overloadDuration,
                    longestUsageDuration: $0.longestUsageDuration
                )
            }

        return DashboardPresentation(
            range: range,
            language: model.resolvedLanguage,
            theme: model.reminderTheme,
            currentFatigue: model.fatigue,
            currentFatigueDisplay: model.fatigueDisplay,
            currentStatus: model.restRequired
                ? AppLocalization.string(
                    .analyticsWaitingForRest,
                    language: model.resolvedLanguage
                )
                : model.presenceDescription,
            fatiguePoints: fatiguePoints,
            dailyPoints: dailyPoints,
            metrics: DashboardMetrics(metrics),
            sources: DashboardRestSources(metrics)
        )
    }
}

enum DashboardRange: String, CaseIterable, Identifiable {
    case today
    case week

    var id: Self { self }

    func title(language: AppLanguage = .zhHans) -> String {
        AppLocalization.string(
            self == .today ? .analyticsRangeToday : .analyticsRangeWeek,
            language: language
        )
    }
}

struct DashboardFatiguePoint: Identifiable, Equatable {
    let timestamp: Date
    let fatigue: Double

    var id: Date { timestamp }
}

struct DashboardDailyPoint: Identifiable, Equatable {
    let date: Date
    let peakFatigue: Double
    let overloadDuration: TimeInterval
    let longestUsageDuration: TimeInterval

    var id: Date { date }
}

struct DashboardMetrics: Equatable {
    let peakFatigue: Double
    let overloadDuration: TimeInterval
    let longestUsageDuration: TimeInterval
    let completedRestCount: Int
    let interruptedRestCount: Int
    let averageResponseDuration: TimeInterval?

    init(
        peakFatigue: Double,
        overloadDuration: TimeInterval,
        longestUsageDuration: TimeInterval,
        completedRestCount: Int,
        interruptedRestCount: Int,
        averageResponseDuration: TimeInterval?
    ) {
        self.peakFatigue = peakFatigue
        self.overloadDuration = overloadDuration
        self.longestUsageDuration = longestUsageDuration
        self.completedRestCount = completedRestCount
        self.interruptedRestCount = interruptedRestCount
        self.averageResponseDuration = averageResponseDuration
    }

    init(_ metrics: AnalyticsMetrics) {
        self.init(
            peakFatigue: metrics.peakFatigue,
            overloadDuration: metrics.overloadDuration,
            longestUsageDuration: metrics.longestUsageDuration,
            completedRestCount: metrics.completedRestCount,
            interruptedRestCount: metrics.interruptedRestCount,
            averageResponseDuration: metrics.averageResponseDuration
        )
    }
}

struct DashboardRestSources: Equatable {
    let manual: Int
    let system: Int
    let inactivity: Int
    let deferred: Int

    init(manual: Int, system: Int, inactivity: Int, deferred: Int) {
        self.manual = manual
        self.system = system
        self.inactivity = inactivity
        self.deferred = deferred
    }

    init(_ metrics: AnalyticsMetrics) {
        self.init(
            manual: metrics.manualRestCount,
            system: metrics.systemRestCount,
            inactivity: metrics.inactivityRestCount,
            deferred: metrics.continuedWorkingCount
        )
    }
}

struct DashboardPresentation: Equatable {
    let range: DashboardRange
    let language: AppLanguage
    let theme: ReminderTheme
    let currentFatigue: Double
    let currentFatigueDisplay: String
    let currentStatus: String
    let fatiguePoints: [DashboardFatiguePoint]
    let dailyPoints: [DashboardDailyPoint]
    let metrics: DashboardMetrics
    let sources: DashboardRestSources

    var hasTrendData: Bool {
        switch range {
        case .today:
            return fatiguePoints.contains { $0.fatigue > 0 }
        case .week:
            return dailyPoints.contains {
                $0.peakFatigue > 0
                    || $0.overloadDuration > 0
                    || $0.longestUsageDuration > 0
            }
        }
    }

    var restAttemptCount: Int {
        metrics.completedRestCount + metrics.interruptedRestCount
    }

    var peakDisplay: String {
        FatigueValueFormatter.display(metrics.peakFatigue)
    }

    var peakMetricDisplay: String {
        metrics.peakFatigue > 0
            ? peakDisplay
            : localized(.analyticsMetricPeakFatigueZero)
    }

    var overloadDisplay: String {
        EyeDurationFormatter.compact(metrics.overloadDuration, language: language)
    }

    var overloadMetricDisplay: String {
        metrics.overloadDuration > 0
            ? overloadDisplay
            : localized(.analyticsMetricOverloadDurationZero)
    }

    var longestUsageDisplay: String {
        EyeDurationFormatter.compact(metrics.longestUsageDuration, language: language)
    }

    var longestUsageMetricDisplay: String {
        metrics.longestUsageDuration > 0
            ? longestUsageDisplay
            : localized(.analyticsMetricLongestUsageZero)
    }

    var averageResponseDisplay: String {
        guard let duration = metrics.averageResponseDuration else {
            return localized(.analyticsMetricAverageResponseNoData)
        }
        return EyeDurationFormatter.compact(duration, language: language)
    }

    var restRatioDisplay: String {
        guard restAttemptCount > 0 else {
            return localized(.analyticsRestNoAttempts)
        }
        return AppLocalization.format(
            .analyticsRestCompletedRatio,
            language: language,
            arguments: [metrics.completedRestCount, restAttemptCount]
        )
    }

    var summaryAccessibilityLabel: String {
        return AppLocalization.format(
            .analyticsSummaryAccessibility,
            language: language,
            arguments: [
                currentFatigueDisplay,
                peakMetricDisplay,
                overloadMetricDisplay,
                longestUsageMetricDisplay
            ]
        )
    }

    var trendAccessibilityLabel: String {
        guard hasTrendData else {
            return "\(zeroTitle). \(zeroDescription)"
        }
        return AppLocalization.format(
            range == .today
                ? .analyticsChartTodayAccessibility
                : .analyticsChartWeekAccessibility,
            language: language,
            arguments: [
                range == .today ? fatiguePoints.count : dailyPoints.count,
                peakDisplay,
                overloadDisplay
            ]
        )
    }

    var restAccessibilityLabel: String {
        guard restAttemptCount > 0 else {
            return localized(.analyticsRestSummaryAccessibilityEmpty)
        }
        return AppLocalization.format(
            .analyticsRestSummaryAccessibility,
            language: language,
            arguments: [
                metrics.completedRestCount,
                restAttemptCount,
                averageResponseDisplay
            ]
        )
    }

    var trendTitle: String {
        localized(range == .today ? .analyticsTrendTodayTitle : .analyticsTrendWeekTitle)
    }

    var trendSubtitle: String {
        localized(range == .today ? .analyticsTrendTodaySubtitle : .analyticsTrendWeekSubtitle)
    }

    var zeroTitle: String {
        localized(range == .today ? .analyticsZeroTodayTitle : .analyticsZeroWeekTitle)
    }

    var zeroDescription: String {
        localized(
            range == .today
                ? .analyticsZeroTodayDescription
                : .analyticsZeroWeekDescription
        )
    }

    func localized(_ key: L10nKey) -> String {
        AppLocalization.string(key, language: language)
    }

    func weekdayDisplay(for date: Date) -> String {
        date.formatted(
            .dateTime
                .weekday(.narrow)
                .locale(dateLocale)
        )
    }

    func hoverDateDisplay(for date: Date) -> String {
        date.formatted(
            .dateTime
                .month()
                .day()
                .weekday(.abbreviated)
                .locale(dateLocale)
        )
    }

    private var dateLocale: Locale {
        Locale(identifier: language == .zhHans ? "zh_CN" : "en_US")
    }
}

struct DashboardScene: View {
    let presentation: DashboardPresentation
    @Binding var range: DashboardRange
    var accessibilityOverrides: DashboardAccessibilityOverrides = .system
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                metricSummary
                trendCard
                restSummary
                disclaimer
            }
            .padding(26)
            .frame(maxWidth: 980, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .frame(minWidth: 760, idealWidth: 900, minHeight: 560, idealHeight: 720)
        .background(Color(nsColor: .windowBackgroundColor))
        .environment(\.locale, dashboardLocale)
        .environment(\.dashboardReduceTransparency, effectiveReduceTransparency)
        .environment(\.dashboardColorSchemeContrast, effectiveColorSchemeContrast)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image("MenuBarTaiji")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .foregroundStyle(dashboardAccent)
                .frame(width: 28, height: 28)
                .accessibilityHidden(true)

            Text(presentation.localized(.analyticsTitle))
                .font(.system(size: 25, weight: .bold, design: .rounded))

            Divider()
                .frame(height: 28)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(presentation.localized(.analyticsCurrentFatigue))
                        .foregroundStyle(.primary.opacity(0.72))
                    Text(presentation.currentFatigueDisplay)
                        .fontWeight(.semibold)
                        .monospacedDigit()
                        .foregroundStyle(dashboardAccent)
                }

                Text(presentation.currentStatus)
                    .foregroundStyle(.primary.opacity(0.72))
                    .lineLimit(1)
            }
            .font(.subheadline)
            .accessibilityElement(children: .combine)

            Spacer(minLength: 18)

            Picker(presentation.localized(.analyticsRangeLabel), selection: $range) {
                ForEach(DashboardRange.allCases) { item in
                    Text(item.title(language: presentation.language)).tag(item)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 190)
        }
    }

    private var metricSummary: some View {
        HStack(spacing: 12) {
            DashboardPrimaryMetricCard(presentation: presentation)
                .frame(maxWidth: .infinity)

            DashboardSupportingMetricCard(
                title: presentation.localized(.analyticsMetricPeakFatigueTitle),
                value: presentation.peakMetricDisplay,
                symbol: "chart.line.uptrend.xyaxis",
                accent: dashboardAccent
            )

            DashboardSupportingMetricCard(
                title: presentation.localized(.analyticsMetricLongestUsageTitle),
                value: presentation.longestUsageMetricDisplay,
                symbol: "timer",
                accent: dashboardAccent
            )
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(presentation.summaryAccessibilityLabel)
    }

    private var trendCard: some View {
        DashboardCard {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(presentation.trendTitle)
                        .font(.headline)
                    Text(presentation.trendSubtitle)
                        .font(.subheadline)
                        .foregroundStyle(.primary.opacity(0.72))
                }

                if presentation.hasTrendData {
                    switch presentation.range {
                    case .today:
                        DashboardTodayChart(presentation: presentation)
                    case .week:
                        DashboardWeekChart(presentation: presentation)
                    }
                } else {
                    DashboardPositiveZeroState(presentation: presentation)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(presentation.trendAccessibilityLabel)
    }

    private var restSummary: some View {
        DashboardCard {
            VStack(alignment: .leading, spacing: 14) {
                Text(presentation.localized(.analyticsRestSummaryTitle))
                    .font(.headline)

                HStack(spacing: 0) {
                    DashboardRestMetric(
                        value: presentation.restRatioDisplay,
                        title: presentation.localized(.analyticsRestCompletedRatioCaption)
                    )

                    Divider()
                        .frame(height: 42)
                        .padding(.horizontal, 28)

                    DashboardRestMetric(
                        value: presentation.averageResponseDisplay,
                        title: presentation.localized(.analyticsMetricAverageResponseTitle)
                    )

                    Spacer(minLength: 0)
                }

                Divider()

                VStack(alignment: .leading, spacing: 10) {
                    Text(presentation.localized(.analyticsRestSourcesTitle))
                        .font(.subheadline.weight(.semibold))
                        .accessibilityAddTraits(.isHeader)

                    LazyVGrid(
                        columns: [
                            GridItem(.flexible(), spacing: 10),
                            GridItem(.flexible(), spacing: 10)
                        ],
                        spacing: 10
                    ) {
                        DashboardSourceRow(
                            title: presentation.localized(.analyticsEvidenceManualRest),
                            count: presentation.sources.manual,
                            symbol: "hand.tap.fill",
                            presentation: presentation
                        )
                        DashboardSourceRow(
                            title: presentation.localized(.analyticsEvidenceLockOrSleep),
                            count: presentation.sources.system,
                            symbol: "moon.zzz.fill",
                            presentation: presentation
                        )
                        DashboardSourceRow(
                            title: presentation.localized(.analyticsEvidenceInactivityRest),
                            count: presentation.sources.inactivity,
                            symbol: "keyboard.badge.ellipsis",
                            presentation: presentation
                        )
                        DashboardSourceRow(
                            title: presentation.localized(.analyticsEvidenceDeferredRest),
                            count: presentation.sources.deferred,
                            symbol: "arrow.right.circle.fill",
                            presentation: presentation
                        )
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(presentation.restAccessibilityLabel)
    }

    private var disclaimer: some View {
        Label(
            presentation.localized(.analyticsDisclaimer),
            systemImage: "info.circle"
        )
        .font(.caption.weight(.medium))
        .foregroundStyle(.primary.opacity(0.68))
        .padding(.horizontal, 2)
    }

    private var dashboardLocale: Locale {
        Locale(identifier: presentation.language == .zhHans ? "zh_CN" : "en_US")
    }

    private var dashboardAccent: Color {
        presentation.theme.dashboardAccent(
            colorScheme: colorScheme,
            contrast: effectiveColorSchemeContrast
        )
    }

    private var effectiveReduceTransparency: Bool {
        accessibilityOverrides.reduceTransparency ?? reduceTransparency
    }

    private var effectiveColorSchemeContrast: ColorSchemeContrast {
        accessibilityOverrides.colorSchemeContrast ?? colorSchemeContrast
    }
}

struct DashboardAccessibilityOverrides {
    static let system = DashboardAccessibilityOverrides()

    var reduceTransparency: Bool?
    var colorSchemeContrast: ColorSchemeContrast?
}

private struct DashboardReduceTransparencyKey: EnvironmentKey {
    static let defaultValue = false
}

private struct DashboardColorSchemeContrastKey: EnvironmentKey {
    static let defaultValue: ColorSchemeContrast = .standard
}

private extension EnvironmentValues {
    var dashboardReduceTransparency: Bool {
        get { self[DashboardReduceTransparencyKey.self] }
        set { self[DashboardReduceTransparencyKey.self] = newValue }
    }

    var dashboardColorSchemeContrast: ColorSchemeContrast {
        get { self[DashboardColorSchemeContrastKey.self] }
        set { self[DashboardColorSchemeContrastKey.self] = newValue }
    }
}

private struct DashboardPrimaryMetricCard: View {
    let presentation: DashboardPresentation
    @Environment(\.dashboardReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dashboardColorSchemeContrast) private var colorSchemeContrast

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: "waveform.path.ecg")
                .font(.system(size: 25, weight: .semibold))
                .foregroundStyle(dashboardAccent)
                .frame(width: 36, height: 36)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(presentation.localized(.analyticsMetricOverloadDurationTitle))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary.opacity(0.72))

                Text(presentation.overloadMetricDisplay)
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(dashboardAccent)
                    .lineLimit(1)
                    .minimumScaleFactor(0.52)

                Text(presentation.localized(.analyticsMetricOverloadDurationDetail))
                    .font(.subheadline)
                    .foregroundStyle(.primary.opacity(0.72))
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .padding(18)
        .frame(minWidth: 300, minHeight: 112, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: primaryCardColors,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        }
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(
                    dashboardAccent.opacity(
                        colorSchemeContrast == .increased ? 0.72 : 0.40
                    ),
                    lineWidth: colorSchemeContrast == .increased ? 1.5 : 1
                )
        }
    }

    private var dashboardAccent: Color {
        presentation.theme.dashboardAccent(
            colorScheme: colorScheme,
            contrast: colorSchemeContrast
        )
    }

    private var primaryCardColors: [Color] {
        if reduceTransparency {
            return [
                Color(nsColor: .controlBackgroundColor),
                Color(nsColor: .controlBackgroundColor)
            ]
        }
        if colorScheme == .light {
            return [dashboardAccent.opacity(0.10), dashboardAccent.opacity(0.025)]
        }
        return [
            presentation.theme.style.surface.opacity(0.22),
            presentation.theme.style.accent.opacity(0.08)
        ]
    }
}

private struct DashboardSupportingMetricCard: View {
    let title: String
    let value: String
    let symbol: String
    let accent: Color
    @Environment(\.dashboardColorSchemeContrast) private var colorSchemeContrast

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(accent)

            Spacer(minLength: 0)

            Text(value)
                .font(.system(size: 21, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.72)

            Text(title)
                .font(.subheadline)
                .foregroundStyle(.primary.opacity(0.72))
                .lineLimit(1)
        }
        .padding(16)
        .frame(width: 184, alignment: .leading)
        .frame(minHeight: 112, alignment: .leading)
        .background(
            Color(nsColor: .controlBackgroundColor),
            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(
                    colorSchemeContrast == .increased ? .secondary : .quaternary,
                    lineWidth: colorSchemeContrast == .increased ? 1.5 : 1
                )
        }
    }
}

private struct DashboardTodayChart: View {
    let presentation: DashboardPresentation
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dashboardColorSchemeContrast) private var colorSchemeContrast

    var body: some View {
        Chart {
            ForEach(presentation.fatiguePoints) { point in
                AreaMark(
                    x: .value(
                        presentation.localized(.analyticsChartAxisTime),
                        point.timestamp
                    ),
                    yStart: .value(
                        presentation.localized(.analyticsChartThreshold),
                        100
                    ),
                    yEnd: .value(
                        presentation.localized(.analyticsChartOverloadZone),
                        max(100, point.fatigue)
                    )
                )
                .foregroundStyle(
                    chartAccent.opacity(
                        colorSchemeContrast == .increased ? 0.28 : 0.18
                    )
                )

                LineMark(
                    x: .value(
                        presentation.localized(.analyticsChartAxisTime),
                        point.timestamp
                    ),
                    y: .value(
                        presentation.localized(.analyticsChartAxisFatigue),
                        point.fatigue
                    )
                )
                .foregroundStyle(chartAccent)
                .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                .interpolationMethod(.catmullRom)
            }

            RuleMark(y: .value(presentation.localized(.analyticsChartRestLine), 100))
                .foregroundStyle(chartAccent.opacity(0.72))
                .lineStyle(StrokeStyle(lineWidth: 1.25, dash: [4, 5]))
        }
        .chartYScale(domain: 0...todayUpperBound)
        .chartYAxis {
            AxisMarks(position: .leading, values: [0, 100, todayUpperBound]) { value in
                AxisGridLine().foregroundStyle(chartGridColor)
                AxisValueLabel {
                    if let number = value.as(Double.self) {
                        Text(AppLocalization.fatiguePercent(
                            number,
                            language: presentation.language
                        ))
                        .foregroundStyle(chartAxisLabelColor)
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 5)) { _ in
                AxisGridLine().foregroundStyle(chartGridColor.opacity(0.72))
                AxisValueLabel(format: .dateTime.hour().minute())
                    .foregroundStyle(chartAxisLabelColor)
            }
        }
        .frame(height: 230)
    }

    private var todayUpperBound: Double {
        max(120, ceil((presentation.fatiguePoints.map(\.fatigue).max() ?? 100) / 20) * 20)
    }

    private var chartAccent: Color {
        presentation.theme.dashboardAccent(
            colorScheme: colorScheme,
            contrast: colorSchemeContrast
        )
    }

    private var chartAxisLabelColor: Color {
        Color(nsColor: .labelColor).opacity(
            colorSchemeContrast == .increased ? 0.92 : 0.68
        )
    }

    private var chartGridColor: Color {
        Color(nsColor: .separatorColor).opacity(
            colorSchemeContrast == .increased ? 1 : 0.62
        )
    }
}

private struct DashboardWeekChart: View {
    let presentation: DashboardPresentation
    @State private var hoveredPoint: DashboardDailyPoint?
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dashboardColorSchemeContrast) private var colorSchemeContrast

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 18) {
                DashboardChartLegend(
                    title: presentation.localized(.analyticsTrendWeekOverloadTitle),
                    color: chartAccent.opacity(0.62),
                    isLine: false
                )
                DashboardChartLegend(
                    title: presentation.localized(.analyticsTrendWeekPeakTitle),
                    color: chartAccent,
                    isLine: true
                )
            }

            Chart {
                ForEach(presentation.dailyPoints) { point in
                    BarMark(
                        x: .value(
                            presentation.localized(.analyticsChartAxisDate),
                            point.date,
                            unit: .day
                        ),
                        y: .value(
                            presentation.localized(.analyticsMetricOverloadDurationTitle),
                            overloadBarHeight(for: point)
                        )
                    )
                    .foregroundStyle(
                        chartAccent.opacity(colorSchemeContrast == .increased ? 0.52 : 0.38)
                    )
                    .cornerRadius(5)

                    LineMark(
                        x: .value(
                            presentation.localized(.analyticsChartAxisDate),
                            point.date,
                            unit: .day
                        ),
                        y: .value(
                            presentation.localized(.analyticsChartDailyPeak),
                            point.peakFatigue
                        )
                    )
                    .foregroundStyle(chartAccent)
                    .lineStyle(StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round))

                    PointMark(
                        x: .value(
                            presentation.localized(.analyticsChartAxisDate),
                            point.date,
                            unit: .day
                        ),
                        y: .value(
                            presentation.localized(.analyticsChartDailyPeak),
                            point.peakFatigue
                        )
                    )
                    .foregroundStyle(chartAccent)
                    .symbolSize(30)
                }

                RuleMark(y: .value(presentation.localized(.analyticsChartRestLine), 100))
                    .foregroundStyle(chartAccent.opacity(0.68))
                    .lineStyle(StrokeStyle(lineWidth: 1.25, dash: [4, 5]))

                if let hoveredPoint {
                    RuleMark(
                        x: .value(
                            presentation.localized(.analyticsChartAxisDate),
                            hoveredPoint.date,
                            unit: .day
                        )
                    )
                    .foregroundStyle(.secondary.opacity(0.5))
                    .lineStyle(StrokeStyle(lineWidth: 1))
                }
            }
            .chartYScale(domain: 0...weekPeakUpperBound)
            .chartYAxis {
                AxisMarks(position: .leading, values: [0, 100, weekPeakUpperBound]) { value in
                    AxisGridLine().foregroundStyle(chartGridColor)
                    AxisValueLabel {
                        if let number = value.as(Double.self) {
                            Text(AppLocalization.fatiguePercent(
                                number,
                                language: presentation.language
                            ))
                            .foregroundStyle(chartAxisLabelColor)
                        }
                    }
                }

                AxisMarks(position: .trailing, values: overloadAxisPositions) { value in
                    AxisValueLabel {
                        if let scaledHeight = value.as(Double.self) {
                            Text(EyeDurationFormatter.compact(
                                overloadDuration(forScaledHeight: scaledHeight),
                                language: presentation.language
                            ))
                            .foregroundStyle(chartAccent)
                        }
                    }
                }
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .day)) { value in
                    AxisValueLabel {
                        if let date = value.as(Date.self) {
                            Text(presentation.weekdayDisplay(for: date))
                                .foregroundStyle(chartAxisLabelColor)
                        }
                    }
                }
            }
            .chartOverlay { proxy in
                GeometryReader { geometry in
                    Rectangle()
                        .fill(.clear)
                        .contentShape(Rectangle())
                        .onContinuousHover { phase in
                            updateHover(phase, proxy: proxy, geometry: geometry)
                        }
                }
            }
            .overlay(alignment: .topTrailing) {
                if let hoveredPoint {
                    DashboardWeekHoverCard(
                        point: hoveredPoint,
                        presentation: presentation
                    )
                    .padding(8)
                    .allowsHitTesting(false)
                }
            }
            .frame(height: 230)
        }
    }

    private var weekPeakUpperBound: Double {
        max(120, ceil((presentation.dailyPoints.map(\.peakFatigue).max() ?? 100) / 20) * 20)
    }

    private var maximumOverloadDuration: TimeInterval {
        presentation.dailyPoints.map(\.overloadDuration).max() ?? 0
    }

    private var chartAccent: Color {
        presentation.theme.dashboardAccent(
            colorScheme: colorScheme,
            contrast: colorSchemeContrast
        )
    }

    private var chartAxisLabelColor: Color {
        Color(nsColor: .labelColor).opacity(
            colorSchemeContrast == .increased ? 0.92 : 0.68
        )
    }


    private var chartGridColor: Color {
        Color(nsColor: .separatorColor).opacity(
            colorSchemeContrast == .increased ? 1 : 0.62
        )
    }

    private var maximumOverloadBarHeight: Double {
        weekPeakUpperBound * 0.72
    }

    private var overloadAxisPositions: [Double] {
        guard maximumOverloadDuration > 0 else { return [] }
        return [0, maximumOverloadBarHeight / 2, maximumOverloadBarHeight]
    }

    private func overloadBarHeight(for point: DashboardDailyPoint) -> Double {
        guard maximumOverloadDuration > 0 else { return 0 }
        return point.overloadDuration / maximumOverloadDuration * maximumOverloadBarHeight
    }

    private func overloadDuration(forScaledHeight scaledHeight: Double) -> TimeInterval {
        guard maximumOverloadBarHeight > 0 else { return 0 }
        return scaledHeight / maximumOverloadBarHeight * maximumOverloadDuration
    }

    private func updateHover(
        _ phase: HoverPhase,
        proxy: ChartProxy,
        geometry: GeometryProxy
    ) {
        switch phase {
        case let .active(location):
            guard let plotFrame = proxy.plotFrame else {
                hoveredPoint = nil
                return
            }
            let frame = geometry[plotFrame]
            guard frame.contains(location),
                  let date: Date = proxy.value(atX: location.x - frame.minX) else {
                hoveredPoint = nil
                return
            }
            hoveredPoint = presentation.dailyPoints.min {
                abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date))
            }
        case .ended:
            hoveredPoint = nil
        }
    }
}

private struct DashboardChartLegend: View {
    let title: String
    let color: Color
    let isLine: Bool

    var body: some View {
        HStack(spacing: 6) {
            if isLine {
                Capsule()
                    .fill(color)
                    .frame(width: 18, height: 2)
            } else {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(color)
                    .frame(width: 10, height: 10)
            }
            Text(title)
        }
        .font(.subheadline.weight(.medium))
        .foregroundStyle(.primary)
    }
}

private struct DashboardWeekHoverCard: View {
    let point: DashboardDailyPoint
    let presentation: DashboardPresentation
    @Environment(\.dashboardReduceTransparency) private var reduceTransparency

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(presentation.hoverDateDisplay(for: point.date))
                .font(.caption.weight(.semibold))
            Text(
                "\(presentation.localized(.analyticsTrendWeekPeakTitle)): "
                    + AppLocalization.fatiguePercent(
                        point.peakFatigue,
                        language: presentation.language
                    )
            )
            Text(
                "\(presentation.localized(.analyticsTrendWeekOverloadTitle)): "
                    + EyeDurationFormatter.compact(
                        point.overloadDuration,
                        language: presentation.language
                    )
            )
        }
        .font(.caption)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            reduceTransparency
                ? AnyShapeStyle(Color(nsColor: .windowBackgroundColor))
                : AnyShapeStyle(.regularMaterial),
            in: RoundedRectangle(cornerRadius: 9, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(.quaternary, lineWidth: 1)
        }
    }
}

private struct DashboardPositiveZeroState: View {
    let presentation: DashboardPresentation
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dashboardColorSchemeContrast) private var colorSchemeContrast

    var body: some View {
        VStack(spacing: 8) {
            Image("MenuBarTaiji")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .foregroundStyle(dashboardAccent.opacity(0.90))
                .frame(width: 30, height: 30)
                .accessibilityHidden(true)

            Text(presentation.zeroTitle)
                .font(.headline)

            Text(presentation.zeroDescription)
                .font(.subheadline)
                .foregroundStyle(.primary.opacity(0.72))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, minHeight: 210)
    }

    private var dashboardAccent: Color {
        presentation.theme.dashboardAccent(
            colorScheme: colorScheme,
            contrast: colorSchemeContrast
        )
    }
}

private struct DashboardRestMetric: View {
    let value: String
    let title: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value)
                .font(.system(size: 22, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.primary.opacity(0.72))
                .lineLimit(1)
        }
    }
}

private struct DashboardSourceRow: View {
    let title: String
    let count: Int
    let symbol: String
    let presentation: DashboardPresentation
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dashboardColorSchemeContrast) private var colorSchemeContrast

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .foregroundStyle(dashboardAccent)
                .frame(width: 18)
                .accessibilityHidden(true)
            Text(title)
                .foregroundStyle(.primary)
            Spacer(minLength: 8)
            Text(AppLocalization.times(count, language: presentation.language))
                .monospacedDigit()
        }
        .font(.subheadline)
        .padding(10)
        .background(.quinary, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "\(title), \(AppLocalization.times(count, language: presentation.language))"
        )
    }

    private var dashboardAccent: Color {
        presentation.theme.dashboardAccent(
            colorScheme: colorScheme,
            contrast: colorSchemeContrast
        )
    }
}

private struct DashboardCard<Content: View>: View {
    @ViewBuilder let content: Content
    @Environment(\.dashboardColorSchemeContrast) private var colorSchemeContrast

    var body: some View {
        content
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                Color(nsColor: .controlBackgroundColor),
                in: RoundedRectangle(cornerRadius: 18, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(
                        colorSchemeContrast == .increased ? .secondary : .quaternary,
                        lineWidth: colorSchemeContrast == .increased ? 1.5 : 1
                    )
            }
    }
}

private extension ReminderTheme {
    func dashboardAccent(
        colorScheme: ColorScheme,
        contrast: ColorSchemeContrast
    ) -> Color {
        guard colorScheme == .light else {
            return style.accentHighlight
        }

        let color: Color = switch self {
        case .quietHorizon:
            Color(red: 0.070, green: 0.390, blue: 0.335)
        case .forestLight:
            Color(red: 0.090, green: 0.370, blue: 0.245)
        case .alpineMist:
            Color(red: 0.155, green: 0.330, blue: 0.500)
        case .twilightDunes:
            Color(red: 0.430, green: 0.275, blue: 0.085)
        case .mossGardenRain:
            Color(red: 63.0 / 255.0, green: 91.0 / 255.0, blue: 45.0 / 255.0)
        case .polarNightGlow:
            Color(red: 59.0 / 255.0, green: 87.0 / 255.0, blue: 135.0 / 255.0)
        case .moonlitBamboo:
            Color(red: 44.0 / 255.0, green: 98.0 / 255.0, blue: 86.0 / 255.0)
        case .rainwashedSeaCliff:
            Color(red: 44.0 / 255.0, green: 99.0 / 255.0, blue: 112.0 / 255.0)
        case .cloudfieldWind:
            Color(red: 70.0 / 255.0, green: 95.0 / 255.0, blue: 107.0 / 255.0)
        }

        guard contrast == .increased else { return color }
        return switch self {
        case .quietHorizon:
            Color(red: 0.035, green: 0.285, blue: 0.245)
        case .forestLight:
            Color(red: 0.045, green: 0.275, blue: 0.175)
        case .alpineMist:
            Color(red: 0.090, green: 0.245, blue: 0.405)
        case .twilightDunes:
            Color(red: 0.325, green: 0.190, blue: 0.035)
        case .mossGardenRain:
            Color(red: 46.0 / 255.0, green: 67.0 / 255.0, blue: 31.0 / 255.0)
        case .polarNightGlow:
            Color(red: 40.0 / 255.0, green: 62.0 / 255.0, blue: 101.0 / 255.0)
        case .moonlitBamboo:
            Color(red: 29.0 / 255.0, green: 73.0 / 255.0, blue: 63.0 / 255.0)
        case .rainwashedSeaCliff:
            Color(red: 28.0 / 255.0, green: 72.0 / 255.0, blue: 84.0 / 255.0)
        case .cloudfieldWind:
            Color(red: 50.0 / 255.0, green: 71.0 / 255.0, blue: 82.0 / 255.0)
        }
    }
}
