import AppKit
import SwiftUI
import XCTest
@testable import EyeProtection

@MainActor
final class MenuContentSnapshotTests: XCTestCase {
    private let size = CGSize(width: 320, height: 425)

    func testMenuRefreshRunsOnlyWhileItsOwnHostWindowIsVisible() {
        XCTAssertFalse(MenuRefreshPolicy.shouldRun(isMenuVisible: false))
        XCTAssertTrue(MenuRefreshPolicy.shouldRun(isMenuVisible: true))
        XCTAssertTrue((10...30).contains(MenuRefreshPolicy.visibleRefreshInterval))

        XCTAssertFalse(MenuHostWindowVisibilityPolicy.isVisible(
            isWindowVisible: false,
            isKeyWindow: false
        ))
        XCTAssertFalse(MenuHostWindowVisibilityPolicy.isVisible(
            isWindowVisible: true,
            isKeyWindow: false
        ))
        XCTAssertFalse(MenuHostWindowVisibilityPolicy.isVisible(
            isWindowVisible: false,
            isKeyWindow: true
        ))
        XCTAssertTrue(MenuHostWindowVisibilityPolicy.isVisible(
            isWindowVisible: true,
            isKeyWindow: true
        ))

        let hostWindow = NSWindow()
        let unrelatedWindow = NSWindow()
        XCTAssertTrue(MenuHostWindowVisibilityPolicy.isEventForHostWindow(
            eventWindow: hostWindow,
            hostWindow: hostWindow
        ))
        XCTAssertFalse(MenuHostWindowVisibilityPolicy.isEventForHostWindow(
            eventWindow: unrelatedWindow,
            hostWindow: hostWindow
        ))
        XCTAssertFalse(MenuHostWindowVisibilityPolicy.isEventForHostWindow(
            eventWindow: nil,
            hostWindow: hostWindow
        ))
    }

    func testTodayFatigueSummaryFiltersToTodayAndAddsLivePoint() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let startOfDay = calendar.startOfDay(for: now)
        let summary = MenuTodayFatigueSummary(
            points: [
                MenuTodayFatiguePoint(
                    timestamp: startOfDay.addingTimeInterval(-1),
                    fatigue: 900
                ),
                MenuTodayFatiguePoint(
                    timestamp: startOfDay.addingTimeInterval(60),
                    fatigue: 80
                ),
                MenuTodayFatiguePoint(
                    timestamp: startOfDay.addingTimeInterval(120),
                    fatigue: 128
                ),
                MenuTodayFatiguePoint(
                    timestamp: now.addingTimeInterval(1),
                    fatigue: 1_200
                )
            ],
            currentFatigue: 63,
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(summary.points.map(\.fatigue), [80, 128, 63])
        XCTAssertEqual(summary.points.last?.timestamp, now)
        XCTAssertEqual(summary.peakFatigue, 128, accuracy: 0.000_001)
        XCTAssertEqual(summary.upperBound, 140, accuracy: 0.000_001)
        XCTAssertEqual(summary.peakDisplay(language: .zhHans), "峰值 128%")
        XCTAssertEqual(
            summary.accessibilityLabel(language: .english),
            "Today's fatigue curve has 3 data points, a peak of 128%, and a current value of 63%."
        )
    }

    func testTodayFatigueSummaryHandlesEmptySingleAndExtremeValues() {
        let now = Date()
        XCTAssertTrue(MenuTodayFatigueSummary.empty.points.isEmpty)
        XCTAssertEqual(MenuTodayFatigueSummary.empty.upperBound, 120)

        let single = MenuTodayFatigueSummary(
            points: [],
            currentFatigue: 63,
            now: now
        )
        XCTAssertEqual(single.points.count, 1)
        XCTAssertEqual(single.points[0].fatigue, 63, accuracy: 0.000_001)

        let extreme = MenuTodayFatigueSummary(
            points: [],
            currentFatigue: 1_200,
            now: now
        )
        XCTAssertEqual(extreme.upperBound, 1_300, accuracy: 0.000_001)
        XCTAssertEqual(extreme.peakDisplay(language: .english), "Peak 1.2k%")
    }

    func testTodayFatigueSummaryLimitsVisualPointsAndPreservesEndpointsAndPeak() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let startOfDay = calendar.startOfDay(
            for: Date(timeIntervalSince1970: 1_800_000_000)
        )
        let now = startOfDay.addingTimeInterval(20 * 60 * 60)
        let peakTimestamp = startOfDay.addingTimeInterval(334 * 60)
        var sourcePoints: [MenuTodayFatiguePoint] = []
        sourcePoints.reserveCapacity(720)
        for minute in 1...720 {
            let timestamp = startOfDay.addingTimeInterval(
                TimeInterval(minute * 60)
            )
            let fatigue: Double = minute == 334
                ? 1_200
                : Double(40 + minute % 60)
            sourcePoints.append(MenuTodayFatiguePoint(
                timestamp: timestamp,
                fatigue: fatigue
            ))
        }

