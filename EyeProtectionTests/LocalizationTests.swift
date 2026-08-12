import Foundation
import XCTest
@testable import EyeProtection

final class LocalizationTests: XCTestCase {
    func testPersistedLanguageRestorationDefaultsUnknownValuesToSystem() {
        XCTAssertEqual(AppLanguage.restored(fromPersistedValue: nil), .system)
        XCTAssertEqual(AppLanguage.restored(fromPersistedValue: ""), .system)
        XCTAssertEqual(AppLanguage.restored(fromPersistedValue: "removed-language"), .system)

        for language in AppLanguage.allCases {
            XCTAssertEqual(
                AppLanguage.restored(fromPersistedValue: language.rawValue),
                language
            )
        }
    }

    func testOnboardingPreferenceDefaultsToIncompleteAndPersistsCompletion() {
        let key = "onboardingCompleted"
        let defaults = UserDefaults.standard
        let previousValue = defaults.object(forKey: key)
        defer {
            if let previousValue {
                defaults.set(previousValue, forKey: key)
            } else {
                defaults.removeObject(forKey: key)
            }
        }

        defaults.removeObject(forKey: key)
        XCTAssertFalse(Preferences.onboardingCompleted)

        Preferences.onboardingCompleted = true
        XCTAssertTrue(Preferences.onboardingCompleted)
    }

    func testSystemLanguageResolutionUsesOnlySupportedLocalizations() {
        XCTAssertEqual(
            AppLanguage.system.resolved(preferredLanguages: ["zh-Hans-CN"]),
            .zhHans
        )
        XCTAssertEqual(
            AppLanguage.system.resolved(preferredLanguages: ["fr-FR", "zh_CN"]),
            .zhHans
        )
        XCTAssertEqual(
            AppLanguage.system.resolved(preferredLanguages: ["en-GB"]),
            .english
        )
        XCTAssertEqual(
            AppLanguage.system.resolved(preferredLanguages: ["zh-Hant-TW"]),
            .english
        )
        XCTAssertEqual(AppLanguage.system.resolved(preferredLanguages: []), .english)
        XCTAssertEqual(
            AppLanguage.zhHans.resolved(preferredLanguages: ["en-US"]),
            .zhHans
        )
        XCTAssertEqual(
            AppLanguage.english.resolved(preferredLanguages: ["zh-Hans"]),
            .english
        )
    }

    func testEnglishAndChineseResourcesContainExactlyEverySemanticKey() throws {
        let english = try localizationDictionary("en")
        let chinese = try localizationDictionary("zh-Hans")
        let expectedKeys = Set(L10nKey.allCases.map(\.rawValue))

        XCTAssertEqual(Set(english.keys), expectedKeys)
        XCTAssertEqual(Set(chinese.keys), expectedKeys)
        XCTAssertTrue(english.values.allSatisfy { !$0.isEmpty })
        XCTAssertTrue(chinese.values.allSatisfy { !$0.isEmpty })
    }

    func testExplicitLanguageSelectionReturnsLocalizedModelCopy() {
        XCTAssertEqual(
            AppLocalization.string(.presenceWaitingForFirstInput, language: .english),
            "Waiting for first input"
        )
        XCTAssertEqual(
            AppLocalization.string(.presenceWaitingForFirstInput, language: .zhHans),
            "等待首次输入"
        )
        XCTAssertEqual(ReminderMode.fullScreen.displayName(language: .english), "Full Screen")
        XCTAssertEqual(ReminderMode.fullScreen.displayName, "全屏提醒")
        XCTAssertEqual(ReminderTheme.forestLight.displayName(language: .english), "Forest Light")
        XCTAssertEqual(ReminderTheme.forestLight.displayName, "林间天光")
        XCTAssertEqual(ReminderDecisionAction.deferRest.title(language: .english), "Not Now")
        XCTAssertEqual(ReminderDecisionAction.deferRest.title, "暂不休息")
    }

    func testDynamicFormatsAndPluralQuantitiesUseSelectedLanguage() {
        XCTAssertEqual(AppLocalization.duration(1, language: .english), "1 second")
        XCTAssertEqual(AppLocalization.duration(2, language: .english), "2 seconds")
        XCTAssertEqual(AppLocalization.duration(60, language: .english), "1 minute")
        XCTAssertEqual(AppLocalization.duration(120, language: .english), "2 minutes")
        XCTAssertEqual(AppLocalization.duration(3_600, language: .english), "1 hour")
        XCTAssertEqual(AppLocalization.duration(5_280, language: .english), "1 hour 28 minutes")
        XCTAssertEqual(AppLocalization.times(1, language: .english), "1 time")
        XCTAssertEqual(AppLocalization.times(2, language: .english), "2 times")

        XCTAssertEqual(AppLocalization.duration(1, language: .zhHans), "1 秒")
        XCTAssertEqual(AppLocalization.duration(120, language: .zhHans), "2 分钟")
        XCTAssertEqual(AppLocalization.duration(5_280, language: .zhHans), "1 小时 28 分钟")
        XCTAssertEqual(AppLocalization.times(2, language: .zhHans), "2 次")
        XCTAssertEqual(AppLocalization.fatiguePercent(100, language: .english), "100%")
        XCTAssertEqual(AppLocalization.fatiguePercent(100, language: .zhHans), "100%")

        XCTAssertEqual(
            AppLocalization.format(
                .notificationMilestoneTitle,
                language: .english,
                arguments: [3]
            ),
            "Fatigue Reached 3%"
        )
        XCTAssertEqual(
            AppLocalization.format(
                .notificationMilestoneTitle,
                language: .zhHans,
                arguments: [3]
            ),
            "疲劳度已达到 3%"
        )
    }

    private func localizationDictionary(_ identifier: String) throws -> [String: String] {
        let language: AppLanguage = identifier == "zh-Hans" ? .zhHans : .english
        let data = try Data(contentsOf: try XCTUnwrap(
            AppLocalization.localizedResourceURL(for: language)
        ))
        let propertyList = try PropertyListSerialization.propertyList(
            from: data,
            options: [],
            format: nil
        )
        return try XCTUnwrap(propertyList as? [String: String])
    }
}
