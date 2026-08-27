import AppKit
import SwiftUI
import XCTest
@testable import EyeProtection

@MainActor
final class DashboardViewTests: XCTestCase {
    private let size = CGSize(width: 900, height: 720)

    func testZeroValuesUsePositiveCopyAndDoNotCountAsTrendData() {
        let chineseToday = presentation(
            range: .today,
            language: .zhHans,
            state: .empty
        )
        XCTAssertFalse(chineseToday.hasTrendData)
        XCTAssertEqual(chineseToday.overloadMetricDisplay, "状态良好")
        XCTAssertEqual(chineseToday.peakMetricDisplay, "保持舒缓")
        XCTAssertEqual(chineseToday.longestUsageMetricDisplay, "节奏轻松")
        XCTAssertEqual(chineseToday.restRatioDisplay, "暂无休息记录")
        XCTAssertEqual(chineseToday.restAccessibilityLabel, "暂无休息记录。")

        let englishWeek = presentation(
            range: .week,
            language: .english,
            state: .empty
        )
        XCTAssertFalse(englishWeek.hasTrendData)
        XCTAssertEqual(englishWeek.overloadMetricDisplay, "All clear")
        XCTAssertEqual(englishWeek.peakMetricDisplay, "Comfortable")
        XCTAssertEqual(englishWeek.longestUsageMetricDisplay, "Easy pace")
        XCTAssertEqual(englishWeek.restRatioDisplay, "No rest records yet")
        XCTAssertEqual(englishWeek.restAccessibilityLabel, "No rest records yet.")
    }

    func testExtremePresentationFormatsMetricsAndAccessibilitySummary() {
        let english = presentation(
            range: .week,
            language: .english,
            state: .extreme
        )

        XCTAssertTrue(english.hasTrendData)
        XCTAssertEqual(english.peakDisplay, "1.2k%")
        XCTAssertEqual(english.restRatioDisplay, "4 / 6")
        XCTAssertTrue(english.summaryAccessibilityLabel.contains("1.2k%"))
        XCTAssertTrue(english.trendAccessibilityLabel.contains("7 days"))
        XCTAssertTrue(english.restAccessibilityLabel.contains("4 full rests"))
    }