        let summary = MenuTodayFatigueSummary(
            points: sourcePoints,
            currentFatigue: 73,
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(summary.points.count, 721)
        XCTAssertLessThanOrEqual(
            summary.visualPoints.count,
            MenuTodayFatigueSummary.maximumVisualPointCount
        )
        XCTAssertEqual(summary.visualPoints.first, summary.points.first)
        XCTAssertEqual(summary.visualPoints.last, summary.points.last)
        XCTAssertTrue(summary.visualPoints.contains(
            MenuTodayFatiguePoint(timestamp: peakTimestamp, fatigue: 1_200)
        ))
        XCTAssertEqual(summary.peakFatigue, 1_200, accuracy: 0.000_001)
        XCTAssertEqual(summary.currentFatigue, 73, accuracy: 0.000_001)
        XCTAssertEqual(
            summary.peakDisplay(language: AppLanguage.english),
            "Peak 1.2k%"
        )
        XCTAssertEqual(
            summary.accessibilityLabel(language: AppLanguage.english),
            "Today's fatigue curve has 721 data points, a peak of 1.2k%, and a current value of 73%."
        )
    }

    func testTodayOverviewSummaryUsesLocalizedZeroAndDurationCopy() {
        XCTAssertEqual(
            MenuTodayOverviewSummary.empty.overloadDisplay(language: .zhHans),
            "今天未超负荷"
        )

        let oneMinute = MenuTodayOverviewSummary(overloadDuration: 60)
        XCTAssertEqual(
            oneMinute.overloadDisplay(language: .zhHans),
            "超负荷 1 分钟"
        )
        XCTAssertEqual(
            oneMinute.overloadDisplay(language: .english),
            "Overload 1 minute"
        )

        let extreme = MenuTodayOverviewSummary(overloadDuration: 5_280)
        XCTAssertEqual(
            extreme.overloadDisplay(language: .zhHans),
            "超负荷 1 小时 28 分钟"
        )
        XCTAssertEqual(
            extreme.overloadDisplay(language: .english),
            "Overload 1 hour 28 minutes"
        )
    }

    func testTodayOverviewAccessibilityReadsOverloadBeforeCurve() {
        let presentation = overloadedPresentation(
            theme: .quietHorizon,
            language: .english
        )

        XCTAssertEqual(
            presentation.todayOverviewAccessibilityLabel,
            "Overload 1 hour 28 minutes Today's fatigue curve has 4 data points, a peak of 128%, and a current value of 128%."
        )
        XCTAssertFalse(
            presentation.todayOverviewAccessibilityLabel.contains("Average Response")
        )
        XCTAssertFalse(
            presentation.todayOverviewAccessibilityLabel.contains("Complete rests")
        )
    }

    func testMonitoringIssueCopyDistinguishesPermissionFromRuntimeFailure() {
        var presentation = emptyPresentation(theme: .quietHorizon)
        presentation.inputPermissionGranted = false
        XCTAssertEqual(
            AppLocalization.string(
                presentation.monitoringIssueKey,
                language: .zhHans
            ),
            "输入监控未授权"
        )

        presentation.inputPermissionGranted = true
        XCTAssertEqual(
            AppLocalization.string(
                presentation.monitoringIssueKey,
                language: .english
            ),
            "Input monitoring is not running"
        )
    }

    func testMenuContentIntrinsicHeightFitsCompactPanel() {
        let view = MenuContentScene(
            presentation: overloadedPresentation(
                theme: .quietHorizon,
                language: .english
            ),
            onBeginRest: {},
            onOpenAnalytics: {},
            onOpenSettings: {},
            onQuit: {},
            reduceTransparencyOverride: false
        )
        .environment(\.locale, Locale(identifier: "en"))
        .environment(\.colorScheme, .dark)

        let hostingView = NSHostingView(rootView: view)
        hostingView.frame = NSRect(
            origin: .zero,
            size: NSSize(width: size.width, height: 1)
        )
        hostingView.layoutSubtreeIfNeeded()

        XCTAssertLessThanOrEqual(hostingView.fittingSize.height, size.height)
    }

    func testEveryThemeRendersAtFixedMenuWidth() throws {
        for theme in ReminderTheme.allCases {
            let rendered = try render(
                presentation: overloadedPresentation(theme: theme),
                reduceTransparency: false,
                scale: 2
            )

            XCTAssertEqual(rendered.bitmap.pixelsWide, 640)
            XCTAssertEqual(rendered.bitmap.pixelsHigh, 850)
            XCTAssertGreaterThan(rendered.png.count, 20_000)
            assertOpaqueSurface(rendered.bitmap)

            try writeScreenshot(
                rendered.png,
                named: "menu-content-\(theme.rawValue).png"
            )
        }
    }

