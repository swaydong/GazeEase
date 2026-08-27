import AppKit
import SwiftUI
import XCTest
@testable import EyeProtection

@MainActor
final class SettingsThemeSnapshotTests: XCTestCase {
    private let size = ReminderThemePickerLayout.gridSize

    func testNineThemePickerUsesFixedThreeByThreeGeometry() {
        XCTAssertEqual(ReminderTheme.allCases.count, 9)
        XCTAssertEqual(ReminderThemePickerLayout.columns, 3)
        XCTAssertEqual(ReminderThemePickerLayout.rows, 3)
        XCTAssertEqual(ReminderThemePickerLayout.cardSize, CGSize(width: 152, height: 90))
        XCTAssertEqual(ReminderThemePickerLayout.spacing, 8)
        XCTAssertEqual(ReminderThemePickerLayout.totalWidth, 472)
        XCTAssertEqual(ReminderThemePickerLayout.totalHeight, 286)
        XCTAssertEqual(ReminderThemePickerLayout.gridSize, CGSize(width: 472, height: 286))
        XCTAssertEqual(
            ReminderThemePickerLayout.atmosphereSize,
            CGSize(width: 472, height: 116)
        )
    }

    func testEverySelectedThemeRendersInsideFixedPickerGeometry() throws {
        for selection in ReminderTheme.allCases {
            let rendered = try render(selection: selection, reduceTransparency: false)

            XCTAssertEqual(rendered.bitmap.pixelsWide, 944)
            XCTAssertEqual(rendered.bitmap.pixelsHigh, 572)
            XCTAssertGreaterThan(rendered.png.count, 20_000)
            assertEveryCardCenterIsOpaque(rendered.bitmap, scale: 2)

            try writeScreenshot(
                rendered.png,
                named: "settings-themes-selected-\(selection.rawValue).png"
            )
        }
    }

    func testReduceTransparencyUsesAnOpaqueImageFreeTreatment() throws {
        let regular = try render(selection: .rainwashedSeaCliff, reduceTransparency: false)
        let reduced = try render(selection: .rainwashedSeaCliff, reduceTransparency: true)

        XCTAssertNotEqual(regular.png, reduced.png)
        assertEveryCardCenterIsOpaque(reduced.bitmap, scale: 2)
        try writeScreenshot(
            reduced.png,
            named: "settings-themes-reduce-transparency.png"
        )
    }

    func testLongThemeNamesRenderInChineseAndEnglishWithinTheSameGrid() throws {
        for language in [AppLanguage.zhHans, .english] {
            let rendered = try render(
                selection: .rainwashedSeaCliff,
                reduceTransparency: false,
                language: language
            )

            XCTAssertEqual(rendered.bitmap.pixelsWide, 944)
            XCTAssertEqual(rendered.bitmap.pixelsHigh, 572)
            assertEveryCardCenterIsOpaque(rendered.bitmap, scale: 2)

            try writeScreenshot(
                rendered.png,
                named: "settings-themes-" + language.rawValue + "-long-name.png"
            )
        }
    }

    func testEveryThemeUsesADistinctSettingsCardTreatment() {
        let themes = ReminderTheme.allCases

        for leftIndex in themes.indices {
            for rightIndex in themes.indices where rightIndex > leftIndex {
                XCTAssertNotEqual(
                    themes[leftIndex].settingsCardTreatment,
                    themes[rightIndex].settingsCardTreatment
                )
            }
        }
    }

    func testEveryThemeRendersAsAFullWidthAtmosphereWithRotationStatus() throws {
        for theme in ReminderTheme.allCases {
            let rendered = try renderAtmosphere(
                theme: theme,
                rotationEnabled: true,
                rotationIntervalMinutes: 1_440,
                reduceTransparency: false
            )

            XCTAssertEqual(rendered.bitmap.pixelsWide, 944)
            XCTAssertEqual(rendered.bitmap.pixelsHigh, 232)
            XCTAssertGreaterThan(rendered.png.count, 24_000)
            XCTAssertGreaterThanOrEqual(alpha(of: rendered.bitmap, x: 472, y: 116), 0.99)

            try writeScreenshot(
                rendered.png,
                named: "settings-atmosphere-\(theme.rawValue).png"
            )
        }
    }

