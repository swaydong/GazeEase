import XCTest
@testable import EyeProtection

final class AnalyticsRefreshPolicyTests: XCTestCase {
    func testSamplingPolicyUsesFiveMinuteCadenceAndCriticalFlushes() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)

        XCTAssertTrue(AnalyticsSamplingPolicy.shouldFlush(
            lastFlushAt: nil,
            now: start,
            force: false
        ))
        XCTAssertFalse(AnalyticsSamplingPolicy.shouldFlush(
            lastFlushAt: start,
            now: start.addingTimeInterval(5 * 60 - 1),
            force: false
        ))
        XCTAssertTrue(AnalyticsSamplingPolicy.shouldFlush(
            lastFlushAt: start,
            now: start.addingTimeInterval(5 * 60),
            force: false
        ))
        XCTAssertTrue(AnalyticsSamplingPolicy.shouldFlush(
            lastFlushAt: start,
            now: start.addingTimeInterval(1),
            force: true
        ))
        XCTAssertTrue(AnalyticsSamplingPolicy.shouldFlush(
            lastFlushAt: start,
            now: start,
            force: true
        ))
        XCTAssertTrue(AnalyticsSamplingPolicy.shouldCommitUsageSessionEnd(
            tailFlushSucceeded: true
        ))
        XCTAssertFalse(AnalyticsSamplingPolicy.shouldCommitUsageSessionEnd(
            tailFlushSucceeded: false
        ))
    }

    func testSamplingPolicyFlushesAfterClockRollback() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)

        XCTAssertTrue(AnalyticsSamplingPolicy.shouldFlush(
            lastFlushAt: start,
            now: start.addingTimeInterval(-1),
            force: false
        ))
    }

    func testPublicationPolicyOnlyEmitsWhenVisibleValuesChange() {
        XCTAssertFalse(AppModelPublicationPolicy.shouldPublishFatigue(
            current: 63.1,
            updated: 63.9
        ))
        XCTAssertTrue(AppModelPublicationPolicy.shouldPublishFatigue(
            current: 63.9,
            updated: 64
        ))
        XCTAssertFalse(AppModelPublicationPolicy.shouldPublishFatigue(
            current: 1_001,
            updated: 1_040
        ))
        XCTAssertTrue(AppModelPublicationPolicy.shouldPublishFatigue(
            current: 0.4,
            updated: 0
        ))

        XCTAssertFalse(AppModelPublicationPolicy.shouldPublishDuration(
            current: 61,
            updated: 119
        ))
        XCTAssertTrue(AppModelPublicationPolicy.shouldPublishDuration(
            current: 119,
            updated: 120
        ))
        XCTAssertTrue(AppModelPublicationPolicy.shouldPublishDuration(
            current: 0.4,
            updated: 0
        ))
    }

    func testRefreshPolicyHandlesFreshnessClockChangesAndMidnight() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let dayStart = Date(timeIntervalSince1970: 1_800_000_000)
        let lastRefresh = dayStart.addingTimeInterval(60 * 60)

        XCTAssertTrue(AnalyticsRefreshPolicy.shouldRefresh(
            lastRefreshAt: nil,
            now: lastRefresh,
            maxAge: 60,
            calendar: calendar
        ))
        XCTAssertFalse(AnalyticsRefreshPolicy.shouldRefresh(
            lastRefreshAt: lastRefresh,
            now: lastRefresh.addingTimeInterval(59),
            maxAge: 60,
            calendar: calendar
        ))
        XCTAssertTrue(AnalyticsRefreshPolicy.shouldRefresh(
            lastRefreshAt: lastRefresh,
            now: lastRefresh.addingTimeInterval(60),
            maxAge: 60,
            calendar: calendar
        ))
        XCTAssertTrue(AnalyticsRefreshPolicy.shouldRefresh(
            lastRefreshAt: lastRefresh,
            now: lastRefresh.addingTimeInterval(-1),
            maxAge: 60,
            calendar: calendar
        ))

        let beforeMidnight = calendar.startOfDay(for: dayStart)
            .addingTimeInterval(24 * 60 * 60 - 10)
        XCTAssertTrue(AnalyticsRefreshPolicy.shouldRefresh(
            lastRefreshAt: beforeMidnight,
            now: beforeMidnight.addingTimeInterval(20),
            maxAge: 60,
            calendar: calendar
        ))
        XCTAssertTrue(AnalyticsRefreshPolicy.shouldRefresh(
            lastRefreshAt: lastRefresh,
            now: lastRefresh,
            maxAge: 0,
            calendar: calendar
        ))
    }
}
