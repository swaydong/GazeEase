import AppKit
import SwiftUI
import XCTest
@testable import EyeProtection

@MainActor
final class MenuBarStatusLabelTests: XCTestCase {
    func testTaijiAssetUsesFifteenPointIntrinsicSize() throws {
        let image = try XCTUnwrap(NSImage(named: "MenuBarTaiji"))

        XCTAssertEqual(image.size.width, 15, accuracy: 0.01)
        XCTAssertEqual(image.size.height, 15, accuracy: 0.01)
    }

    func testRepresentativeFatigueValuesStayCompact() {
        for value in ["0%", "63%", "100%", "999%", "1.2k%"] {
            let host = NSHostingView(
                rootView: MenuBarStatusLabel(
                    fatigueDisplay: value,
                    isMonitoringComplete: true
                )
            )

            XCTAssertLessThanOrEqual(
                host.fittingSize.width,
                48,
                "\(value) should keep the menu bar item compact"
            )
        }
    }
}
