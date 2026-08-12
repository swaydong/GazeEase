import Charts
import SwiftUI

struct DashboardView: View {
    @ObservedObject var model: AppModel
    @State private var range: DashboardRange = .today

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                currentFatigueCard
                fatigueChart
                metricGrid
                evidenceCard
            }
            .padding(28)
        }
        .frame(minWidth: 760, idealWidth: 900, minHeight: 620, idealHeight: 720)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear(perform: model.refreshAnalytics)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text(localized(.analyticsTitle))
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                Text(localized(.analyticsDisclaimer))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Picker(localized(.analyticsRangeLabel), selection: $range) {
                ForEach(DashboardRange.allCases) { item in
                    Text(item.title(language: language)).tag(item)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 180)
        }
    }

    private var currentFatigueCard: some View {
        HStack(spacing: 22) {
            ZStack {
                Circle()
                    .fill(EyePalette.fatigueColor(model.fatigue).opacity(0.12))
                Image(systemName: "eye.fill")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(EyePalette.fatigueColor(model.fatigue))
            }
            .frame(width: 72, height: 72)

            VStack(alignment: .leading, spacing: 5) {
                Text(localized(.analyticsCurrentFatigue))
                    .foregroundStyle(.secondary)
                Text(model.fatigueDisplay)
                    .font(.system(size: 38, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(EyePalette.fatigueColor(model.fatigue))
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 5) {
                Text(model.restRequired ? localized(.analyticsWaitingForRest) : model.presenceDescription)
                    .font(.headline)
                Text(model.restRequired
                     ? AppLocalization.format(
                        .analyticsOverloadSince,
                        language: language,
                        arguments: [EyeDurationFormatter.compact(
                            model.overloadDuration,
                            language: language
                        )]
                     )
                     : AppLocalization.format(
                        .analyticsRestFrequency,
                        language: language,
                        arguments: [model.workMinutes]
                     ))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(22)
        .background(.background, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(.quaternary, lineWidth: 1)
        }
    }

    private var fatigueChart: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(localized(.analyticsChartTitle))
                    .font(.headline)
                Spacer()
                Label(localized(.analyticsChartThreshold), systemImage: "line.diagonal")
                    .font(.caption)
                    .foregroundStyle(EyePalette.overdue)
            }

            if visibleFatiguePoints.isEmpty {
                ContentUnavailableView(
                    localized(.analyticsChartEmptyTitle),
                    systemImage: "chart.xyaxis.line",
                    description: Text(localized(.analyticsChartEmptyDescription))
                )
                .frame(height: 220)
            } else {
                Chart {
                    ForEach(visibleFatiguePoints) { point in
                        AreaMark(
                            x: .value(localized(.analyticsChartAxisTime), point.timestamp),
                            y: .value(localized(.analyticsChartAxisFatigue), point.fatigue)
                        )
                        .foregroundStyle(
                            LinearGradient(
                                colors: [EyePalette.watch.opacity(0.28), EyePalette.calm.opacity(0.03)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )

                        LineMark(
                            x: .value(localized(.analyticsChartAxisTime), point.timestamp),
                            y: .value(localized(.analyticsChartAxisFatigue), point.fatigue)
                        )
                        .foregroundStyle(EyePalette.watch)
                        .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                    }

                    RuleMark(y: .value(localized(.analyticsChartRestLine), 100))
                        .foregroundStyle(EyePalette.overdue.opacity(0.7))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 5]))

                    if range == .week {
                        ForEach(visibleDailyPeaks) { peak in
                            PointMark(
                                x: .value(localized(.analyticsChartAxisDate), peak.date),
                                y: .value(localized(.analyticsChartDailyPeak), peak.peak)
                            )
                            .foregroundStyle(EyePalette.overdue)
                            .symbolSize(34)
                        }
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading) { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let number = value.as(Double.self) {
                                Text(AppLocalization.fatiguePercent(number, language: language))
                            }
                        }
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: range == .today ? 6 : 7)) { value in
                        AxisGridLine()
                        AxisValueLabel(format: range == .today
                            ? .dateTime.hour().minute()
                            : .dateTime.month().day())
                    }
                }
                .frame(height: 250)
            }
        }
        .padding(20)
        .background(.background, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(.quaternary, lineWidth: 1)
        }
    }

    private var metricGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3), spacing: 12) {
            MetricCard(
                title: localized(.analyticsMetricPeakFatigueTitle),
                value: selectedMetrics.peakFatigue.formatted(.number.precision(.fractionLength(0))) + "%",
                detail: range.title(language: language),
                symbol: "waveform.path.ecg",
                tint: EyePalette.watch
            )
            MetricCard(
                title: localized(.analyticsMetricOverloadDurationTitle),
                value: EyeDurationFormatter.compact(
                    selectedMetrics.overloadDuration,
                    language: language
                ),
                detail: localized(.analyticsMetricOverloadDurationDetail),
                symbol: "exclamationmark.circle.fill",
                tint: EyePalette.overdue
            )
            MetricCard(
                title: localized(.analyticsMetricLongestUsageTitle),
                value: EyeDurationFormatter.compact(
                    selectedMetrics.longestUsageDuration,
                    language: language
                ),
                detail: localized(.analyticsMetricLongestUsageDetail),
                symbol: "timer",
                tint: .blue
            )
            MetricCard(
                title: localized(.analyticsMetricCompletedRestTitle),
                value: AppLocalization.times(selectedMetrics.completedRestCount, language: language),
                detail: localized(.analyticsMetricCompletedRestDetail),
                symbol: "checkmark.seal.fill",
                tint: EyePalette.calm
            )
            MetricCard(
                title: localized(.analyticsMetricInterruptedRestTitle),
                value: AppLocalization.times(selectedMetrics.interruptedRestCount, language: language),
                detail: localized(.analyticsMetricInterruptedRestDetail),
                symbol: "arrow.uturn.backward.circle.fill",
                tint: EyePalette.watch
            )
            MetricCard(
                title: localized(.analyticsMetricAverageResponseTitle),
                value: selectedMetrics.averageResponseDuration.map {
                    EyeDurationFormatter.compact($0, language: language)
                } ?? "—",
                detail: localized(.analyticsMetricAverageResponseDetail),
                symbol: "hourglass",
                tint: .indigo
            )
        }
    }

    private var evidenceCard: some View {
        HStack(spacing: 0) {
            EvidenceItem(
                title: localized(.analyticsEvidenceManualRest),
                count: selectedMetrics.manualRestCount,
                symbol: "hand.tap.fill",
                language: language
            )
            Divider().frame(height: 45)
            EvidenceItem(
                title: localized(.analyticsEvidenceLockOrSleep),
                count: selectedMetrics.systemRestCount,
                symbol: "moon.zzz.fill",
                language: language
            )
            Divider().frame(height: 45)
            EvidenceItem(
                title: localized(.analyticsEvidenceInactivityRest),
                count: selectedMetrics.inactivityRestCount,
                symbol: "keyboard.badge.ellipsis",
                language: language
            )
            Divider().frame(height: 45)
            EvidenceItem(
                title: localized(.analyticsEvidenceDeferredRest),
                count: selectedMetrics.continuedWorkingCount,
                symbol: "arrow.right.circle.fill",
                language: language
            )
        }
        .padding(.vertical, 18)
        .background(.background, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(.quaternary, lineWidth: 1)
        }
    }

    private var visibleFatiguePoints: [FatiguePoint] {
        let calendar = Calendar.current
        switch range {
        case .today:
            return model.analytics.fatiguePoints.filter { calendar.isDateInToday($0.timestamp) }
        case .week:
            let cutoff = calendar.date(byAdding: .day, value: -7, to: Date()) ?? .distantPast
            return model.analytics.fatiguePoints.filter { $0.timestamp >= cutoff }
        }
    }

    private var visibleDailyPeaks: [DailyPeak] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? .distantPast
        return model.analytics.dailyPeaks.filter { $0.date >= cutoff }
    }

    private var selectedMetrics: AnalyticsMetrics {
        switch range {
        case .today:
            return model.analytics.today
        case .week:
            return model.analytics.week
        }
    }

    private var language: AppLanguage {
        model.resolvedLanguage
    }

    private func localized(_ key: L10nKey) -> String {
        AppLocalization.string(key, language: language)
    }
}

private enum DashboardRange: String, CaseIterable, Identifiable {
    case today
    case week

    var id: Self { self }

    func title(language: AppLanguage = .zhHans) -> String {
        switch self {
        case .today:
            AppLocalization.string(.analyticsRangeToday, language: language)
        case .week:
            AppLocalization.string(.analyticsRangeWeek, language: language)
        }
    }
}

private struct MetricCard: View {
    let title: String
    let value: String
    let detail: String
    let symbol: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: symbol)
                    .foregroundStyle(tint)
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer()
            }

            Text(value)
                .font(.system(size: 23, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            Text(detail)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .strokeBorder(.quaternary, lineWidth: 1)
        }
    }
}

private struct EvidenceItem: View {
    let title: String
    let count: Int
    let symbol: String
    let language: AppLanguage

    var body: some View {
        VStack(spacing: 7) {
            Label(title, systemImage: symbol)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(AppLocalization.times(count, language: language))
                .font(.title3.weight(.semibold))
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity)
    }
}
