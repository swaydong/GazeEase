import XCTest
@testable import EyeProtection

final class ReminderPresentationPolicyTests: XCTestCase {
    func testDecisionActionsExposeDeferAndBeginRest() {
        XCTAssertEqual(
            ReminderDecisionAction.allCases.map(\.title),
            ["暂不休息", "开始休息"]
        )
    }

    func testSystemNotificationHasNoCustomReminderSurface() {
        XCTAssertNil(ReminderPresentationPolicy.panel(
            restRequired: true,
            isResting: false,
            promptState: .initialDecision,
            reminderMode: .systemNotification
        ))
        XCTAssertNil(ReminderPresentationPolicy.overlay(
            restRequired: true,
            isResting: false,
            activeRestTrigger: nil,
            promptState: .initialDecision,
            reminderMode: .systemNotification
        ))
    }

    func testTopPanelModeShowsTwoButtonPanel() throws {
        let presentation = try XCTUnwrap(ReminderPresentationPolicy.panel(
            restRequired: true,
            isResting: false,
            promptState: .initialDecision,
            reminderMode: .topPanel
        ))

        XCTAssertTrue(presentation.showsDeferAction)
        XCTAssertEqual(presentation.contentWidth, 502)
        XCTAssertEqual(presentation.panelSize, CGSize(width: 514, height: 108))
        XCTAssertNil(ReminderPresentationPolicy.overlay(
            restRequired: true,
            isResting: false,
            activeRestTrigger: nil,
            promptState: .initialDecision,
            reminderMode: .topPanel
        ))
    }

    func testFullScreenModeUsesDecisionOverlayWithoutDuplicatePanel() {
        XCTAssertNil(ReminderPresentationPolicy.panel(
            restRequired: true,
            isResting: false,
            promptState: .initialDecision,
            reminderMode: .fullScreen
        ))
        XCTAssertEqual(ReminderPresentationPolicy.overlay(
            restRequired: true,
            isResting: false,
            activeRestTrigger: nil,
            promptState: .initialDecision,
            reminderMode: .fullScreen
        ), .decision)
    }

    func testDeferringHidesEveryReminderWithoutTimedReappearance() {
        for mode in ReminderMode.allCases {
            XCTAssertNil(ReminderPresentationPolicy.panel(
                restRequired: true,
                isResting: false,
                promptState: .hidden,
                reminderMode: mode
            ))
            XCTAssertNil(ReminderPresentationPolicy.overlay(
                restRequired: true,
                isResting: false,
                activeRestTrigger: nil,
                promptState: .hidden,
                reminderMode: mode
            ))
        }
    }

    func testManualRestInterruptionUsesTopPanelForEveryInitialMode() throws {
        for mode in ReminderMode.allCases {
            let presentation = try XCTUnwrap(ReminderPresentationPolicy.panel(
                restRequired: true,
                isResting: false,
                promptState: .manualRetry,
                reminderMode: mode
            ))
            XCTAssertTrue(presentation.showsDeferAction)
            XCTAssertNil(ReminderPresentationPolicy.overlay(
                restRequired: true,
                isResting: false,
                activeRestTrigger: nil,
                promptState: .manualRetry,
                reminderMode: mode
            ))
        }
    }

    func testManualRestingHidesPromptAndShowsRestOverlay() {
        for mode in ReminderMode.allCases {
            XCTAssertNil(ReminderPresentationPolicy.panel(
                restRequired: true,
                isResting: true,
                promptState: .manualRetry,
                reminderMode: mode
            ))
            XCTAssertEqual(ReminderPresentationPolicy.overlay(
                restRequired: true,
                isResting: true,
                activeRestTrigger: .manual,
                promptState: .hidden,
                reminderMode: mode
            ), .resting)
        }
    }

    func testSystemRestingNeverShowsFullScreenOverlay() {
        for trigger in [
            RestTrigger.screenLocked,
            .displayAsleep,
            .systemSleep,
        ] {
            for mode in ReminderMode.allCases {
                XCTAssertNil(ReminderPresentationPolicy.panel(
                    restRequired: true,
                    isResting: true,
                    promptState: .initialDecision,
                    reminderMode: mode
                ))
                XCTAssertNil(ReminderPresentationPolicy.overlay(
                    restRequired: true,
                    isResting: true,
                    activeRestTrigger: trigger,
                    promptState: .initialDecision,
                    reminderMode: mode
                ))
            }
        }
    }

