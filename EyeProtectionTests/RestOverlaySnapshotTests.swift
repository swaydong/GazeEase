import AppKit
import SwiftUI
import XCTest
@testable import EyeProtection

@MainActor
final class RestOverlaySnapshotTests: XCTestCase {
    private struct Viewport {
        let name: String
        let size: CGSize
    }

    private struct SceneState {
        let name: String
        let presentation: RestOverlayPresentation
    }

    func testAcceptanceScreenshotMatrixRendersAtExactSizes() async throws {
        let viewports = [
            Viewport(name: "1440x900", size: CGSize(width: 1440, height: 900)),
            Viewport(name: "1470x956", size: CGSize(width: 1470, height: 956)),
            Viewport(name: "1920x1080", size: CGSize(width: 1920, height: 1080)),
            Viewport(name: "2560x1080", size: CGSize(width: 2560, height: 1080))
        ]
        let states = [
            SceneState(
                name: "decision",
                presentation: RestOverlayPresentation(
                    mode: .decision,
                    fatigueDisplay: "128%",
                    overloadDuration: 60,
                    restSecondsRemaining: 0,
                    restProgress: 0
                )
            ),
            SceneState(
                name: "rest-start",
                presentation: RestOverlayPresentation(
                    mode: .resting,
                    fatigueDisplay: "128%",
                    overloadDuration: 60,
                    restSecondsRemaining: 20,
                    restProgress: 0
                )
            ),
            SceneState(
                name: "rest-middle",
                presentation: RestOverlayPresentation(
                    mode: .resting,
                    fatigueDisplay: "64%",
                    overloadDuration: 60,
                    restSecondsRemaining: 10,
                    restProgress: 0.5
                )
            ),
            SceneState(
                name: "rest-nearly-complete",
                presentation: RestOverlayPresentation(
                    mode: .resting,
                    fatigueDisplay: "7%",
                    overloadDuration: 60,
                    restSecondsRemaining: 1,
                    restProgress: 0.95
                )
            )
        ]
        let outputDirectory = screenshotOutputDirectory()

        for viewport in viewports {
            for state in states {
                let data = try await render(
                    presentation: state.presentation,
                    size: viewport.size,
                    reduceMotion: false,
                    reduceTransparency: false
                )
                let bitmap = try XCTUnwrap(NSBitmapImageRep(data: data))
                XCTAssertEqual(bitmap.pixelsWide, Int(viewport.size.width))
                XCTAssertEqual(bitmap.pixelsHigh, Int(viewport.size.height))
                XCTAssertGreaterThan(data.count, 100_000)

                if let outputDirectory {
                    let output = outputDirectory
                        .appendingPathComponent("\(state.name)-\(viewport.name).png")
                    try data.write(to: output)
                }
            }
        }
    }

    func testEveryThemeRendersDecisionAndUnifiedCountdown() async throws {
        let outputDirectory = screenshotOutputDirectory()
        let size = CGSize(width: 1440, height: 900)
        let states = [
            SceneState(
                name: "decision",
                presentation: RestOverlayPresentation(
                    mode: .decision,
                    fatigueDisplay: "128%",
                    overloadDuration: 60,
                    restSecondsRemaining: 0,
                    restProgress: 0
                )
            ),
            SceneState(
                name: "rest-middle",
                presentation: RestOverlayPresentation(
                    mode: .resting,
                    fatigueDisplay: "64%",
                    overloadDuration: 60,
                    restSecondsRemaining: 10,
                    restProgress: 0.5
                )
            )
        ]

        for theme in ReminderTheme.allCases {
            for state in states {
                let data = try await render(
                    presentation: state.presentation,
                    theme: theme,
                    size: size,
                    reduceMotion: false,
                    reduceTransparency: false
                )
                XCTAssertGreaterThan(data.count, 100_000)
                if let outputDirectory {
                    try data.write(
                        to: outputDirectory.appendingPathComponent(
                            "\(theme.rawValue)-\(state.name)-1440x900.png"
                        ),
                        options: []
                    )
                }
            }
        }
    }

    func testEveryThemeRendersAtWideAndTallAcceptanceViewports() async throws {
        let viewports = [
            Viewport(name: "1470x956", size: CGSize(width: 1470, height: 956)),
            Viewport(name: "2560x1080", size: CGSize(width: 2560, height: 1080))
        ]
        let states = [
            SceneState(
                name: "decision-extreme",
                presentation: RestOverlayPresentation(
                    mode: .decision,
                    fatigueDisplay: "1.2k%",
                    overloadDuration: 5_280,
                    restSecondsRemaining: 0,
                    restProgress: 0
                )
            ),
            SceneState(
                name: "rest-middle",
                presentation: RestOverlayPresentation(
                    mode: .resting,
                    fatigueDisplay: "64%",
                    overloadDuration: 60,
                    restSecondsRemaining: 10,
                    restProgress: 0.5
                )
            )
        ]
        let outputDirectory = screenshotOutputDirectory()

        for theme in ReminderTheme.allCases {
            for viewport in viewports {
                for state in states {
                    let data = try await render(
                        presentation: state.presentation,
                        theme: theme,
                        size: viewport.size,
                        reduceMotion: false,
                        reduceTransparency: false
                    )
                    let bitmap = try XCTUnwrap(NSBitmapImageRep(data: data))
                    XCTAssertEqual(bitmap.pixelsWide, Int(viewport.size.width))
                    XCTAssertEqual(bitmap.pixelsHigh, Int(viewport.size.height))
                    XCTAssertGreaterThan(data.count, 100_000)

                    if let outputDirectory {
                        try data.write(
                            to: outputDirectory.appendingPathComponent(
                                "\(theme.rawValue)-\(state.name)-\(viewport.name).png"
                            ),
                            options: []
                        )
                    }
                }
            }
        }
    }