    func testExtremeFatigueRemainsWithinSameGeometry() throws {
        let rendered = try render(
            presentation: MenuContentPresentation(
                fatigue: 1_200,
                fatigueDisplay: "1.2k%",
                restRequired: true,
                isResting: false,
                overloadDuration: 5_280,
                presenceDescription: AppLocalization.string(
                    .presenceActiveInteraction,
                    language: .english
                ),
                isMonitoringComplete: true,
                restSecondsRemaining: 0,
                theme: .twilightDunes,
                language: .english,
                todayOverview: MenuTodayOverviewSummary(
                    overloadDuration: 5_280
                ),
                todayFatigue: fatigueSummary(
                    values: [28, 72, 118, 420, 1_200],
                    currentFatigue: 1_200
                )
            ),
            reduceTransparency: false,
            scale: 2
        )

        XCTAssertEqual(rendered.bitmap.pixelsWide, 640)
        XCTAssertEqual(rendered.bitmap.pixelsHigh, 850)
        XCTAssertGreaterThan(rendered.png.count, 20_000)
        assertOpaqueSurface(rendered.bitmap)
        try writeScreenshot(rendered.png, named: "menu-content-extreme.png")
    }

    func testNormalFatigueStateUsesTheSameOpaqueThemeSurface() throws {
        let rendered = try render(
            presentation: normalPresentation(theme: .quietHorizon),
            reduceTransparency: false,
            scale: 2
        )

        XCTAssertEqual(rendered.bitmap.pixelsWide, 640)
        XCTAssertEqual(rendered.bitmap.pixelsHigh, 850)
        assertOpaqueSurface(rendered.bitmap)
        try writeScreenshot(rendered.png, named: "menu-content-normal.png")
    }

    func testMonitoringRepairStateRendersWithinCompactPanel() throws {
        let presentation = MenuContentPresentation(
            fatigue: 0,
            fatigueDisplay: "0%",
            restRequired: false,
            isResting: false,
            overloadDuration: 0,
            presenceDescription: AppLocalization.string(
                .presenceUnobservable,
                language: .zhHans
            ),
            isMonitoringComplete: false,
            restSecondsRemaining: 0,
            theme: .quietHorizon,
            inputPermissionGranted: false,
            language: .zhHans,
            todayOverview: .empty,
            todayFatigue: .empty
        )

        let rendered = try render(
            presentation: presentation,
            reduceTransparency: false,
            scale: 2
        )

        XCTAssertEqual(rendered.bitmap.pixelsWide, 640)
        XCTAssertEqual(rendered.bitmap.pixelsHigh, 850)
        assertOpaqueSurface(rendered.bitmap)
        try writeScreenshot(
            rendered.png,
            named: "menu-content-monitoring-repair.png"
        )
    }

    func testChineseAndEnglishEmptyAndExtremeTodayOverviewScenesRender() throws {
        for language in [AppLanguage.zhHans, .english] {
            for hasRecords in [false, true] {
                let presentation = hasRecords
                    ? overloadedPresentation(theme: .quietHorizon, language: language)
                    : emptyPresentation(theme: .quietHorizon, language: language)

                let rendered = try render(
                    presentation: presentation,
                    reduceTransparency: false,
                    scale: 2
                )

                XCTAssertEqual(rendered.bitmap.pixelsWide, 640)
                XCTAssertEqual(rendered.bitmap.pixelsHigh, 850)
                XCTAssertGreaterThan(rendered.png.count, 20_000)
                assertOpaqueSurface(rendered.bitmap)

                try writeScreenshot(
                    rendered.png,
                    named: "menu-content-\(language.rawValue)-\(hasRecords ? "extreme" : "empty").png"
                )
            }
        }
    }

    func testReduceTransparencyUsesOpaqueImageFreeTreatment() throws {
        let presentation = overloadedPresentation(theme: .alpineMist)
        let regular = try render(
            presentation: presentation,
            reduceTransparency: false,
            scale: 2
        )
        let reduced = try render(
            presentation: presentation,
            reduceTransparency: true,
            scale: 2
        )

        XCTAssertNotEqual(regular.png, reduced.png)
        assertOpaqueSurface(reduced.bitmap)
        try writeScreenshot(
            reduced.png,
            named: "menu-content-reduce-transparency.png"
        )
    }

    func testEveryThemeUsesADistinctMenuBackdropTreatment() {
        let themes = ReminderTheme.allCases

        XCTAssertEqual(themes.count, 9)
        for leftIndex in themes.indices {
            for rightIndex in themes.indices where rightIndex > leftIndex {
                XCTAssertNotEqual(
                    themes[leftIndex].menuBackdropTreatment,
                    themes[rightIndex].menuBackdropTreatment
                )
            }
        }
    }