    func testShortSystemRestRestoresUnresolvedTopPanelReminder() throws {
        let rest = ActiveRestSession(
            trigger: .screenLocked,
            startedAt: Date(timeIntervalSince1970: 1_000),
            startFatiguePercent: 120
        )
        var promptState = ReminderPromptState.initialDecision.applying(.restStarted(rest))

        XCTAssertNil(ReminderPresentationPolicy.overlay(
            restRequired: true,
            isResting: true,
            activeRestTrigger: .screenLocked,
            promptState: promptState,
            reminderMode: .topPanel
        ))

        let interruptedAttempt = RestAttempt(
            id: rest.id,
            trigger: .screenLocked,
            startedAt: rest.startedAt,
            endedAt: rest.startedAt.addingTimeInterval(10),
            startFatiguePercent: 120,
            duration: 10,
            endFatiguePercent: 60,
            outcome: .interrupted(.cancelled)
        )
        promptState = RestRuntimePolicy.promptStateAfterInterruptedSystemRest(
            restRequired: true
        )
        promptState = promptState.applying(.restInterrupted(interruptedAttempt))

        for mode in ReminderMode.allCases {
            XCTAssertNotNil(ReminderPresentationPolicy.panel(
                restRequired: true,
                isResting: false,
                promptState: promptState,
                reminderMode: mode
            ))
            XCTAssertNil(ReminderPresentationPolicy.overlay(
                restRequired: true,
                isResting: false,
                activeRestTrigger: nil,
                promptState: promptState,
                reminderMode: mode
            ))
        }
    }

    func testReminderModeMigrationKeepsOldTopModesAsTopPanel() {
        XCTAssertEqual(ReminderMode.systemNotification.rawValue, "nativeNotification")
        XCTAssertEqual(ReminderMode.restored(fromPersistedValue: "nativeNotification"), .systemNotification)
        XCTAssertEqual(ReminderMode.restored(fromPersistedValue: "progressive"), .topPanel)
        XCTAssertEqual(ReminderMode.restored(fromPersistedValue: "systemNotification"), .topPanel)
        XCTAssertEqual(ReminderMode.restored(fromPersistedValue: "topPanel"), .topPanel)
        XCTAssertEqual(ReminderMode.restored(fromPersistedValue: "fullScreen"), .fullScreen)
        XCTAssertEqual(ReminderMode.restored(fromPersistedValue: nil), .topPanel)
        XCTAssertEqual(ReminderMode.restored(fromPersistedValue: "unknown"), .topPanel)
    }
}

final class ReminderPreviewPolicyTests: XCTestCase {
    func testPreviewRetiresForAnyRealRestState() {
        XCTAssertFalse(ReminderPreviewPolicy.shouldDismissForRealState(
            restRequired: false,
            isResting: false
        ))
        XCTAssertTrue(ReminderPreviewPolicy.shouldDismissForRealState(
            restRequired: true,
            isResting: false
        ))
        XCTAssertTrue(ReminderPreviewPolicy.shouldDismissForRealState(
            restRequired: false,
            isResting: true
        ))
    }
}

final class ReminderPanelContentPolicyTests: XCTestCase {
    func testStableRealPanelKeepsItsContentUntilInvalidated() {
        let presentation = ReminderPanelPresentation()

        XCTAssertFalse(ReminderPanelContentPolicy.shouldReplace(
            hasContent: true,
            current: presentation,
            updated: presentation
        ))
        XCTAssertTrue(ReminderPanelContentPolicy.shouldReplace(
            hasContent: false,
            current: presentation,
            updated: presentation
        ))
        XCTAssertTrue(ReminderPanelContentPolicy.shouldReplace(
            hasContent: true,
            current: nil,
            updated: presentation
        ))
    }
}