    func testExtremeFatigueAndAccessibilityModesRenderWithoutClipping() async throws {
        let extreme = RestOverlayPresentation(
            mode: .decision,
            fatigueDisplay: "1.2k%",
            overloadDuration: 5_280,
            restSecondsRemaining: 0,
            restProgress: 0
        )
        let resting = RestOverlayPresentation(
            mode: .resting,
            fatigueDisplay: "128%",
            overloadDuration: 60,
            restSecondsRemaining: 10,
            restProgress: 0.5
        )
        let outputDirectory = screenshotOutputDirectory()

        let reducedTransparency = try await render(
            presentation: extreme,
            size: CGSize(width: 1440, height: 900),
            reduceMotion: false,
            reduceTransparency: true
        )
        let reducedMotion = try await render(
            presentation: resting,
            size: CGSize(width: 1440, height: 900),
            reduceMotion: true,
            reduceTransparency: false
        )

        XCTAssertGreaterThan(reducedTransparency.count, 100_000)
        XCTAssertGreaterThan(reducedMotion.count, 100_000)

        if let outputDirectory {
            try reducedTransparency.write(
                to: outputDirectory.appendingPathComponent("decision-1.2k-reduce-transparency.png"),
                options: []
            )
            try reducedMotion.write(
                to: outputDirectory.appendingPathComponent("rest-middle-reduce-motion.png"),
                options: []
            )
        }
    }

    private func render(
        presentation: RestOverlayPresentation,
        theme: ReminderTheme = .quietHorizon,
        size: CGSize,
        reduceMotion: Bool,
        reduceTransparency: Bool
    ) async throws -> Data {
        let maximumPixelDimension = backgroundMaximumPixelDimension(for: size)
        let backgroundLease = RestBackgroundImageLoader.shared.lease(
            for: theme,
            maximumPixelDimension: maximumPixelDimension
        )
        let rawBackground = try await waitForBackgroundImage(backgroundLease)

        XCTAssertEqual(rawBackground.width, maximumPixelDimension)
        XCTAssertEqual(
            Double(rawBackground.width) / Double(rawBackground.height),
            1.6,
            accuracy: 0.003
        )
        XCTAssertGreaterThan(
            try sampledColorCount(in: rawBackground),
            8,
            "Expected decoded raw background pixels for \(theme.rawValue), not fallback"
        )

        return try withExtendedLifetime(backgroundLease) {
            try autoreleasepool {
                let scene = RestOverlayScene(
                    presentation: presentation,
                    theme: theme,
                    onBeginRest: {},
                    onContinueWorking: {},
                    reduceMotionOverride: reduceMotion,
                    reduceTransparencyOverride: reduceTransparency,
                    backgroundMaximumPixelDimensionOverride: maximumPixelDimension
                )
                .environment(\.locale, Locale(identifier: "zh-Hans"))
                .environment(\.colorScheme, .dark)
                .transaction { transaction in
                    transaction.disablesAnimations = true
                }
                .frame(width: size.width, height: size.height)

                let renderer = ImageRenderer(content: scene)
                renderer.proposedSize = ProposedViewSize(size)
                renderer.scale = 1

                let image: NSImage = try XCTUnwrap(renderer.nsImage)
                let tiff: Data = try XCTUnwrap(image.tiffRepresentation)
                let bitmap: NSBitmapImageRep = try XCTUnwrap(NSBitmapImageRep(data: tiff))
                return try XCTUnwrap(
                    bitmap.representation(
                        using: NSBitmapImageRep.FileType.png,
                        properties: [:]
                    )
                )
            }
        }
    }

    private func backgroundMaximumPixelDimension(for viewport: CGSize) -> Int {
        let aspectFillHeight = viewport.height * 1.6
        return min(3072, max(1, Int(ceil(max(viewport.width, aspectFillHeight)))))
    }

    private func waitForBackgroundImage(
        _ lease: RestBackgroundImageLease,
        timeout: TimeInterval = 5
    ) async throws -> CGImage {
        let deadline = Date().addingTimeInterval(timeout)
        while lease.image == nil {
            guard Date() < deadline else {
                throw SnapshotBackgroundError.timedOut
            }
            try await Task.sleep(for: .milliseconds(5))
        }
        return try XCTUnwrap(lease.image)
    }

    private func sampledColorCount(in image: CGImage) throws -> Int {
        let width = 12
        let height = 8
        var pixels = [UInt32](repeating: 0, count: width * height)

        try pixels.withUnsafeMutableBytes { buffer in
            let context = try XCTUnwrap(CGContext(
                data: buffer.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * MemoryLayout<UInt32>.size,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ))
            context.interpolationQuality = .low
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }

        return Set(pixels).count
    }

    private func screenshotOutputDirectory() -> URL? {
        guard let path = ProcessInfo.processInfo.environment["GAZEEASE_SCREENSHOT_DIR"],
              !path.isEmpty else { return nil }

        let url = URL(fileURLWithPath: path, isDirectory: true)
        try? FileManager.default.createDirectory(
            at: url,
            withIntermediateDirectories: true
        )
        return url
    }
}

private enum SnapshotBackgroundError: Error {
    case timedOut
}
