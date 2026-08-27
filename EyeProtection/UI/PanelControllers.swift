import AppKit
import Combine
import SwiftUI

enum RestOverlayWindowTransitionPhase {
    case appearing
    case disappearing
}

struct RestOverlayWindowAnimation {
    static let fadeInDuration: TimeInterval = 0.30
    static let fadeOutDuration: TimeInterval = 0.22

    static func duration(
        for phase: RestOverlayWindowTransitionPhase,
        reduceMotion: Bool
    ) -> TimeInterval {
        guard !reduceMotion else { return 0 }
        return switch phase {
        case .appearing:
            fadeInDuration
        case .disappearing:
            fadeOutDuration
        }
    }
}

enum ReminderPreviewPolicy {
    static func shouldDismissForRealState(
        restRequired: Bool,
        isResting: Bool
    ) -> Bool {
        restRequired || isResting
    }
}

enum ReminderPanelContentPolicy {
    static func shouldReplace(
        hasContent: Bool,
        current: ReminderPanelPresentation?,
        updated: ReminderPanelPresentation
    ) -> Bool {
        !hasContent || current != updated
    }
}

private struct ReminderControllerObservation: Equatable {
    let restRequired: Bool
    let isResting: Bool
    let reminderMode: ReminderMode
    let promptState: ReminderPromptState
}

@MainActor
final class OverduePanelController {
    private let model: AppModel
    private let panel: NonActivatingReminderPanel
    private var cancellables = Set<AnyCancellable>()
    private var presentation: ReminderPanelPresentation?
    private var previewDismissTask: Task<Void, Never>?
    private var isShowingPreview = false

    init(model: AppModel) {
        self.model = model
        self.panel = NonActivatingReminderPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        configurePanel()
        observeModel()
        update(
            restRequired: model.restRequired,
            isResting: model.isResting,
            reminderMode: model.reminderMode,
            promptState: model.reminderPromptState
        )
    }

    func show(_ updatedPresentation: ReminderPanelPresentation) {
        if ReminderPanelContentPolicy.shouldReplace(
            hasContent: panel.contentView != nil,
            current: presentation,
            updated: updatedPresentation
        ) {
            presentation = updatedPresentation
            panel.contentView = NSHostingView(
                rootView: OverduePanelView(
                    model: model,
                    presentation: updatedPresentation
                )
            )
        }

        positionPanel()
        panel.orderFrontRegardless()
    }

    func hide() {
        previewDismissTask?.cancel()
        previewDismissTask = nil
        isShowingPreview = false
        panel.orderOut(nil)
        presentation = nil
        panel.contentView = nil
    }

