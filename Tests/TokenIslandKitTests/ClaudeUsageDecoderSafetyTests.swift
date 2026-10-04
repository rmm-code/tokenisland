import XCTest
@testable import TokenIslandKit

final class ClaudeUsageDecoderSafetyTests: XCTestCase {
    func testInvalidNumbersDoNotBecomeFalseUsageOrCrashTheHeader() throws {
        for value: Any in [true, -1.0, 101.0, Double.nan, Double.infinity, "23"] {
            XCTAssertNil(ClaudeUsageDecoder.snapshot(
                fromUsageJSON: ["five_hour": ["utilization": value]], fetchedAt: Date()
            ))
        }
    }

    func testCanonicalAndCamelCaseAliasesProduceOneStableWindow() throws {
        let snapshot = try XCTUnwrap(ClaudeUsageDecoder.snapshot(fromUsageJSON: [
            "fiveHour": ["utilization": 99], "five_hour": ["utilization": 23]
        ], fetchedAt: Date()))
        XCTAssertEqual(snapshot.windows.count, 1)
        XCTAssertEqual(snapshot.windows.first?.key, "five_hour")
        XCTAssertEqual(snapshot.fiveHourUsedPercent, 23)
    }

    func testNullResetAndZeroUsageRemainValidAndAreNeverGuessed() throws {
        let date = Date()
        let snapshot = try XCTUnwrap(ClaudeUsageDecoder.snapshot(fromUsageJSON: [
            "five_hour": ["utilization": 0, "resets_at": NSNull()]
        ], fetchedAt: date))
        XCTAssertEqual(snapshot.fiveHourUsedPercent, 0)
        XCTAssertNil(snapshot.fiveHourResetsAt)
        XCTAssertTrue(snapshot.isCurrent(at: date))
    }

    func testIntegerRelativeResetsAndMalformedResetTypesAreHandledSafely() throws {
        let date = Date()
        let valid = try XCTUnwrap(ClaudeUsageDecoder.snapshot(fromUsageJSON: [
            "five_hour": ["utilization": 23, "resets_in_seconds": 60]
        ], fetchedAt: date))
        XCTAssertEqual(valid.fiveHourResetsAt, date.addingTimeInterval(60))
        for value: Any in [true, Double.infinity, "invalid"] {
            let invalid = try XCTUnwrap(ClaudeUsageDecoder.snapshot(fromUsageJSON: [
                "five_hour": ["utilization": 23, "resets_at": value]
            ], fetchedAt: date))
            XCTAssertNil(invalid.fiveHourResetsAt)
        }
    }

    func testInactiveZeroWindowKeepsItsFreshValueWithoutAnOverdueCountdown() {
        let date = Date()
        let snapshot = UsageLimitsSnapshot(windows: [
            UsageLimitsWindow(key: "seven_day_fable", label: "7d Fable", usedPercent: 0, resetsAt: date.addingTimeInterval(-10))
        ], fetchedAt: date)
        let current = snapshot.currentWindows(at: date)
        XCTAssertEqual(current.first?.usedPercent, 0)
        XCTAssertNil(current.first?.resetsAt)
    }

    func testUnknownInternalNamesHaveHonestLabelsAndDistinctUIIdentities() {
        XCTAssertEqual(ClaudeUsageDecoder.windowLabel(forKey: "iguana_necktie"), "Additional limit")
        let first = UsageWindow(label: "Additional limit", usedPercent: 0, resetsAt: nil, key: "first")
        let second = UsageWindow(label: "Additional limit", usedPercent: 0, resetsAt: nil, key: "second")
        XCTAssertNotEqual(first.id, second.id)
    }
}
