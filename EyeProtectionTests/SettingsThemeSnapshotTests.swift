import AppKit
import SwiftUI
import XCTest
@testable import EyeProtection

@MainActor
final class SettingsThemeSnapshotTests: XCTestCase {
    private let size = CGSize(width: 472, height: 90)

    func testEverySelectedThemeRendersInsideFixedPickerGeometry() throws {
        for selection in ReminderTheme.allCases {
            let rendered = try render(selection: selection, reduceTransparency: false)

            XCTAssertEqual(rendered.bitmap.pixelsWide, 944)
            XCTAssertEqual(rendered.bitmap.pixelsHigh, 180)
            XCTAssertGreaterThan(rendered.png.count, 20_000)
            for cardCenterX in [112, 352, 592, 832] {
                XCTAssertGreaterThanOrEqual(
                    alpha(of: rendered.bitmap, x: cardCenterX, y: 90),
                    0.99
                )
            }

            try writeScreenshot(
                rendered.png,
                named: "settings-themes-selected-\(selection.rawValue).png"
            )
        }
    }

    func testReduceTransparencyUsesAnOpaqueImageFreeTreatment() throws {
        let regular = try render(selection: .alpineMist, reduceTransparency: false)
        let reduced = try render(selection: .alpineMist, reduceTransparency: true)

        XCTAssertNotEqual(regular.png, reduced.png)
        XCTAssertGreaterThanOrEqual(alpha(of: reduced.bitmap, x: 592, y: 90), 0.99)
        try writeScreenshot(
            reduced.png,
            named: "settings-themes-reduce-transparency.png"
        )
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
        reduceTransparency: Bool
    ) throws -> RenderedSettingsThemes {
        let view = ReminderThemePickerScene(
            selection: selection,
            reduceTransparency: reduceTransparency,
            onSelect: { _ in }
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

    private func writeScreenshot(_ png: Data, named name: String) throws {
        guard let path = ProcessInfo.processInfo.environment["GAZEEASE_MENU_SCREENSHOT_DIR"],
              !path.isEmpty else { return }

        let directory = URL(fileURLWithPath: path, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        try png.write(to: directory.appendingPathComponent(name), options: .atomic)
    }
}

private struct RenderedSettingsThemes {
    let bitmap: NSBitmapImageRep
    let png: Data
}
