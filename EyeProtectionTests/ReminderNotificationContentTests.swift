import XCTest
@testable import EyeProtection

final class ReminderNotificationContentTests: XCTestCase {
    func testWeakNotificationIsSilentAndCarriesItsEpisodeIdentity() {
        let episodeID = UUID()
        let content = ReminderNotificationContent.make(
            fatigueDisplay: "128%",
            episodeID: episodeID,
            reminderMultiple: 1
        )

        XCTAssertEqual(content.title, "疲劳度已达到 100%")
        XCTAssertTrue(content.body.contains("128%"))
        XCTAssertTrue(content.body.contains("点击通知开始休息"))
        XCTAssertNil(content.sound)
        XCTAssertEqual(
            content.userInfo[ReminderNotificationContent.episodeIDKey] as? String,
            episodeID.uuidString
        )
        XCTAssertEqual(
            content.userInfo[ReminderNotificationContent.reminderMultipleKey] as? Int,
            1
        )
        XCTAssertEqual(
            ReminderNotificationContent.requestIdentifier(
                episodeID: episodeID,
                reminderMultiple: 1
            ),
            "rest-required.\(episodeID.uuidString).1"
        )
    }

    func testLaterMilestoneUsesItsExactHundredPercentInTitleAndIdentifier() {
        let episodeID = UUID()
        let content = ReminderNotificationContent.make(
            fatigueDisplay: "205%",
            episodeID: episodeID,
            reminderMultiple: 2
        )

        XCTAssertEqual(content.title, "疲劳度已达到 200%")
        XCTAssertEqual(
            content.userInfo[ReminderNotificationContent.reminderMultipleKey] as? Int,
            2
        )
        XCTAssertEqual(
            ReminderNotificationContent.requestIdentifier(
                episodeID: episodeID,
                reminderMultiple: 2
            ),
            "rest-required.\(episodeID.uuidString).2"
        )
    }

    func testEnglishNotificationUsesSelectedLanguage() {
        let content = ReminderNotificationContent.make(
            fatigueDisplay: "205%",
            episodeID: UUID(),
            reminderMultiple: 2,
            language: .english
        )

        XCTAssertEqual(content.title, "Fatigue Reached 200%")
        XCTAssertEqual(
            content.body,
            "Current fatigue is 205%. Ignore this notification to keep working, or click it to start a rest."
        )
    }

    func testNotificationCopyUsesExplicitEnglishSelection() {
        let content = ReminderNotificationContent.make(
            fatigueDisplay: "205%",
            episodeID: UUID(),
            reminderMultiple: 2,
            language: .english
        )

        XCTAssertEqual(content.title, "Fatigue Reached 200%")
        XCTAssertEqual(
            content.body,
            "Current fatigue is 205%. Ignore this notification to keep working, or click it to start a rest."
        )
    }
}