    private func overloadedPresentation(
        theme: ReminderTheme,
        language: AppLanguage = .zhHans
    ) -> MenuContentPresentation {
        MenuContentPresentation(
            fatigue: 128,
            fatigueDisplay: "128%",
            restRequired: true,
            isResting: false,
            overloadDuration: 60,
            presenceDescription: AppLocalization.string(
                .presenceActiveInteraction,
                language: language
            ),
            isMonitoringComplete: true,
            restSecondsRemaining: 0,
            theme: theme,
            language: language,
            todayOverview: MenuTodayOverviewSummary(
                overloadDuration: 5_280
            ),
            todayFatigue: fatigueSummary(
                values: [63, 99, 128],
                currentFatigue: 128
            )
        )
    }

    private func normalPresentation(
        theme: ReminderTheme,
        language: AppLanguage = .zhHans
    ) -> MenuContentPresentation {
        MenuContentPresentation(
            fatigue: 63,
            fatigueDisplay: "63%",
            restRequired: false,
            isResting: false,
            overloadDuration: 0,
            presenceDescription: AppLocalization.string(
                .presencePassiveStatic,
                language: language
            ),
            isMonitoringComplete: true,
            restSecondsRemaining: 0,
            theme: theme,
            language: language,
            todayOverview: .empty,
            todayFatigue: fatigueSummary(values: [], currentFatigue: 63)
        )
    }

    private func emptyPresentation(
        theme: ReminderTheme,
        language: AppLanguage = .zhHans
    ) -> MenuContentPresentation {
        MenuContentPresentation(
            fatigue: 0,
            fatigueDisplay: "0%",
            restRequired: false,
            isResting: false,
            overloadDuration: 0,
            presenceDescription: AppLocalization.string(
                .presencePassiveStatic,
                language: language
            ),
            isMonitoringComplete: true,
            restSecondsRemaining: 0,
            theme: theme,
            language: language,
            todayOverview: .empty,
            todayFatigue: .empty
        )
    }

    private func fatigueSummary(
        values: [Double],
        currentFatigue: Double
    ) -> MenuTodayFatigueSummary {
        let calendar = Calendar(identifier: .gregorian)
        let now = calendar.startOfDay(for: Date()).addingTimeInterval(18 * 60 * 60)
        let points = values.enumerated().map { index, fatigue in
            MenuTodayFatiguePoint(
                timestamp: now.addingTimeInterval(TimeInterval((index - values.count) * 1_800)),
                fatigue: fatigue
            )
        }
        return MenuTodayFatigueSummary(
            points: points,
            currentFatigue: currentFatigue,
            now: now,
            calendar: calendar
        )
    }

    private func render(
        presentation: MenuContentPresentation,
        reduceTransparency: Bool,
        scale: CGFloat
    ) throws -> RenderedMenuContent {
        let view = MenuContentScene(
            presentation: presentation,
            onBeginRest: {},
            onOpenAnalytics: {},
            onOpenSettings: {},
            onQuit: {},
            reduceTransparencyOverride: reduceTransparency
        )
        .environment(\.locale, Locale(identifier: "zh-Hans"))
        .environment(\.colorScheme, .dark)
        .transaction { transaction in
            transaction.disablesAnimations = true
        }
        .frame(width: size.width, height: size.height)

        let renderer = ImageRenderer(content: view)
        renderer.proposedSize = ProposedViewSize(size)
        renderer.scale = scale
        renderer.isOpaque = false

        let image = try XCTUnwrap(renderer.nsImage)
        let tiff = try XCTUnwrap(image.tiffRepresentation)
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: tiff))
        let png = try XCTUnwrap(
            bitmap.representation(using: .png, properties: [:])
        )
        return RenderedMenuContent(bitmap: bitmap, png: png)
    }

    private func assertOpaqueSurface(
        _ bitmap: NSBitmapImageRep,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let points = [
            NSPoint(x: 1, y: 1),
            NSPoint(x: bitmap.pixelsWide / 2, y: bitmap.pixelsHigh / 2),
            NSPoint(x: bitmap.pixelsWide - 2, y: bitmap.pixelsHigh - 2)
        ]

        for point in points {
            let alpha = bitmap.colorAt(x: Int(point.x), y: Int(point.y))?.alphaComponent ?? 0
            XCTAssertGreaterThanOrEqual(alpha, 0.99, file: file, line: line)
        }
    }

    private func writeScreenshot(_ png: Data, named name: String) throws {
        guard let path = ProcessInfo.processInfo.environment["GAZEEASE_MENU_SCREENSHOT_DIR"],
              !path.isEmpty else { return }

        let directory = URL(fileURLWithPath: path, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        try png.write(to: directory.appendingPathComponent(name))
    }
}

private struct RenderedMenuContent {
    let bitmap: NSBitmapImageRep
    let png: Data
}
