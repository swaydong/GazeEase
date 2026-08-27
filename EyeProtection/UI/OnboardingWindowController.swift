import AppKit
import Combine
import SwiftUI

enum OnboardingWindowPolicy {
    static func canClose(onboardingCompleted: Bool) -> Bool {
        onboardingCompleted
    }
}

@MainActor
final class OnboardingWindowController: NSObject, NSWindowDelegate {
    private let model: AppModel
    private var window: NSWindow?
    private var cancellables = Set<AnyCancellable>()

    init(model: AppModel) {
        self.model = model
        super.init()

        model.$appLanguage
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.updateWindowTitle()
                }
            }
            .store(in: &cancellables)

        model.$onboardingCompleted
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.updateCloseButtonAvailability()
                }
            }
            .store(in: &cancellables)
    }

    func showIfNeeded() {
        guard !model.onboardingCompleted else { return }
        show()
    }

    func show() {
        let window = window ?? makeWindow()
        self.window = window
        if window.contentView == nil {
            installContent(in: window)
        }
        updateWindowTitle()
        updateCloseButtonAvailability()
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func close() {
        window?.orderOut(nil)
        window?.contentView = nil
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard OnboardingWindowPolicy.canClose(
            onboardingCompleted: model.onboardingCompleted
        ) else {
            NSSound.beep()
            return false
        }
        close()
        return false
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 520),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.delegate = self
        window.isReleasedWhenClosed = false
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.backgroundColor = NSColor(
            red: 0.004,
            green: 0.044,
            blue: 0.052,
            alpha: 1
        )
        window.collectionBehavior = [.moveToActiveSpace]
        window.contentMinSize = NSSize(width: 520, height: 520)
        window.contentMaxSize = NSSize(width: 520, height: 520)
        installContent(in: window)
        return window
    }

    private func installContent(in window: NSWindow) {
        window.contentView = NSHostingView(
            rootView: OnboardingView(
                model: model,
                onComplete: { [weak self] in
                    self?.close()
                }
            )
        )
    }

    private func updateWindowTitle() {
        window?.title = AppLocalization.string(
            .onboardingWindowTitle,
            language: model.resolvedLanguage
        )
    }

    private func updateCloseButtonAvailability() {
        window?.standardWindowButton(.closeButton)?.isEnabled =
            OnboardingWindowPolicy.canClose(
                onboardingCompleted: model.onboardingCompleted
            )
    }
}
