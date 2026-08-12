import AppKit
import XCTest
@testable import EyeProtection

@MainActor
final class ReminderThemeTests: XCTestCase {
    func testKnownValuesRestoreWithoutChangingStableIdentifiers() {
        for theme in ReminderTheme.allCases {
            XCTAssertEqual(
                ReminderTheme.restored(fromPersistedValue: theme.rawValue),
                theme
            )
        }
    }

    func testMissingAndUnknownValuesRestoreDefaultTheme() {
        XCTAssertEqual(ReminderTheme.restored(fromPersistedValue: nil), .quietHorizon)
        XCTAssertEqual(
            ReminderTheme.restored(fromPersistedValue: "removed-theme"),
            .quietHorizon
        )
    }

    func testEveryThemeHasAUsableBundledBackground() throws {
        for theme in ReminderTheme.allCases {
            let background = try XCTUnwrap(
                NSImage(named: theme.backgroundAssetName),
                "Missing asset for \(theme.rawValue)"
            )
            XCTAssertEqual(
                background.size.width / background.size.height,
                1.6,
                accuracy: 0.001
            )

            let preview = try XCTUnwrap(
                NSImage(named: theme.previewAssetName),
                "Missing preview asset for \(theme.rawValue)"
            )
            XCTAssertEqual(preview.size.width / preview.size.height, 1.6, accuracy: 0.001)
        }
    }

    func testThemePickerFitsInsideTheSettingsFormWithSafetyMargin() {
        XCTAssertLessThanOrEqual(ReminderThemePickerLayout.totalWidth, 472)
        XCTAssertEqual(ReminderThemePickerLayout.cardSize.height, 82)
    }

    func testEveryThemeUsesADistinctSettingsPreviewFocus() {
        let focuses = Set(ReminderTheme.allCases.map {
            $0.settingsCardTreatment.focus
        })

        XCTAssertEqual(focuses.count, ReminderTheme.allCases.count)
        for theme in ReminderTheme.allCases {
            XCTAssertGreaterThanOrEqual(theme.settingsCardTreatment.scale, 1)
        }
    }

    func testRandomRotationSchedulesWithoutChangingThemeImmediately() {
        let now = Date(timeIntervalSince1970: 1_000)
        var scheduler = ReminderThemeRotationScheduler()

        XCTAssertNil(scheduler.advance(
            enabled: true,
            interval: 600,
            at: now,
            currentTheme: .quietHorizon,
            shouldDefer: false,
            randomValue: 0
        ))
        XCTAssertEqual(scheduler.nextChangeAt, now.addingTimeInterval(600))
        XCTAssertNil(scheduler.pendingTheme)
    }

    func testRandomRotationDoesNotRunBeforeDeadline() {
        let now = Date(timeIntervalSince1970: 1_000)
        var scheduler = ReminderThemeRotationScheduler(
            nextChangeAt: now.addingTimeInterval(600)
        )

        XCTAssertNil(scheduler.advance(
            enabled: true,
            interval: 600,
            at: now.addingTimeInterval(599),
            currentTheme: .quietHorizon,
            shouldDefer: false,
            randomValue: 0
        ))
        XCTAssertEqual(scheduler.nextChangeAt, now.addingTimeInterval(600))
        XCTAssertNil(scheduler.pendingTheme)
    }

    func testRandomRotationRunsExactlyAtDeadline() throws {
        let dueAt = Date(timeIntervalSince1970: 1_600)
        var scheduler = ReminderThemeRotationScheduler(nextChangeAt: dueAt)

        let nextTheme = try XCTUnwrap(scheduler.advance(
            enabled: true,
            interval: 600,
            at: dueAt,
            currentTheme: .quietHorizon,
            shouldDefer: false,
            randomValue: 0
        ))

        XCTAssertNotEqual(nextTheme, .quietHorizon)
        XCTAssertEqual(scheduler.nextChangeAt, dueAt.addingTimeInterval(600))
        XCTAssertNil(scheduler.pendingTheme)
    }

