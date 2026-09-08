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

    func testShortSystemRestBelowThresholdHidesReminder() {
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
            restRequired: interruptedAttempt.endFatiguePercent >= 100
        )
        promptState = promptState.applying(.restInterrupted(interruptedAttempt))

        for mode in ReminderMode.allCases {
            XCTAssertNil(ReminderPresentationPolicy.panel(
                restRequired: false,
                isResting: false,
                promptState: promptState,
                reminderMode: mode
            ))
            XCTAssertNil(ReminderPresentationPolicy.overlay(
                restRequired: false,
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

        state = state.applying(.restInterrupted(makeAttempt(trigger: .manual, endFatigue: 110)))
        XCTAssertEqual(state, .manualRetry)
    }

    func testInterruptionBelowThresholdHidesEveryPreviousPromptState() {
        for state in [ReminderPromptState.hidden, .initialDecision, .manualRetry] {
            for trigger in [RestTrigger.manual, .screenLocked] {
                XCTAssertEqual(
                    state.applying(.restInterrupted(makeAttempt(trigger: trigger))),
                    .hidden
                )
            }
            XCTAssertEqual(
                state.applying(.fatigueChanged(from: 180, to: 90, at: now)),
                .hidden
            )
        }
    }

    func testSystemRestStartAndInterruptionPreservePreviousVisibility() {
        let activeRest = ActiveRestSession(
            trigger: .screenLocked,
            startedAt: now,
            startFatiguePercent: 180
        )
        let interrupted = FatigueEvent.restInterrupted(
            makeAttempt(trigger: .screenLocked, endFatigue: 110)
        )

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
        completed: Bool = false,
        endFatigue: Double = 90
    ) -> RestAttempt {
        RestAttempt(
            id: UUID(),
            trigger: trigger,
            startedAt: now,
            endedAt: now.addingTimeInterval(10),
            startFatiguePercent: 180,
            duration: 10,
            endFatiguePercent: completed ? 0 : endFatigue,
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

    func testFatigueDecreaseAboveThresholdDoesNotRepeatMilestones() {
        var tracker = FatigueReminderMilestones(
            restoredLastReminderMultiple: 2,
            restRequired: true,
            fatigue: 250
        )

        XCTAssertNil(tracker.consumeNewMilestone(from: 250, to: 110))
        XCTAssertNil(tracker.consumeNewMilestone(from: 110, to: 200))
        XCTAssertEqual(tracker.lastReminderMultiple, 2)
        XCTAssertEqual(tracker.consumeNewMilestone(from: 200, to: 300), 3)
    }

    func testRecoveryBelowThresholdRearmsTheFirstAndLaterMilestones() {
        var tracker = FatigueReminderMilestones(
            restoredLastReminderMultiple: 2,
            restRequired: true,
            fatigue: 250
        )

        XCTAssertNil(tracker.consumeNewMilestone(from: 250, to: 90))
        XCTAssertEqual(tracker.lastReminderMultiple, 0)
        XCTAssertNil(tracker.consumeNewMilestone(from: 90, to: 99.9))
        XCTAssertEqual(tracker.consumeNewMilestone(from: 99.9, to: 100), 1)
        XCTAssertEqual(tracker.consumeNewMilestone(from: 100, to: 200), 2)
    }

    func testRestorationBelowThresholdDiscardsOldMilestone() {
        var tracker = FatigueReminderMilestones(
            restoredLastReminderMultiple: 4,
            restRequired: true,
            fatigue: 87
        )

        XCTAssertEqual(tracker.lastReminderMultiple, 0)
        XCTAssertEqual(tracker.consumeNewMilestone(from: 87, to: 100), 1)
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

final class PartialRecoveryReminderFlowTests: XCTestCase {
    func testPartialRecoveryWaitsForOneHundredAndKeepsTheRestEpisode() throws {
        var flow = ReminderFlow()
        flow.use(for: 180)
        let episodeID = try XCTUnwrap(flow.episodeID)
        flow.rest(for: 10)

        XCTAssertEqual(flow.engine.snapshot.fatiguePercent, 90, accuracy: 0.000_001)
        XCTAssertEqual(flow.overlay(mode: .fullScreen), .resting)
        let events = flow.interrupt()
        guard case let .restInterrupted(attempt) = try XCTUnwrap(events.first) else {
            return XCTFail("Partial rest must retain its interrupted outcome")
        }
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(attempt.outcome, .interrupted(.keyboard))
        XCTAssertEqual(attempt.trigger, .manual)
        XCTAssertEqual(attempt.duration, 10)
        XCTAssertTrue(flow.engine.snapshot.restRequired)
        XCTAssertFalse(flow.engine.snapshot.needsRestReminder)
        XCTAssertEqual(flow.engine.snapshot.activeOverloadEpisode?.id, episodeID)
        assertNoReminder(flow)

        flow.use(for: 9.9)
        XCTAssertEqual(flow.engine.snapshot.fatiguePercent, 99.9, accuracy: 0.000_001)
        assertNoReminder(flow)
        flow.use(for: 0.1)
        XCTAssertTrue(flow.engine.snapshot.needsRestReminder)
        XCTAssertNotNil(flow.panel(mode: .topPanel))
        XCTAssertEqual(flow.overlay(mode: .fullScreen), .decision)
        XCTAssertEqual(flow.reminderMultiples, [1, 1])
        let continuedWorking = flow.engine.recordContinueWorking(at: flow.now)
        flow.apply(continuedWorking)
        flow.use(for: 100)
        XCTAssertNotNil(flow.panel(mode: .topPanel))
        XCTAssertEqual(flow.reminderMultiples, [1, 1, 2])
        XCTAssertEqual(flow.episodeID, episodeID)
    }

    func testTenSecondRestAtOrAboveOneHundredStillOffersRetry() {
        for startingFatigue in [200.0, 220.0] {
            var flow = ReminderFlow()
            flow.use(for: startingFatigue)
            flow.rest(for: 10)
            _ = flow.interrupt()

            XCTAssertEqual(
                flow.engine.snapshot.fatiguePercent,
                startingFatigue / 2,
                accuracy: 0.000_001
            )
            XCTAssertTrue(flow.engine.snapshot.needsRestReminder)
            XCTAssertEqual(flow.prompt, .manualRetry)
            XCTAssertEqual(flow.milestones.lastReminderMultiple, 2)
            for mode in ReminderMode.allCases {
                XCTAssertNotNil(flow.panel(mode: mode))
                XCTAssertNil(flow.overlay(mode: mode))
            }
        }
    }

    func testFullRestStillClearsFatigueAndCompletesTheEpisode() {
        var flow = ReminderFlow()
        flow.use(for: 250)
        flow.rest(for: 20)

        XCTAssertEqual(flow.engine.snapshot.fatiguePercent, 0)
        XCTAssertFalse(flow.engine.snapshot.restRequired)
        XCTAssertFalse(flow.engine.isResting)
        XCTAssertNil(flow.episodeID)
        XCTAssertEqual(flow.milestones.lastReminderMultiple, 0)
        assertNoReminder(flow)
        flow.use(for: 100)
        XCTAssertEqual(flow.reminderMultiples, [2, 1])
    }

    func testReturningFromShortSystemRestRespectsRecoveredFatigue() {
        for startingFatigue in [180.0, 200.0, 220.0] {
            var flow = ReminderFlow()
            flow.use(for: startingFatigue)
            flow.rest(for: 10, trigger: .screenLocked)
            _ = flow.interrupt(systemReturn: true)

            if startingFatigue < 200 {
                assertNoReminder(flow)
            } else {
                XCTAssertEqual(flow.prompt, .manualRetry)
                XCTAssertNotNil(flow.panel(mode: .fullScreen))
                XCTAssertNil(flow.overlay(mode: .fullScreen))
            }
        }
    }

    func testLegacyLowFatigueRuntimeStaysHiddenAndRearmsAfterRestart() throws {
        let date = Date(timeIntervalSince1970: 1_000)
        for hadActiveRest in [false, true] {
            let runtime = PersistedRuntimeState(
                fatigue: 87,
                restRequired: true,
                overloadStartedAt: date.addingTimeInterval(-600),
                overloadEpisodeID: UUID(),
                continuousUsageDuration: 2_160,
                activeRest: hadActiveRest ? ActiveRestSession(
                    trigger: .manual,
                    startedAt: date.addingTimeInterval(-10),
                    startFatiguePercent: 174,
                    elapsed: 10
                ) : nil,
                reminderPromptState: .manualRetry,
                reminderDecisionPending: true,
                lastReminderMultiple: 2,
                savedAt: date
            )
            let recovered = RestRuntimePolicy.interruptedAttemptForRecovery(from: runtime)
            XCTAssertEqual(recovered != nil, hadActiveRest)
            if hadActiveRest {
                let attempt = try XCTUnwrap(recovered)
                XCTAssertEqual(attempt.endFatiguePercent, 87)
                XCTAssertEqual(attempt.outcome, .interrupted(.cancelled))
            }
            var flow = ReminderFlow(runtime: runtime)
            assertNoReminder(flow)
            XCTAssertEqual(flow.milestones.lastReminderMultiple, 0)
            flow.use(for: 13)
            XCTAssertEqual(flow.reminderMultiples, [1])
            XCTAssertNotNil(flow.panel(mode: .topPanel))
            XCTAssertEqual(flow.episodeID, runtime.overloadEpisodeID)
        }
    }

    func testLongerWorkTargetBelowThresholdHidesAndRearmsReminder() throws {
        var flow = ReminderFlow()
        flow.use(for: 180)
        let episodeID = flow.episodeID
        let events = try XCTUnwrap(flow.engine.updateDurations(
            usageDurationForOneHundredPercent: 200,
            requiredContinuousRestDuration: 20,
            at: flow.now
        ))
        flow.apply(events)

        XCTAssertEqual(flow.engine.snapshot.fatiguePercent, 90)
        XCTAssertEqual(flow.milestones.lastReminderMultiple, 0)
        assertNoReminder(flow)
        flow.use(for: 20)
        XCTAssertNotNil(flow.panel(mode: .topPanel))
        XCTAssertEqual(flow.reminderMultiples, [1, 1])
        XCTAssertEqual(flow.episodeID, episodeID)
    }

    private func assertNoReminder(
        _ flow: ReminderFlow,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(flow.prompt, .hidden, file: file, line: line)
        for mode in ReminderMode.allCases {
            XCTAssertNil(flow.panel(mode: mode), file: file, line: line)
            XCTAssertNil(flow.overlay(mode: mode), file: file, line: line)
        }
    }

    private struct ReminderFlow {
        var engine = FatigueEngine(usageDurationForOneHundredPercent: 100)
        var prompt = ReminderPromptState.hidden
        var milestones = FatigueReminderMilestones()
        var episodeID: UUID?
        var reminderMultiples: [Int] = []
        var now = Date(timeIntervalSince1970: 1_000)

        init(runtime: PersistedRuntimeState? = nil) {
            guard let runtime else { return }
            // AppModel records a recovered attempt before resuming with no active rest.
            engine = FatigueEngine(
                snapshot: FatigueSnapshot(
                    fatiguePercent: runtime.fatigue,
                    restRequired: runtime.restRequired,
                    activeOverloadEpisode: OverloadEpisode(
                        id: runtime.overloadEpisodeID ?? UUID(),
                        startedAt: runtime.overloadStartedAt ?? runtime.savedAt,
                        peakFatiguePercent: 180
                    )
                ),
                usageDurationForOneHundredPercent: 100
            )
            prompt = RestRuntimePolicy.restoredPromptState(from: runtime)
            milestones = FatigueReminderMilestones(
                restoredLastReminderMultiple: runtime.lastReminderMultiple,
                restRequired: runtime.restRequired,
                fatigue: runtime.fatigue
            )
            episodeID = runtime.overloadEpisodeID
            now = runtime.savedAt
        }

        mutating func use(for seconds: TimeInterval) {
            now.addTimeInterval(seconds)
            let events = engine.accrueUsage(for: seconds, endingAt: now)
            apply(events)
        }

        mutating func rest(for seconds: TimeInterval, trigger: RestTrigger = .manual) {
            let started = engine.beginRest(trigger: trigger, at: now)
            apply(started)
            now.addTimeInterval(seconds)
            let advanced = engine.advanceRest(by: seconds, endingAt: now)
            apply(advanced)
        }

        mutating func interrupt(systemReturn: Bool = false) -> [FatigueEvent] {
            let events = engine.interruptRest(
                reason: systemReturn ? .cancelled : .keyboard,
                at: now
            )
            if systemReturn {
                prompt = RestRuntimePolicy.promptStateAfterInterruptedSystemRest(
                    restRequired: engine.snapshot.needsRestReminder
                )
            }
            apply(events)
            return events
        }

        mutating func apply(_ events: [FatigueEvent]) {
            // Compose the real domain and presentation policies in AppModel's event order.
            for event in events {
                prompt = prompt.applying(event)
                switch event {
                case let .fatigueChanged(from, to, _):
                    if episodeID != nil,
                       let multiple = milestones.consumeNewMilestone(from: from, to: to) {
                        prompt = .initialDecision
                        reminderMultiples.append(multiple)
                    }
                case let .restRequired(episode):
                    episodeID = episode.id
                    if let multiple = milestones.registerInitialReminder(
                        fatigue: episode.peakFatiguePercent
                    ) {
                        reminderMultiples.append(multiple)
                    }
                case .restCompleted:
                    milestones.reset()
                case .overloadCompleted:
                    milestones.reset()
                    episodeID = nil
                case .restStarted, .restInterrupted, .continuedWorking:
                    break
                }
            }
        }

        func panel(mode: ReminderMode) -> ReminderPanelPresentation? {
            ReminderPresentationPolicy.panel(
                restRequired: engine.snapshot.needsRestReminder,
                isResting: engine.isResting,
                promptState: prompt,
                reminderMode: mode
            )
        }

        func overlay(mode: ReminderMode) -> ReminderOverlayPhase? {
            ReminderPresentationPolicy.overlay(
                restRequired: engine.snapshot.needsRestReminder,
                isResting: engine.isResting,
                activeRestTrigger: engine.snapshot.activeRest?.trigger,
                promptState: prompt,
                reminderMode: mode
            )
        }
    }
}
