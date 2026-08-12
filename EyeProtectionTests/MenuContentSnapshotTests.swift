import AppKit
import SwiftUI
import XCTest
@testable import EyeProtection

@MainActor
final class MenuContentSnapshotTests: XCTestCase {
    private let size = CGSize(width: 320, height: 300)

    func testEveryThemeRendersAtFixedMenuWidth() throws {
        for theme in ReminderTheme.allCases {
            let rendered = try render(
                presentation: overloadedPresentation(theme: theme),
                reduceTransparency: false,
                scale: 2
            )

            XCTAssertEqual(rendered.bitmap.pixelsWide, 640)
            XCTAssertEqual(rendered.bitmap.pixelsHigh, 600)
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
                presenceDescription: "正在使用电脑",
                isMonitoringComplete: true,
                restSecondsRemaining: 0,
                theme: .twilightDunes
            ),
            reduceTransparency: false,
            scale: 2
        )

        XCTAssertEqual(rendered.bitmap.pixelsWide, 640)
        XCTAssertEqual(rendered.bitmap.pixelsHigh, 600)
        XCTAssertGreaterThan(rendered.png.count, 20_000)
        assertOpaqueSurface(rendered.bitmap)
        try writeScreenshot(rendered.png, named: "menu-content-extreme.png")
    }

    func testNormalFatigueStateUsesTheSameOpaqueThemeSurface() throws {
        let rendered = try render(
            presentation: MenuContentPresentation(
                fatigue: 63,
                fatigueDisplay: "63%",
                restRequired: false,
                isResting: false,
                overloadDuration: 0,
                presenceDescription: "静态阅读或思考",
                isMonitoringComplete: true,
                restSecondsRemaining: 0,
                theme: .quietHorizon
            ),
            reduceTransparency: false,
            scale: 2
        )

        XCTAssertEqual(rendered.bitmap.pixelsWide, 640)
        XCTAssertEqual(rendered.bitmap.pixelsHigh, 600)
        assertOpaqueSurface(rendered.bitmap)
        try writeScreenshot(rendered.png, named: "menu-content-normal.png")
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
        let treatments = ReminderTheme.allCases.map(\.menuBackdropTreatment)

        XCTAssertEqual(Set(treatments.map(\.imageOpacity)).count, ReminderTheme.allCases.count)
        XCTAssertEqual(Set(treatments.map(\.lightCenter)).count, ReminderTheme.allCases.count)
        XCTAssertNotEqual(
            ReminderTheme.quietHorizon.menuBackdropTreatment,
            ReminderTheme.forestLight.menuBackdropTreatment
        )
    }

    private func overloadedPresentation(theme: ReminderTheme) -> MenuContentPresentation {
        MenuContentPresentation(
            fatigue: 128,
            fatigueDisplay: "128%",
            restRequired: true,
            isResting: false,
            overloadDuration: 60,
            presenceDescription: "正在使用电脑",
            isMonitoringComplete: true,
            restSecondsRemaining: 0,
            theme: theme
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
        try png.write(
            to: directory.appendingPathComponent(name),
            options: .atomic
        )
    }
}

private struct RenderedMenuContent {
    let bitmap: NSBitmapImageRep
    let png: Data
}