    func testOverdueRotationOnlyRunsOnceAndReschedulesFromNow() throws {
        let dueAt = Date(timeIntervalSince1970: 1_000)
        let resumedAt = dueAt.addingTimeInterval(3_600)
        var scheduler = ReminderThemeRotationScheduler(nextChangeAt: dueAt)

        let nextTheme = try XCTUnwrap(scheduler.advance(
            enabled: true,
            interval: 600,
            at: resumedAt,
            currentTheme: .quietHorizon,
            shouldDefer: false,
            randomValue: 0
        ))
        XCTAssertNotEqual(nextTheme, .quietHorizon)
        XCTAssertEqual(scheduler.nextChangeAt, resumedAt.addingTimeInterval(600))

        XCTAssertNil(scheduler.advance(
            enabled: true,
            interval: 600,
            at: resumedAt,
            currentTheme: nextTheme,
            shouldDefer: false,
            randomValue: 1
        ))
    }

    func testDueRandomRotationNeverRepeatsCurrentTheme() throws {
        let now = Date(timeIntervalSince1970: 1_000)
        for randomValue in UInt64(0)..<UInt64(24) {
            var scheduler = ReminderThemeRotationScheduler(nextChangeAt: now)
            let nextTheme = try XCTUnwrap(scheduler.advance(
                enabled: true,
                interval: 600,
                at: now,
                currentTheme: .forestLight,
                shouldDefer: false,
                randomValue: randomValue
            ))

            XCTAssertNotEqual(nextTheme, .forestLight)
            XCTAssertEqual(scheduler.nextChangeAt, now.addingTimeInterval(600))
        }
    }

    func testDueRotationDefersDuringRestAndAppliesOnceAfterward() throws {
        let dueAt = Date(timeIntervalSince1970: 1_000)
        var scheduler = ReminderThemeRotationScheduler(nextChangeAt: dueAt)

        XCTAssertNil(scheduler.advance(
            enabled: true,
            interval: 600,
            at: dueAt,
            currentTheme: .quietHorizon,
            shouldDefer: true,
            randomValue: 0
        ))
        let pendingTheme = try XCTUnwrap(scheduler.pendingTheme)
        XCTAssertNotEqual(pendingTheme, .quietHorizon)
        XCTAssertNil(scheduler.nextChangeAt)

        XCTAssertNil(scheduler.advance(
            enabled: true,
            interval: 600,
            at: dueAt.addingTimeInterval(20),
            currentTheme: .quietHorizon,
            shouldDefer: true,
            randomValue: 1
        ))
        XCTAssertEqual(scheduler.pendingTheme, pendingTheme)

        let appliedTheme = scheduler.advance(
            enabled: true,
            interval: 600,
            at: dueAt.addingTimeInterval(21),
            currentTheme: .quietHorizon,
            shouldDefer: false,
            randomValue: 2
        )
        XCTAssertEqual(appliedTheme, pendingTheme)
        XCTAssertNil(scheduler.pendingTheme)
        XCTAssertEqual(
            scheduler.nextChangeAt,
            dueAt.addingTimeInterval(621)
        )
    }

    func testDueRotationDefersWhileReminderPromptIsVisible() throws {
        let dueAt = Date(timeIntervalSince1970: 1_500)
        var scheduler = ReminderThemeRotationScheduler(nextChangeAt: dueAt)

        XCTAssertNil(scheduler.advance(
            enabled: true,
            interval: 600,
            at: dueAt,
            currentTheme: .quietHorizon,
            shouldDefer: true,
            randomValue: 1
        ))
        let pendingTheme = try XCTUnwrap(scheduler.pendingTheme)
        XCTAssertNil(scheduler.nextChangeAt)

        let safeAt = dueAt.addingTimeInterval(30)
        XCTAssertEqual(scheduler.advance(
            enabled: true,
            interval: 600,
            at: safeAt,
            currentTheme: .quietHorizon,
            shouldDefer: false,
            randomValue: 2
        ), pendingTheme)
        XCTAssertNil(scheduler.pendingTheme)
        XCTAssertEqual(scheduler.nextChangeAt, safeAt.addingTimeInterval(600))
    }