    func showPreview(duration: TimeInterval = 6) {
        guard model.canShowTestReminderPreview else { return }

        previewDismissTask?.cancel()
        isShowingPreview = true

        let previewPresentation = ReminderPanelPresentation()
        presentation = previewPresentation
        installPreviewContent(presentation: previewPresentation)
        positionPanel()
        panel.orderFrontRegardless()

        previewDismissTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: .seconds(max(1, duration)))
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            self?.hidePreview()
        }
    }

    private func installPreviewContent(
        presentation previewPresentation: ReminderPanelPresentation
    ) {
        let closePreview: () -> Void = { [weak self] in
            self?.hidePreview()
        }
        panel.contentView = NSHostingView(
            rootView: OverduePanelScene(
                fatigueDisplay: AppLocalization.fatiguePercent(
                    100,
                    language: model.resolvedLanguage
                ),
                overloadDuration: 0,
                presentation: previewPresentation,
                theme: model.reminderTheme,
                language: model.resolvedLanguage,
                onContinueWorking: closePreview,
                onBeginRest: closePreview
            )
        )
    }

    private func hidePreview() {
        guard isShowingPreview else { return }
        previewDismissTask?.cancel()
        previewDismissTask = nil
        isShowingPreview = false
        update(
            restRequired: model.restRequired,
            isResting: model.isResting,
            reminderMode: model.reminderMode,
            promptState: model.reminderPromptState
        )
    }

    private func configurePanel() {
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .screenSaver
        panel.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .stationary,
            .ignoresCycle
        ]
        panel.animationBehavior = .utilityWindow
    }

    private func observeModel() {
        Publishers.CombineLatest4(
            model.$restRequired,
            model.$isResting,
            model.$reminderMode,
            model.$reminderPromptState
        )
        .map { restRequired, isResting, reminderMode, promptState in
            ReminderControllerObservation(
                restRequired: restRequired,
                isResting: isResting,
                reminderMode: reminderMode,
                promptState: promptState
            )
        }
        .removeDuplicates()
        .receive(on: RunLoop.main)
        .sink { [weak self] observation in
            Task { @MainActor [weak self] in
                self?.update(
                    restRequired: observation.restRequired,
                    isResting: observation.isResting,
                    reminderMode: observation.reminderMode,
                    promptState: observation.promptState
                )
            }
        }
        .store(in: &cancellables)

        Publishers.CombineLatest(model.$reminderTheme, model.$appLanguage)
            .dropFirst()
            .removeDuplicates { previous, updated in
                previous.0 == updated.0 && previous.1 == updated.1
            }
            .receive(on: RunLoop.main)
            .sink { [weak self] _, _ in
                Task { @MainActor [weak self] in
                    guard let self,
                          let presentation = self.presentation else { return }
                    if self.isShowingPreview {
                        self.installPreviewContent(presentation: presentation)
                        return
                    }
                    self.panel.contentView = NSHostingView(
                        rootView: OverduePanelView(
                            model: self.model,
                            presentation: presentation
                        )
                    )
                }
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .merge(with: NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.activeSpaceDidChangeNotification))
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.positionPanel()
                }
            }
            .store(in: &cancellables)
    }

    private func update(
        restRequired: Bool,
        isResting: Bool,
        reminderMode: ReminderMode,
        promptState: ReminderPromptState
    ) {
        if isShowingPreview {
            guard ReminderPreviewPolicy.shouldDismissForRealState(
                restRequired: restRequired,
                isResting: isResting
            ) else { return }
            previewDismissTask?.cancel()
            previewDismissTask = nil
            isShowingPreview = false
            // Preview and real panels currently have the same value-only
            // presentation. Invalidate the cached view so live values and real
            // callbacks are always installed after the preview retires.
            presentation = nil
            panel.contentView = nil
        }

        guard let presentation = ReminderPresentationPolicy.panel(
            restRequired: restRequired,
            isResting: isResting,
            promptState: promptState,
            reminderMode: reminderMode
        ) else {
            hide()
            return
        }

        show(presentation)
    }

    private func positionPanel() {
        guard let screen = activeScreen,
              let presentation else { return }

        let size = presentation.panelSize
        let frame = NSRect(
            x: screen.visibleFrame.midX - size.width / 2,
            y: screen.visibleFrame.maxY - size.height - 8,
            width: size.width,
            height: size.height
        )
        panel.setFrame(frame, display: true, animate: panel.isVisible)
    }

    private var activeScreen: NSScreen? {
        let pointer = NSEvent.mouseLocation
        return NSScreen.screens.first(where: { $0.frame.contains(pointer) }) ?? NSScreen.main
    }
}

@MainActor
final class RestOverlayController {
    private let model: AppModel
    private var panels: [ObjectIdentifier: RestBlockingPanel] = [:]
    private var cancellables = Set<AnyCancellable>()
    private var presentedMode: RestOverlayMode?

    init(model: AppModel) {
        self.model = model
        observeModel()
        update(
            restRequired: model.restRequired,
            isResting: model.isResting,
            activeRestTrigger: model.activeRestTrigger,
            reminderMode: model.reminderMode,
            promptState: model.reminderPromptState
        )
    }

    func presentDecision() {
        present(.decision)
    }

    func presentRest() {
        present(.resting)
    }

    func hide() {
        let outgoingPanels = Array(panels.values)
        panels.removeAll()
        presentedMode = nil
        retire(
            outgoingPanels,
            reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        )
    }

    private func observeModel() {
        Publishers.CombineLatest4(
            model.$restRequired,
            model.$isResting,
            model.$reminderMode,
            model.$reminderPromptState
        )
        .map { restRequired, isResting, reminderMode, promptState in
            ReminderControllerObservation(
                restRequired: restRequired,
                isResting: isResting,
                reminderMode: reminderMode,
                promptState: promptState
            )
        }
        .removeDuplicates()
        .receive(on: RunLoop.main)
        .sink { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.update(
                    restRequired: self.model.restRequired,
                    isResting: self.model.isResting,
                    activeRestTrigger: self.model.activeRestTrigger,
                    reminderMode: self.model.reminderMode,
                    promptState: self.model.reminderPromptState
                )
            }
        }
        .store(in: &cancellables)

