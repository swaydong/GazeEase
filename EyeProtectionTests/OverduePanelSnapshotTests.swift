import AppKit
import SwiftUI
import XCTest
@testable import EyeProtection

@MainActor
final class OverduePanelSnapshotTests: XCTestCase {
    func testTopReminderRendersAtExpectedSizeWithTransparentCorners() throws {
        let rendered = try renderPanel(
            fatigueDisplay: "128%",
            overloadDuration: 60,
            scale: 2,
            colorScheme: .dark,
            reduceTransparency: false
        )

        XCTAssertEqual(rendered.bitmap.pixelsWide, 1_028)
        XCTAssertEqual(rendered.bitmap.pixelsHigh, 216)
        XCTAssertGreaterThan(rendered.png.count, 10_000)
        assertCornersAreTransparent(rendered.bitmap)
        assertCenterIsOpaque(rendered.bitmap)

        try writeScreenshot(rendered.png, named: "top-popup.png")
    }

    func testExtremeFatigueValueStillRendersAtExpectedSize() throws {
        let rendered = try renderPanel(
            fatigueDisplay: "1.2k%",
            overloadDuration: 5_280,
            scale: 1,
            colorScheme: .light,
            reduceTransparency: false
        )

        XCTAssertEqual(rendered.image.size, CGSize(width: 514, height: 108))
        XCTAssertEqual(rendered.bitmap.pixelsWide, 514)
        XCTAssertEqual(rendered.bitmap.pixelsHigh, 108)
        XCTAssertGreaterThan(rendered.png.count, 5_000)
        assertCornersAreTransparent(rendered.bitmap)
        assertCenterIsOpaque(rendered.bitmap)

        try writeScreenshot(rendered.png, named: "top-popup-extreme.png")
    }

    func testReduceTransparencyUsesDistinctOpaqueSurfaceTreatment() throws {
        let regular = try renderPanel(
            fatigueDisplay: "128%",
            overloadDuration: 60,
            scale: 2,
            colorScheme: .dark,
            reduceTransparency: false
        )
        let reduced = try renderPanel(
            fatigueDisplay: "128%",
            overloadDuration: 60,
            scale: 2,
            colorScheme: .dark,
            reduceTransparency: true
        )

        XCTAssertNotEqual(regular.png, reduced.png)
        XCTAssertGreaterThan(
            try XCTUnwrap(reduced.bitmap.colorAt(
                x: reduced.bitmap.pixelsWide / 2,
                y: reduced.bitmap.pixelsHigh / 2
            )).alphaComponent,
            0.99
        )
        assertCornersAreTransparent(reduced.bitmap)

        try writeScreenshot(reduced.png, named: "top-popup-reduce-transparency.png")
    }

    func testEveryThemeRendersTheSamePanelGeometry() throws {
        for theme in ReminderTheme.allCases {
            let rendered = try renderPanel(
                fatigueDisplay: "128%",
                overloadDuration: 60,
                scale: 2,
                colorScheme: .dark,
                reduceTransparency: false,
                theme: theme
            )
            XCTAssertEqual(rendered.bitmap.pixelsWide, 1_028)
            XCTAssertEqual(rendered.bitmap.pixelsHigh, 216)
            assertCornersAreTransparent(rendered.bitmap)
            assertCenterIsOpaque(rendered.bitmap)
            try writeScreenshot(rendered.png, named: "top-popup-\(theme.rawValue).png")
        }
    }

    private func renderPanel(
        fatigueDisplay: String,
        overloadDuration: TimeInterval,
        scale: CGFloat,
        colorScheme: ColorScheme,
        reduceTransparency: Bool,
        theme: ReminderTheme = .quietHorizon
    ) throws -> RenderedPanel {
        let presentation = ReminderPanelPresentation()
        let size = presentation.panelSize
        let view = OverduePanelScene(
            fatigueDisplay: fatigueDisplay,
            overloadDuration: overloadDuration,
            presentation: presentation,
            theme: theme,
            onContinueWorking: {},
            onBeginRest: {},
            reduceTransparencyOverride: reduceTransparency
        )
        .environment(\.locale, Locale(identifier: "zh-Hans"))
        .environment(\.colorScheme, colorScheme)
        .transaction { transaction in
            transaction.disablesAnimations = true
        }
        .frame(width: size.width, height: size.height)

        let renderer = ImageRenderer(content: view)
        renderer.proposedSize = ProposedViewSize(size)
        renderer.scale = scale
        renderer.isOpaque = false

        let image: NSImage = try XCTUnwrap(renderer.nsImage)
        let tiff: Data = try XCTUnwrap(image.tiffRepresentation)
        let bitmap: NSBitmapImageRep = try XCTUnwrap(NSBitmapImageRep(data: tiff))
        let png = try XCTUnwrap(
            bitmap.representation(using: .png, properties: [:])
        )
        return RenderedPanel(image: image, bitmap: bitmap, png: png)
    }

    private func assertCornersAreTransparent(
        _ bitmap: NSBitmapImageRep,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let corners = [
            NSPoint(x: 0, y: 0),
            NSPoint(x: bitmap.pixelsWide - 1, y: 0),
            NSPoint(x: 0, y: bitmap.pixelsHigh - 1),
            NSPoint(x: bitmap.pixelsWide - 1, y: bitmap.pixelsHigh - 1)
        ]

        for corner in corners {
            let alpha = bitmap.colorAt(
                x: Int(corner.x),
                y: Int(corner.y)
            )?.alphaComponent ?? 0
            XCTAssertLessThanOrEqual(
                alpha,
                0.04,
                "Only the intentional soft shadow may reach the canvas corner",
                file: file,
                line: line
            )
        }
    }

    private func assertCenterIsOpaque(
        _ bitmap: NSBitmapImageRep,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let alpha = bitmap.colorAt(
            x: bitmap.pixelsWide / 2,
            y: bitmap.pixelsHigh / 2
        )?.alphaComponent ?? 0
        XCTAssertGreaterThanOrEqual(alpha, 0.99, file: file, line: line)
    }

    private func writeScreenshot(_ png: Data, named name: String) throws {
        guard let outputDirectory = screenshotOutputDirectory() else { return }
        try png.write(
            to: outputDirectory.appendingPathComponent(name),
            options: .atomic
        )
    }

    private func screenshotOutputDirectory() -> URL? {
        guard let path = ProcessInfo.processInfo.environment["GAZEEASE_POPUP_SCREENSHOT_DIR"],
              !path.isEmpty else { return nil }

        let url = URL(fileURLWithPath: path, isDirectory: true)
        try? FileManager.default.createDirectory(
            at: url,
            withIntermediateDirectories: true
        )
        return url
    }
}

private struct RenderedPanel {
    let image: NSImage
    let bitmap: NSBitmapImageRep
    let png: Data
}