final class ReminderPromptStateTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_000)

    func testThresholdThenDeferHidesPromptAndLaterFatigueDoesNotReopenIt() {
        let episode = OverloadEpisode(startedAt: now, peakFatiguePercent: 100)
        var state = ReminderPromptState.hidden.applying(.restRequired(episode))
        XCTAssertEqual(state, .initialDecision)

        state = state.applying(.continuedWorking(at: now.addingTimeInterval(1)))
        XCTAssertEqual(state, .hidden)

        state = state.applying(.fatigueChanged(
            from: 100,
            to: 180,
            at: now.addingTimeInterval(960)
        ))
        XCTAssertEqual(state, .hidden)
    }

    func testManualRestInterruptionReturnsAsTopPanelRetry() {
        let activeRest = ActiveRestSession(
            trigger: .manual,
            startedAt: now,
            startFatiguePercent: 180
        )
        var state = ReminderPromptState.initialDecision.applying(.restStarted(activeRest))
        XCTAssertEqual(state, .hidden)

        state = state.applying(.restInterrupted(makeAttempt(trigger: .manual)))
        XCTAssertEqual(state, .manualRetry)
    }

    func testSystemRestStartAndInterruptionPreservePreviousVisibility() {
        let activeRest = ActiveRestSession(
            trigger: .screenLocked,
            startedAt: now,
            startFatiguePercent: 180
        )
        let interrupted = FatigueEvent.restInterrupted(makeAttempt(trigger: .screenLocked))

        var hidden = ReminderPromptState.hidden.applying(.restStarted(activeRest))
        hidden = hidden.applying(interrupted)
        XCTAssertEqual(hidden, .hidden)

        var visible = ReminderPromptState.initialDecision.applying(.restStarted(activeRest))
        visible = visible.applying(interrupted)
        XCTAssertEqual(visible, .initialDecision)
    }

    func testCompletedRestAndOverloadBothHidePrompt() {
        let attempt = makeAttempt(trigger: .manual, completed: true)
        XCTAssertEqual(
            ReminderPromptState.manualRetry.applying(.restCompleted(attempt)),
            .hidden
        )

        let episode = OverloadEpisode(
            startedAt: now,
            endedAt: now.addingTimeInterval(20),
            peakFatiguePercent: 180,
            completedBy: .manual
        )
        XCTAssertEqual(
            ReminderPromptState.initialDecision.applying(.overloadCompleted(episode)),
            .hidden
        )
    }

    func testPersistenceMigrationPrefersNewStateAndMapsLegacyBoolean() {
        XCTAssertEqual(
            ReminderPromptState.restored(savedState: .manualRetry, legacyDecisionPending: false),
            .manualRetry
        )
        XCTAssertEqual(
            ReminderPromptState.restored(savedState: nil, legacyDecisionPending: true),
            .initialDecision
        )
        XCTAssertEqual(
            ReminderPromptState.restored(savedState: nil, legacyDecisionPending: false),
            .hidden
        )
        XCTAssertEqual(
            ReminderPromptState.restored(savedState: nil, legacyDecisionPending: nil),
            .hidden
        )
    }

    private func makeAttempt(
        trigger: RestTrigger,
        completed: Bool = false
    ) -> RestAttempt {
        RestAttempt(
            id: UUID(),
            trigger: trigger,
            startedAt: now,
            endedAt: now.addingTimeInterval(10),
            startFatiguePercent: 180,
            duration: 10,
            endFatiguePercent: completed ? 0 : 90,
            outcome: completed ? .completed : .interrupted(.cancelled)
        )
    }
}

