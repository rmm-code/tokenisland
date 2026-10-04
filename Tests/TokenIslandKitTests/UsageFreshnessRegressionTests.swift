import XCTest
@testable import TokenIslandKit

@MainActor
final class UsageFreshnessRegressionTests: XCTestCase {
    func testSeptemberSnapshotMustNeverAppearAsCurrentUsageAfterRestart() throws {
        let suite = "ti-stale-usage-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let old = Date().addingTimeInterval(-18 * 86_400)
        let cached = UsageLimitsSnapshot(windows: [
            UsageLimitsWindow(key: "five_hour", label: "5h", usedPercent: 1, resetsAt: old.addingTimeInterval(5 * 3600)),
            UsageLimitsWindow(key: "seven_day", label: "7d", usedPercent: 49, resetsAt: old.addingTimeInterval(7 * 86_400))
        ], fetchedAt: old)
        defaults.set(try JSONEncoder().encode(cached), forKey: "claudeUsageLimitsSnapshot")

        let service = UsageLimitsService(defaults: defaults)
        XCTAssertNil(service.snapshot, "Old saved limits are not current authenticated account data")
    }

    func testExpiredResetMustNotClaimThatAResetIsStillComingSoon() {
        let expired = Date().addingTimeInterval(-86_400)
        XCTAssertNotEqual(PanelHeaderView.countdown(to: expired), "soon")
    }

    func testRelativeResetIsAnchoredToTheFetchRatherThanDecodeWallClock() throws {
        let fetched = Date(timeIntervalSince1970: 1_800_000_000)
        let snapshot = try XCTUnwrap(ClaudeUsageDecoder.snapshot(
            fromUsageJSON: ["five_hour": ["utilization": 23.0, "resets_in_seconds": 60.0]],
            fetchedAt: fetched
        ))
        XCTAssertEqual(snapshot.fiveHourResetsAt, fetched.addingTimeInterval(60))
    }

    func testAnOldOptionalModelWindowDoesNotHideFreshSessionAndWeeklyLimits() {
        let now = Date()
        let snapshot = UsageLimitsSnapshot(windows: [
            UsageLimitsWindow(key: "five_hour", label: "5h", usedPercent: 23, resetsAt: now.addingTimeInterval(3600)),
            UsageLimitsWindow(key: "seven_day", label: "7d", usedPercent: 12, resetsAt: now.addingTimeInterval(86_400)),
            UsageLimitsWindow(key: "seven_day_opus", label: "7d Opus", usedPercent: 4, resetsAt: now.addingTimeInterval(-3600))
        ], fetchedAt: now)
        XCTAssertTrue(snapshot.isCurrent(at: now), "Fresh primary limits must survive an expired optional window")
    }
}
