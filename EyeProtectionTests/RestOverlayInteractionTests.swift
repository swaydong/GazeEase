import AppKit
import SwiftUI
import XCTest
@testable import EyeProtection

@MainActor
final class RestOverlayInteractionTests: XCTestCase {
    func testReturnInvokesBeginRestWithoutDeferring() throws {
        var beginRestCount = 0
        var deferRestCount = 0
        let window = makeWindow(
            presentation: decisionPresentation,
            onBeginRest: { beginRestCount += 1 },
            onContinueWorking: { deferRestCount += 1 }
        )
        defer { window.close() }

        let handled = window.performKeyEquivalent(with: try makeKeyEvent(keyCode: 36, characters: "\r"))

        XCTAssertTrue(handled)
        XCTAssertEqual(beginRestCount, 1)
        XCTAssertEqual(deferRestCount, 0)
    }

    func testEscapeDoesNotSkipTheDecision() throws {
        var beginRestCount = 0
        var deferRestCount = 0
        let window = makeWindow(
            presentation: decisionPresentation,
            onBeginRest: { beginRestCount += 1 },
            onContinueWorking: { deferRestCount += 1 }
        )
        defer { window.close() }

        let handled = window.performKeyEquivalent(with: try makeKeyEvent(keyCode: 53, characters: "\u{1b}"))

        XCTAssertFalse(handled)
        XCTAssertEqual(beginRestCount, 0)
        XCTAssertEqual(deferRestCount, 0)
    }

    private var decisionPresentation: RestOverlayPresentation {
        RestOverlayPresentation(
            mode: .decision,
            fatigueDisplay: "128%",
            overloadDuration: 60,
            restSecondsRemaining: 0,
            restProgress: 0
        )
    }

    private func makeWindow(
        presentation: RestOverlayPresentation,
        onBeginRest: @escaping () -> Void,
        onContinueWorking: @escaping () -> Void
    ) -> NSWindow {
        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 900, height: 640),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = NSHostingView(
            rootView: RestOverlayScene(
                presentation: presentation,
                onBeginRest: onBeginRest,
                onContinueWorking: onContinueWorking,
                reduceMotionOverride: true,
                reduceTransparencyOverride: false
            )
        )
        window.makeKeyAndOrderFront(nil)
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        return window
    }

    private func makeKeyEvent(keyCode: UInt16, characters: String) throws -> NSEvent {
        try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: characters,
            charactersIgnoringModifiers: characters,
            isARepeat: false,
            keyCode: keyCode
        ))
    }
}