final class RestRuntimePolicyTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_000)

    func testRestoringInterruptedActiveRestUsesTopPanelRetry() {
        let runtime = makeRuntime(
            promptState: .hidden,
            activeRest: ActiveRestSession(
                trigger: .manual,
                startedAt: now,
                startFatiguePercent: 180,
                elapsed: 8
            )
        )

        XCTAssertEqual(
            RestRuntimePolicy.restoredPromptState(from: runtime),
            .manualRetry
        )
    }

    func testRestoringHiddenStateWithoutActiveRestPreservesIntentionalDeferral() {
        XCTAssertEqual(
            RestRuntimePolicy.restoredPromptState(
                from: makeRuntime(promptState: .hidden)
            ),
            .hidden
        )
    }

    func testRestoringLegacyRequiredRestWithoutPromptMetadataShowsDecision() {
        XCTAssertEqual(
            RestRuntimePolicy.restoredPromptState(
                from: makeRuntime(promptState: nil)
            ),
            .initialDecision
        )
    }

    func testInterruptedActiveRestProducesOneBoundedRecoveryAttempt() throws {
        let attempt = try XCTUnwrap(
            RestRuntimePolicy.interruptedAttemptForRecovery(
                from: makeRuntime(
                    promptState: .hidden,
                    activeRest: ActiveRestSession(
                        trigger: .manual,
                        startedAt: now,
                        startFatiguePercent: 180,
                        elapsed: 8
                    )
                )
            )
        )

        XCTAssertEqual(attempt.startedAt, now)
        XCTAssertEqual(attempt.endedAt, now.addingTimeInterval(8))
        XCTAssertEqual(attempt.duration, 8)
        XCTAssertEqual(attempt.outcome, .interrupted(.cancelled))
    }

    func testAwayInputIsIgnoredInsteadOfInterruptingSystemRest() {
        XCTAssertTrue(RestRuntimePolicy.shouldIgnoreInput(systemAway: true))
        XCTAssertFalse(RestRuntimePolicy.shouldIgnoreInput(systemAway: false))
    }

    func testOnlyManualRestRequiresLiveInputMonitoring() {
        XCTAssertTrue(RestRuntimePolicy.shouldInterruptForUnavailableMonitoring(
            activeRestTrigger: .manual,
            inputPermissionGranted: false,
            inputMonitorRunning: false
        ))
        XCTAssertTrue(RestRuntimePolicy.shouldInterruptForUnavailableMonitoring(
            activeRestTrigger: .manual,
            inputPermissionGranted: true,
            inputMonitorRunning: false
        ))

        for trigger in [
            RestTrigger.screenLocked,
            .displayAsleep,
            .systemSleep,
        ] {
            XCTAssertFalse(RestRuntimePolicy.shouldInterruptForUnavailableMonitoring(
                activeRestTrigger: trigger,
                inputPermissionGranted: false,
                inputMonitorRunning: false
            ))
        }
    }

    func testInterruptedSystemRestReturnsToTopPanelEvenInFullScreenMode() {
        let promptState = RestRuntimePolicy.promptStateAfterInterruptedSystemRest(
            restRequired: true
        )

        XCTAssertEqual(promptState, .manualRetry)
        XCTAssertNotNil(ReminderPresentationPolicy.panel(
            restRequired: true,
            isResting: false,
            promptState: promptState,
            reminderMode: .fullScreen
        ))
        XCTAssertNil(ReminderPresentationPolicy.overlay(
            restRequired: true,
            isResting: false,
            activeRestTrigger: nil,
            promptState: promptState,
            reminderMode: .fullScreen
        ))
    }

    private func makeRuntime(
        promptState: ReminderPromptState?,
        activeRest: ActiveRestSession? = nil
    ) -> PersistedRuntimeState {
        PersistedRuntimeState(
            fatigue: 180,
            restRequired: true,
            overloadStartedAt: now.addingTimeInterval(-600),
            overloadEpisodeID: UUID(),
            continuousUsageDuration: 2_160,
            activeRest: activeRest,
            reminderPromptState: promptState,
            reminderDecisionPending: promptState.map { $0 != .hidden },
            savedAt: now
        )
    }
}

final class RestAttemptOutboxPolicyTests: XCTestCase {
    func testDuplicateAttemptsAreQueuedOnceAndRetryUntilSuccess() {
        let pendingAttempt = makePendingAttempt(id: UUID())
        var attempts: [PendingRestAttempt] = []

        RestAttemptOutboxPolicy.enqueue(pendingAttempt, into: &attempts)
        RestAttemptOutboxPolicy.enqueue(pendingAttempt, into: &attempts)
        XCTAssertEqual(attempts, [pendingAttempt])

        XCTAssertFalse(RestAttemptOutboxPolicy.drain(&attempts) { _ in false })
        XCTAssertEqual(attempts, [pendingAttempt])
        XCTAssertTrue(RestAttemptOutboxPolicy.drain(&attempts) { _ in true })
        XCTAssertTrue(attempts.isEmpty)
    }