    func testWeekdayAndHoverDatesFollowTheSelectedLanguage() throws {
        let calendar = Calendar(identifier: .gregorian)
        let date = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026,
            month: 8,
            day: 10
        )))
        let chinese = presentation(
            range: .week,
            language: .zhHans,
            state: .extreme
        )
        let english = presentation(
            range: .week,
            language: .english,
            state: .extreme
        )

        XCTAssertEqual(chinese.weekdayDisplay(for: date), "一")
        XCTAssertEqual(english.weekdayDisplay(for: date), "M")
        XCTAssertTrue(chinese.hoverDateDisplay(for: date).contains("周一"))
        XCTAssertTrue(english.hoverDateDisplay(for: date).contains("Mon"))
    }

    func testRestRatioHandlesCompleteOnlyAndInterruptedOnlyAttempts() {
        let completeOnly = presentation(
            range: .today,
            language: .zhHans,
            state: .extreme,
            completedRestCount: 4,
            interruptedRestCount: 0
        )
        XCTAssertEqual(completeOnly.restRatioDisplay, "4 / 4")

        let interruptedOnly = presentation(
            range: .today,
            language: .english,
            state: .extreme,
            completedRestCount: 0,
            interruptedRestCount: 2
        )
        XCTAssertEqual(interruptedOnly.restRatioDisplay, "0 / 2")
    }

    func testChineseAndEnglishTodayAndWeekEmptyAndExtremeScenesRender() throws {
        for language in [AppLanguage.zhHans, .english] {
            for range in DashboardRange.allCases {
                for state in DashboardTestState.allCases {
                    let rendered = try render(
                        presentation: presentation(
                            range: range,
                            language: language,
                            state: state
                        )
                    )

                    XCTAssertEqual(rendered.bitmap.pixelsWide, Int(size.width * 2))
                    XCTAssertEqual(rendered.bitmap.pixelsHigh, Int(size.height * 2))
                    XCTAssertGreaterThan(rendered.png.count, 28_000)

                    try writeScreenshot(
                        rendered.png,
                        named: "dashboard-\(language.rawValue)-\(range.rawValue)-\(state.rawValue).png"
                    )
                }
            }
        }
    }

    func testEveryThemeRendersReadablyInLightAndDarkAppearances() throws {
        for theme in ReminderTheme.allCases {
            for appearance in DashboardTestAppearance.allCases {
                let rendered = try render(
                    presentation: presentation(
                        range: .week,
                        language: .zhHans,
                        state: .extreme,
                        theme: theme
                    ),
                    colorScheme: appearance.colorScheme
                )

                XCTAssertEqual(rendered.bitmap.pixelsWide, Int(size.width * 2))
                XCTAssertEqual(rendered.bitmap.pixelsHigh, Int(size.height * 2))
                XCTAssertGreaterThan(rendered.png.count, 28_000)

                try writeScreenshot(
                    rendered.png,
                    named: "dashboard-audit-\(theme.rawValue)-\(appearance.rawValue).png"
                )
            }
        }
    }

    func testAccessibilityAppearancesAndMinimumWindowRender() throws {
        let reduceTransparency = try render(
            presentation: presentation(
                range: .week,
                language: .english,
                state: .extreme,
                theme: .twilightDunes
            ),
            colorScheme: .light,
            reduceTransparency: true
        )
        try writeScreenshot(
            reduceTransparency.png,
            named: "dashboard-audit-reduce-transparency-light.png"
        )

        let increasedContrast = try render(
            presentation: presentation(
                range: .today,
                language: .zhHans,
                state: .extreme,
                theme: .alpineMist
            ),
            colorScheme: .dark,
            colorSchemeContrast: .increased
        )
        try writeScreenshot(
            increasedContrast.png,
            named: "dashboard-audit-increased-contrast-dark.png"
        )

        let minimumSize = CGSize(width: 760, height: 560)
        let minimumWindow = try render(
            presentation: presentation(
                range: .week,
                language: .english,
                state: .extreme,
                theme: .forestLight
            ),
            size: minimumSize,
            colorScheme: .light
        )
        XCTAssertEqual(minimumWindow.bitmap.pixelsWide, Int(minimumSize.width * 2))
        XCTAssertEqual(minimumWindow.bitmap.pixelsHigh, Int(minimumSize.height * 2))
        XCTAssertGreaterThan(minimumWindow.png.count, 20_000)
        try writeScreenshot(
            minimumWindow.png,
            named: "dashboard-audit-minimum-window-light.png"
        )

        let fullContent = try render(
            presentation: presentation(
                range: .today,
                language: .zhHans,
                state: .empty,
                theme: .quietHorizon
            ),
            size: CGSize(width: 900, height: 920),
            colorScheme: .light
        )
        XCTAssertEqual(fullContent.bitmap.pixelsHigh, 1_840)
        try writeScreenshot(
            fullContent.png,
            named: "dashboard-audit-full-content-light.png"
        )
    }

    func testRestSourcesRenderVisibleWithoutInteraction() throws {
        let expandedContentSize = CGSize(width: 900, height: 920)
        for language in [AppLanguage.zhHans, .english] {
            let rendered = try render(
                presentation: presentation(
                    range: .today,
                    language: language,
                    state: .extreme,
                    theme: .quietHorizon
                ),
                size: expandedContentSize,
                colorScheme: .light
            )

            XCTAssertEqual(rendered.bitmap.pixelsWide, 1_800)
            XCTAssertEqual(rendered.bitmap.pixelsHigh, 1_840)
            XCTAssertGreaterThan(rendered.png.count, 28_000)
            try writeScreenshot(
                rendered.png,
                named: "dashboard-rest-sources-visible-\(language.rawValue)-light.png"
            )
        }
    }

    private func presentation(
        range: DashboardRange,
        language: AppLanguage,
        state: DashboardTestState,
        theme: ReminderTheme = .quietHorizon,
        completedRestCount: Int? = nil,
        interruptedRestCount: Int? = nil
    ) -> DashboardPresentation {
        let start = Date(timeIntervalSinceReferenceDate: 800_000_000)
        let calendar = Calendar(identifier: .gregorian)
        let isExtreme = state == .extreme
        let fatiguePoints = isExtreme
            ? [28.0, 72, 118, 420, 1_200].enumerated().map { index, fatigue in
                DashboardFatiguePoint(
                    timestamp: start.addingTimeInterval(TimeInterval(index * 1_800)),
                    fatigue: fatigue
                )
            }
            : []
        let dailyPoints = (0..<7).map { index in
            DashboardDailyPoint(
                date: calendar.date(byAdding: .day, value: index, to: start) ?? start,
                peakFatigue: isExtreme ? [82, 104, 176, 1_200, 232, 98, 146][index] : 0,
                overloadDuration: isExtreme ? TimeInterval([0, 300, 1_200, 5_280, 2_400, 0, 900][index]) : 0,
                longestUsageDuration: isExtreme ? TimeInterval(2_400 + index * 600) : 0
            )
        }

        return DashboardPresentation(
            range: range,
            language: language,
            theme: theme,
            currentFatigue: isExtreme ? 1_200 : 0,
            currentFatigueDisplay: isExtreme ? "1.2k%" : "0%",
            currentStatus: AppLocalization.string(
                isExtreme ? .analyticsWaitingForRest : .presencePassiveStatic,
                language: language
            ),
            fatiguePoints: fatiguePoints,
            dailyPoints: dailyPoints,
            metrics: DashboardMetrics(
                peakFatigue: isExtreme ? 1_200 : 0,
                overloadDuration: isExtreme ? 5_280 : 0,
                longestUsageDuration: isExtreme ? 7_200 : 0,
                completedRestCount: completedRestCount ?? (isExtreme ? 4 : 0),
                interruptedRestCount: interruptedRestCount ?? (isExtreme ? 2 : 0),
                averageResponseDuration: isExtreme ? 75 : nil
            ),
            sources: DashboardRestSources(
                manual: isExtreme ? 2 : 0,
                system: isExtreme ? 1 : 0,
                inactivity: 0,
                deferred: isExtreme ? 4 : 0
            )
        )
    }

    private func render(
        presentation: DashboardPresentation,
        size: CGSize? = nil,
        colorScheme: ColorScheme = .dark,
        reduceTransparency: Bool = false,
        colorSchemeContrast: ColorSchemeContrast = .standard
    ) throws -> RenderedDashboard {
        let renderSize = size ?? self.size
        let locale = presentation.language == .zhHans ? "zh_CN" : "en_US"
        let view = DashboardScene(
            presentation: presentation,
            range: .constant(presentation.range),
            accessibilityOverrides: DashboardAccessibilityOverrides(
                reduceTransparency: reduceTransparency,
                colorSchemeContrast: colorSchemeContrast
            )
        )
        .environment(\.locale, Locale(identifier: locale))
        .environment(\.colorScheme, colorScheme)
        .transaction { transaction in
            transaction.disablesAnimations = true
        }
        .frame(width: renderSize.width, height: renderSize.height)

        let hostingView = NSHostingView(rootView: view)
        hostingView.appearance = NSAppearance(
            named: colorScheme == .dark ? .darkAqua : .aqua
        )
        hostingView.frame = NSRect(origin: .zero, size: renderSize)
        hostingView.layoutSubtreeIfNeeded()
        hostingView.displayIfNeeded()
        let bitmap = try XCTUnwrap(
            hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds)
        )
        hostingView.cacheDisplay(in: hostingView.bounds, to: bitmap)
        let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        return RenderedDashboard(bitmap: bitmap, png: png)
    }

    private func writeScreenshot(_ png: Data, named name: String) throws {
        guard let path = ProcessInfo.processInfo.environment["GAZEEASE_DASHBOARD_SCREENSHOT_DIR"],
              !path.isEmpty else { return }

        let directory = URL(fileURLWithPath: path, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        try png.write(to: directory.appendingPathComponent(name))
    }
}

private enum DashboardTestState: String, CaseIterable {
    case empty
    case extreme
}

private enum DashboardTestAppearance: String, CaseIterable {
    case light
    case dark

    var colorScheme: ColorScheme {
        self == .light ? .light : .dark
    }
}

private struct RenderedDashboard {
    let bitmap: NSBitmapImageRep
    let png: Data
}