        model.$reminderTheme
            .dropFirst()
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.rebuildForCurrentScreens()
                }
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.rebuildForCurrentScreens()
                }
            }
            .store(in: &cancellables)
    }

    private func update(
        restRequired: Bool,
        isResting: Bool,
        activeRestTrigger: RestTrigger?,
        reminderMode: ReminderMode,
        promptState: ReminderPromptState
    ) {
        guard let overlayPhase = ReminderPresentationPolicy.overlay(
            restRequired: restRequired,
            isResting: isResting,
            activeRestTrigger: activeRestTrigger,
            promptState: promptState,
            reminderMode: reminderMode
        ) else {
            hide()
            return
        }

        let mode: RestOverlayMode = switch overlayPhase {
        case .decision: .decision
        case .resting: .resting
        }
        if presentedMode != mode {
            present(mode)
        }
    }

    private func present(_ mode: RestOverlayMode) {
        presentedMode = mode
        rebuildForCurrentScreens()

        NSApp.activate(ignoringOtherApps: true)
        let pointer = NSEvent.mouseLocation
        let primaryScreen = NSScreen.screens.first(where: { $0.frame.contains(pointer) }) ?? NSScreen.main
        if let primaryScreen,
           let primaryPanel = panels[ObjectIdentifier(primaryScreen)] {
            primaryPanel.makeKeyAndOrderFront(nil)
        }
    }

    private func rebuildForCurrentScreens() {
        guard let mode = presentedMode else { return }
        let currentPhase = ReminderPresentationPolicy.overlay(
            restRequired: model.restRequired,
            isResting: model.isResting,
            activeRestTrigger: model.activeRestTrigger,
            promptState: model.reminderPromptState,
            reminderMode: model.reminderMode
        )
        let currentMode = currentPhase.map { phase in
            switch phase {
            case .decision: RestOverlayMode.decision
            case .resting: RestOverlayMode.resting
            }
        }
        guard currentMode == mode else {
            hide()
            return
        }

        let outgoingPanels = Array(panels.values)
        panels.removeAll()

        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion

        let pointer = NSEvent.mouseLocation
        let primaryScreen = NSScreen.screens.first(where: { $0.frame.contains(pointer) }) ?? NSScreen.main

        for screen in NSScreen.screens {
            let panel = RestBlockingPanel(
                contentRect: screen.frame,
                styleMask: [.borderless],
                backing: .buffered,
                defer: false,
                screen: screen
            )
            panel.level = .screenSaver
            panel.collectionBehavior = [
                .canJoinAllSpaces,
                .fullScreenAuxiliary,
                .stationary,
                .ignoresCycle
            ]
            panel.isOpaque = true
            panel.backgroundColor = .black
            panel.hidesOnDeactivate = false
            panel.animationBehavior = .none
            panel.alphaValue = reduceMotion ? 1 : 0
            panel.contentView = NSHostingView(
                rootView: RestOverlayView(
                    model: model,
                    mode: mode,
                    onBeginRest: { [weak self] in
                        self?.model.beginRest()
                    },
                    onContinueWorking: { [weak self] in
                        self?.model.continueWorking()
                        self?.hide()
                    }
                )
                .accessibilityHidden(screen !== primaryScreen)
            )
            panel.setFrame(screen.frame, display: true)
            panel.contentView?.layoutSubtreeIfNeeded()
            panel.displayIfNeeded()
            panel.orderFrontRegardless()
            panels[ObjectIdentifier(screen)] = panel
        }

        if let primaryScreen,
           let primaryPanel = panels[ObjectIdentifier(primaryScreen)] {
            primaryPanel.makeKeyAndOrderFront(nil)
        }

        fadeIn(Array(panels.values), reduceMotion: reduceMotion)
        retire(outgoingPanels, reduceMotion: reduceMotion)
    }

    private func fadeIn(
        _ incomingPanels: [RestBlockingPanel],
        reduceMotion: Bool
    ) {
        let duration = RestOverlayWindowAnimation.duration(
            for: .appearing,
            reduceMotion: reduceMotion
        )
        guard duration > 0 else {
            incomingPanels.forEach { $0.alphaValue = 1 }
            return
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            incomingPanels.forEach { $0.animator().alphaValue = 1 }
        }
    }

    private func retire(
        _ outgoingPanels: [RestBlockingPanel],
        reduceMotion: Bool
    ) {
        guard !outgoingPanels.isEmpty else { return }

        let duration = RestOverlayWindowAnimation.duration(
            for: .disappearing,
            reduceMotion: reduceMotion
        )
        guard duration > 0 else {
            outgoingPanels.forEach { panel in
                panel.orderOut(nil)
                panel.contentView = nil
            }
            return
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            outgoingPanels.forEach { $0.animator().alphaValue = 0 }
        } completionHandler: {
            MainActor.assumeIsolated {
                outgoingPanels.forEach { panel in
                    panel.orderOut(nil)
                    panel.contentView = nil
                }
            }
        }
    }
}

private final class NonActivatingReminderPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private final class RestBlockingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