    func testDrainStopsAtFirstFailureWithoutDroppingLaterAttempts() {
        let first = makePendingAttempt(id: UUID())
        let second = makePendingAttempt(id: UUID())
        var attempts = [first, second]
        var visited: [UUID] = []

        XCTAssertFalse(RestAttemptOutboxPolicy.drain(&attempts) { pendingAttempt in
            visited.append(pendingAttempt.id)
            return false
        })
        XCTAssertEqual(visited, [first.id])
        XCTAssertEqual(attempts, [first, second])
    }

    func testNormalizationKeepsFirstAttemptForEachStableID() {
        let id = UUID()
        let first = makePendingAttempt(id: id)
        var duplicate = first
        duplicate.overloadEpisodeID = UUID()

        XCTAssertEqual(
            RestAttemptOutboxPolicy.normalized([first, duplicate]),
            [first]
        )
    }

    func testDiscardAllRemovesPendingAttemptsBeforeDataClear() {
        var attempts = [makePendingAttempt(id: UUID())]

        RestAttemptOutboxPolicy.discardAll(&attempts)

        XCTAssertTrue(attempts.isEmpty)
    }

    private func makePendingAttempt(id: UUID) -> PendingRestAttempt {
        PendingRestAttempt(
            attempt: RestAttempt(
                id: id,
                trigger: .manual,
                startedAt: Date(timeIntervalSince1970: 1_000),
                endedAt: Date(timeIntervalSince1970: 1_010),
                startFatiguePercent: 180,
                duration: 10,
                endFatiguePercent: 90,
                outcome: .interrupted(.keyboard)
            ),
            overloadEpisodeID: UUID()
        )
    }
}

final class FatigueReminderMilestonesTests: XCTestCase {
    func testExactFirstThresholdIsConsumedButValueBelowItIsNot() {
        var tracker = FatigueReminderMilestones()

        XCTAssertNil(tracker.consumeNewMilestone(from: 98, to: 99))
        XCTAssertEqual(tracker.consumeNewMilestone(from: 99, to: 100), 1)
        XCTAssertEqual(tracker.lastReminderMultiple, 1)
    }

    func testSecondThresholdIsConsumedOnlyWhenTwoHundredIsReached() {
        var tracker = FatigueReminderMilestones(
            restoredLastReminderMultiple: 1,
            restRequired: true,
            fatigue: 100
        )

        XCTAssertNil(tracker.consumeNewMilestone(from: 100, to: 199.9))
        XCTAssertEqual(tracker.consumeNewMilestone(from: 199.9, to: 200), 2)
        XCTAssertNil(tracker.consumeNewMilestone(from: 200, to: 200.1))
    }

    func testCrossingSeveralThresholdsEmitsOnlyTheHighestMultiple() {
        var tracker = FatigueReminderMilestones(
            restoredLastReminderMultiple: 1,
            restRequired: true,
            fatigue: 180
        )

        XCTAssertEqual(tracker.consumeNewMilestone(from: 180, to: 420), 4)
        XCTAssertEqual(tracker.lastReminderMultiple, 4)
    }

    func testFatigueDecreaseNeverMovesMilestoneBackwardOrRepeatsIt() {
        var tracker = FatigueReminderMilestones(
            restoredLastReminderMultiple: 2,
            restRequired: true,
            fatigue: 250
        )

        XCTAssertNil(tracker.consumeNewMilestone(from: 250, to: 90))
        XCTAssertNil(tracker.consumeNewMilestone(from: 90, to: 200))
        XCTAssertEqual(tracker.lastReminderMultiple, 2)
        XCTAssertEqual(tracker.consumeNewMilestone(from: 200, to: 300), 3)
    }

    func testLegacyRestoreInfersHighestAlreadyPresentedMultiple() {
        let tracker = FatigueReminderMilestones(
            restoredLastReminderMultiple: nil,
            restRequired: true,
            fatigue: 250
        )

        XCTAssertEqual(tracker.lastReminderMultiple, 2)
    }

    func testCompletedRestResetAllowsANewFirstThreshold() {
        var tracker = FatigueReminderMilestones(
            restoredLastReminderMultiple: 4,
            restRequired: true,
            fatigue: 420
        )

        tracker.reset()

        XCTAssertEqual(tracker.lastReminderMultiple, 0)
        XCTAssertEqual(tracker.registerInitialReminder(fatigue: 100), 1)
    }
}