    func testAtmosphereReduceTransparencyIsOpaqueAndImageFree() throws {
        let regular = try renderAtmosphere(
            theme: .alpineMist,
            rotationEnabled: false,
            rotationIntervalMinutes: 60,
            reduceTransparency: false
        )
        let reduced = try renderAtmosphere(
            theme: .alpineMist,
            rotationEnabled: false,
            rotationIntervalMinutes: 60,
            reduceTransparency: true
        )

        XCTAssertNotEqual(regular.png, reduced.png)
        XCTAssertGreaterThanOrEqual(alpha(of: reduced.bitmap, x: 472, y: 116), 0.99)
        try writeScreenshot(reduced.png, named: "settings-atmosphere-reduce-transparency.png")
    }

    private func render(
        selection: ReminderTheme,
        reduceTransparency: Bool,
        language: AppLanguage = .zhHans
    ) throws -> RenderedSettingsThemes {
        let view = ReminderThemePickerScene(
            selection: selection,
            reduceTransparency: reduceTransparency,
            language: language,
            onSelect: { _ in }
        )
        .environment(
            \.locale,
            Locale(identifier: language == .english ? "en" : "zh-Hans")
        )
        .environment(\.colorScheme, .dark)
        .transaction { transaction in
            transaction.disablesAnimations = true
        }
        .frame(width: size.width, height: size.height)

        let renderer = ImageRenderer(content: view)
        renderer.proposedSize = ProposedViewSize(size)
        renderer.scale = 2
        renderer.isOpaque = false

        let image = try XCTUnwrap(renderer.nsImage)
        let tiff = try XCTUnwrap(image.tiffRepresentation)
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: tiff))
        let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        return RenderedSettingsThemes(bitmap: bitmap, png: png)
    }

    private func renderAtmosphere(
        theme: ReminderTheme,
        rotationEnabled: Bool,
        rotationIntervalMinutes: Int,
        reduceTransparency: Bool
    ) throws -> RenderedSettingsThemes {
        let size = ReminderThemePickerLayout.atmosphereSize
        let view = ReminderThemeAtmosphereScene(
            theme: theme,
            rotationEnabled: rotationEnabled,
            rotationIntervalMinutes: rotationIntervalMinutes,
            reduceTransparency: reduceTransparency
        )
        .environment(\.locale, Locale(identifier: "zh-Hans"))
        .environment(\.colorScheme, .dark)
        .transaction { transaction in
            transaction.disablesAnimations = true
        }
        .frame(width: size.width, height: size.height)

        let renderer = ImageRenderer(content: view)
        renderer.proposedSize = ProposedViewSize(size)
        renderer.scale = 2
        renderer.isOpaque = false

        let image = try XCTUnwrap(renderer.nsImage)
        let tiff = try XCTUnwrap(image.tiffRepresentation)
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: tiff))
        let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        return RenderedSettingsThemes(bitmap: bitmap, png: png)
    }

    private func alpha(of bitmap: NSBitmapImageRep, x: Int, y: Int) -> CGFloat {
        bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0
    }

    private func assertEveryCardCenterIsOpaque(
        _ bitmap: NSBitmapImageRep,
        scale: CGFloat,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        for index in ReminderTheme.allCases.indices {
            let column = index % ReminderThemePickerLayout.columns
            let row = index / ReminderThemePickerLayout.columns
            let x = (
                CGFloat(column)
                    * (ReminderThemePickerLayout.cardSize.width
                        + ReminderThemePickerLayout.spacing)
                    + (ReminderThemePickerLayout.cardSize.width / 2)
            ) * scale
            let y = (
                CGFloat(row)
                    * (ReminderThemePickerLayout.cardSize.height
                        + ReminderThemePickerLayout.spacing)
                    + (ReminderThemePickerLayout.cardSize.height / 2)
            ) * scale

            XCTAssertGreaterThanOrEqual(
                alpha(of: bitmap, x: Int(x), y: Int(y)),
                0.99,
                "Theme card at index \(index) should be opaque at its center",
                file: file,
                line: line
            )
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

private struct RenderedSettingsThemes {
    let bitmap: NSBitmapImageRep
    let png: Data
}