    func testRestoredPendingThemeIsAppliedAfterRestartWithoutRepeatingCurrentTheme() throws {
        let now = Date(timeIntervalSince1970: 2_000)
        var scheduler = ReminderThemeRotationScheduler(
            nextChangeAt: nil,
            pendingTheme: .alpineMist
        )

        let appliedTheme = try XCTUnwrap(scheduler.advance(
            enabled: true,
            interval: 300,
            at: now,
            currentTheme: .alpineMist,
            shouldDefer: false,
            randomValue: 0
        ))

        XCTAssertNotEqual(appliedTheme, .alpineMist)
        XCTAssertNil(scheduler.pendingTheme)
        XCTAssertEqual(scheduler.nextChangeAt, now.addingTimeInterval(300))
    }

    func testDisablingRotationClearsRestoredScheduleAndPendingTheme() {
        let now = Date(timeIntervalSince1970: 2_000)
        var scheduler = ReminderThemeRotationScheduler(
            nextChangeAt: now,
            pendingTheme: .twilightDunes
        )

        XCTAssertNil(scheduler.advance(
            enabled: false,
            interval: 300,
            at: now,
            currentTheme: .quietHorizon,
            shouldDefer: false,
            randomValue: 0
        ))
        XCTAssertNil(scheduler.nextChangeAt)
        XCTAssertNil(scheduler.pendingTheme)
    }

    func testManualConfigurationResetsPendingThemeAndDeadline() {
        let originalDueAt = Date(timeIntervalSince1970: 1_000)
        let changedAt = originalDueAt.addingTimeInterval(300)
        var scheduler = ReminderThemeRotationScheduler(
            nextChangeAt: originalDueAt,
            pendingTheme: .twilightDunes
        )

        scheduler.configure(enabled: true, interval: 900, at: changedAt)

        XCTAssertNil(scheduler.pendingTheme)
        XCTAssertEqual(scheduler.nextChangeAt, changedAt.addingTimeInterval(900))
    }

    func testReconfiguringRotationClearsPendingThemeAndRestartsDeadline() {
        let now = Date(timeIntervalSince1970: 3_000)
        var scheduler = ReminderThemeRotationScheduler(
            nextChangeAt: now.addingTimeInterval(-1),
            pendingTheme: .twilightDunes
        )

        scheduler.configure(enabled: true, interval: 900, at: now)

        XCTAssertNil(scheduler.pendingTheme)
        XCTAssertEqual(scheduler.nextChangeAt, now.addingTimeInterval(900))
    }

    func testRandomRotationIntervalIsClampedToFiveMinutesThroughOneDay() {
        XCTAssertEqual(Preferences.normalizedRandomThemeRotationIntervalMinutes(1), 5)
        XCTAssertEqual(Preferences.normalizedRandomThemeRotationIntervalMinutes(60), 60)
        XCTAssertEqual(Preferences.normalizedRandomThemeRotationIntervalMinutes(2_000), 1_440)
    }

    func testRandomRotationDefaultsToOptInOneHourScheduling() {
        let now = Date(timeIntervalSince1970: 4_000)
        var scheduler = ReminderThemeRotationScheduler()

        XCTAssertEqual(Preferences.defaultRandomThemeRotationIntervalMinutes, 60)
        XCTAssertEqual(Preferences.randomThemeRotationIntervalMinutesRange, 5...1_440)
        XCTAssertTrue(
            Preferences.randomThemeRotationIntervalMinutesRange.contains(
                Preferences.defaultRandomThemeRotationIntervalMinutes
            )
        )

        scheduler.configure(
            enabled: false,
            interval: TimeInterval(Preferences.defaultRandomThemeRotationIntervalMinutes * 60),
            at: now
        )
        XCTAssertNil(scheduler.nextChangeAt)
        XCTAssertNil(scheduler.pendingTheme)
    }

}
