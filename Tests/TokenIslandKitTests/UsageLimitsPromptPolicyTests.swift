import Foundation
@testable import TokenIslandKit
import XCTest

final class UsageLimitsPromptPolicyTests: XCTestCase {
    /// The body the real endpoint returns, verbatim in shape: microsecond
    /// precision on `resets_at`, `utilization` already on a 0–100 scale, and a
    /// null per-model window.
    private static let realUsageBody = """
    {
        "five_hour":        { "utilization": 33.0, "resets_at": "2026-04-11T07:00:00.528743+00:00" },
        "seven_day":        { "utilization": 13.0, "resets_at": "2026-04-17T00:59:59.951713+00:00" },
        "seven_day_opus":   null,
        "seven_day_sonnet": { "utilization": 1.0,  "resets_at": "2026-04-16T03:00:00.951719+00:00" },
        "extra_usage":      { "is_enabled": false, "monthly_limit": null }
    }
    """

    private func decode(_ json: String) throws -> UsageLimitsSnapshot? {
        let object = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any]
        )
        return UsageLimitsService.snapshot(fromUsageJSON: object, fetchedAt: Date(timeIntervalSince1970: 0))
    }

    /// The countdown never rendered because microsecond timestamps parsed to
    /// nil — percentages arrived, reset dates did not.
    func testRealResponseYieldsBothResetDates() throws {
        let snapshot = try XCTUnwrap(try decode(Self.realUsageBody))
        XCTAssertEqual(snapshot.fiveHourUsedPercent, 33)
        XCTAssertEqual(snapshot.sevenDayUsedPercent, 13)

        let fiveHour = try XCTUnwrap(snapshot.fiveHourResetsAt)
        XCTAssertEqual(fiveHour.timeIntervalSince1970, 1775890800.528, accuracy: 1)
        let sevenDay = try XCTUnwrap(snapshot.sevenDayResetsAt)
        XCTAssertEqual(sevenDay.timeIntervalSince1970, 1776387599.951, accuracy: 1)
    }

    /// A 1% window used to be rescaled to a red 100% pill.
    func testLowUtilizationIsNotRescaled() throws {
        let snapshot = try XCTUnwrap(try decode("""
        { "five_hour": { "utilization": 1.0 }, "seven_day": { "utilization": 0.0 } }
        """))
        XCTAssertEqual(snapshot.fiveHourUsedPercent, 1)
        XCTAssertEqual(snapshot.sevenDayUsedPercent, 0)
    }

    /// Plans carry per-model weekly caps (Fable, Opus) beside the session and
    /// weekly windows, and they change with the plan — every window the
    /// endpoint reports has to reach the pill, not just a hardcoded pair.
    func testEveryReportedWindowIsShownIncludingPerModelCaps() throws {
        let snapshot = try XCTUnwrap(try decode("""
        {
          "five_hour": { "utilization": 33.0, "resets_at": "2026-04-11T07:00:00Z" },
          "seven_day": { "utilization": 55.0 },
          "seven_day_fable": { "utilization": 12.0 },
          "seven_day_opus": { "utilization": 4.0 },
          "account_uuid": "not-a-window"
        }
        """))

        XCTAssertEqual(
            snapshot.windows.map(\.label),
            ["5h", "7d", "7d Fable"],
            "session, then the weekly cap, then per-model caps — and no Opus, which Claude does not meter"
        )
        XCTAssertEqual(snapshot.headerText, "5h 33% · 7d 55% · 7d Fable 12%")
        XCTAssertEqual(snapshot.windows.first?.resetsAt, UsageLimitsService.parseTimestamp("2026-04-11T07:00:00Z"))
        XCTAssertEqual(snapshot.fiveHourUsedPercent, 33, "the named accessors still resolve")
        XCTAssertEqual(snapshot.sevenDayUsedPercent, 55)
    }

    func testUnknownWindowsGetAReadableLabelInsteadOfBeingDropped() throws {
        let snapshot = try XCTUnwrap(try decode("""
        { "five_hour": { "utilization": 1.0 }, "thirty_day_mythos": { "utilization": 9.0 } }
        """))
        XCTAssertEqual(snapshot.windows.map(\.label), ["5h", "30d Mythos"])
    }

    func testCamelCaseWindowKeysAreTreatedAsTheSameWindow() {
        XCTAssertEqual(UsageLimitsService.normalizedKey("fiveHour"), "five_hour")
        XCTAssertEqual(UsageLimitsService.windowLabel(forKey: "sevenDayFable"), "7d Fable")
    }

    func testTimestampParsingAcceptsTheShapesTheEndpointCanSend() throws {
        // Microseconds + offset (what Anthropic actually sends).
        XCTAssertNotNil(UsageLimitsService.parseTimestamp("2026-04-11T07:00:00.528743+00:00"))
        // Milliseconds, and no fractional part at all.
        XCTAssertNotNil(UsageLimitsService.parseTimestamp("2026-04-11T07:00:00.528Z"))
        XCTAssertNotNil(UsageLimitsService.parseTimestamp("2026-04-11T07:00:00Z"))
        XCTAssertNil(UsageLimitsService.parseTimestamp("not a date"))
        XCTAssertNil(UsageLimitsService.parseTimestamp(""))
    }

    /// Windows can be absent or JSON null; neither may crash or invent a date.
    func testMissingAndNullWindowsDegradeQuietly() throws {
        XCTAssertNil(try decode("""
        { "seven_day_opus": null }
        """))
        let partial = try XCTUnwrap(try decode("""
        { "five_hour": { "utilization": 12.0 }, "seven_day": null }
        """))
        XCTAssertEqual(partial.fiveHourUsedPercent, 12)
        XCTAssertNil(partial.fiveHourResetsAt)
        XCTAssertNil(partial.sevenDayUsedPercent)
    }

    /// Relative form, in case a future response reports seconds remaining.
    func testResetsInSecondsIsAccepted() throws {
        let snapshot = try XCTUnwrap(try decode("""
        { "five_hour": { "utilization": 5.0, "resets_in_seconds": 600 } }
        """))
        let resets = try XCTUnwrap(snapshot.fiveHourResetsAt)
        XCTAssertEqual(resets.timeIntervalSinceNow, 600, accuracy: 5)
    }

    @MainActor
    func testUsageServiceRestoresLastSuccessfulSnapshotImmediately() async throws {
        let suiteName = "UsageLimitsPromptPolicyTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let expected = UsageLimitsSnapshot(
            windows: [
                UsageLimitsWindow(
                    key: "five_hour",
                    label: "5h",
                    usedPercent: 24,
                    resetsAt: Date(timeIntervalSince1970: 100)
                ),
                UsageLimitsWindow(
                    key: "seven_day",
                    label: "7d",
                    usedPercent: 41,
                    resetsAt: Date(timeIntervalSince1970: 200)
                )
            ],
            fetchedAt: Date(timeIntervalSince1970: 50)
        )
        defaults.set(
            try JSONEncoder().encode(expected),
            forKey: "claudeUsageLimitsSnapshot"
        )

        let service = UsageLimitsService(defaults: defaults)

        XCTAssertEqual(service.snapshot, expected)
    }

    func testExpandedPanelAutomaticallyUsesSafeRefreshWithoutTapRequiredState() throws {
        let source = try sourceFile(
            "Sources/TokenIslandKit/Features/NotchUI/ExpandedPanelView.swift"
        )
        let expandedPanel = try sourceSection(
            source,
            beginningWith: "struct ExpandedPanelView"
        )
        let automaticLifecycle = lifecycleBlocks(in: expandedPanel)

        XCTAssertTrue(
            automaticLifecycle.contains("usageLimits.refreshIfStale()"),
            "Presenting the expanded panel should load Claude usage automatically through the noninteractive refresh path"
        )
        XCTAssertFalse(
            automaticLifecycle.contains("usageLimits.refreshFromUserAction()"),
            "Panel presentation must never use the user-initiated Keychain fallback"
        )
        XCTAssertFalse(
            source.contains("\"Tap for usage\""),
            "Passive panel presentation must not require a second tap before showing Claude usage state"
        )
    }

    func testUsageLimitsServiceLivesInAppEnvironmentAndIsInjectedIntoExpandedPanel() throws {
        let environmentSource = try sourceFile("Sources/TokenIslandKit/App/AppEnvironment.swift")
        let panelSource = try sourceFile(
            "Sources/TokenIslandKit/Features/NotchUI/ExpandedPanelView.swift"
        )
        let notchSource = try sourceFile(
            "Sources/TokenIslandKit/Features/NotchUI/TokenIslandNotchView.swift"
        )
        let expandedPanel = try sourceSection(
            panelSource,
            beginningWith: "struct ExpandedPanelView"
        )
        let expandedPanelCall = try sourceSection(
            notchSource,
            beginningWith: "ExpandedPanelView(",
            endingBefore: "case .reveal"
        )

        XCTAssertNotNil(
            environmentSource.range(
                of: #"let\s+\w*[Uu]sage\w*\s*:\s*UsageLimitsService"#,
                options: .regularExpression
            ),
            "AppEnvironment should own the single UsageLimitsService instance"
        )
        XCTAssertTrue(
            environmentSource.contains("UsageLimitsService()"),
            "AppEnvironment.production() should construct the app-lifetime usage service"
        )
        XCTAssertFalse(
            expandedPanel.contains("UsageLimitsService()"),
            "The transient expanded panel must not create and discard its own usage service"
        )
        XCTAssertTrue(
            expandedPanelCall.contains("usageLimits:"),
            "TokenIslandNotchView should inject the app-lifetime usage service into ExpandedPanelView"
        )
    }

    func testAutomaticCredentialLookupUsesOnlyNoninteractiveKeychainFallback() throws {
        let source = try sourceFile(
            "Sources/TokenIslandKit/Core/UsageLimits/UsageLimitsService.swift"
        )
        var keychainWasRead = false
        let token = UsageLimitsService.resolveAccessToken(
            credentialsFileURL: URL(fileURLWithPath: "/missing/claude-credentials.json"),
            allowsKeychainFallback: true,
            keychainReader: {
                keychainWasRead = true
                return Self.credentialsData
            }
        )

        XCTAssertEqual(token, "test-token")
        XCTAssertTrue(keychainWasRead)
        XCTAssertTrue(
            source.contains("interactionNotAllowed = true") &&
                source.contains("kSecUseAuthenticationContext as String"),
            "Automatic Keychain fallback must fail silently instead of displaying a password prompt"
        )
        XCTAssertTrue(
            source.contains("allowsInteraction: false"),
            "The automatic refresh path must explicitly select noninteractive Keychain access"
        )
    }

    func testUserInitiatedCredentialLookupMayReadKeychainFallback() {
        var keychainWasRead = false
        let token = UsageLimitsService.resolveAccessToken(
            credentialsFileURL: URL(fileURLWithPath: "/missing/claude-credentials.json"),
            allowsKeychainFallback: true,
            keychainReader: {
                keychainWasRead = true
                return Self.credentialsData
            }
        )

        XCTAssertEqual(token, "test-token")
        XCTAssertTrue(keychainWasRead)
    }

    private static let credentialsData = Data(
        #"{"claudeAiOauth":{"accessToken":"test-token"}}"#.utf8
    )

    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func sourceFile(_ relativePath: String) throws -> String {
        try String(
            contentsOf: repositoryRoot.appendingPathComponent(relativePath),
            encoding: .utf8
        )
    }

    private func sourceSection(
        _ source: String,
        beginningWith startMarker: String,
        endingBefore endMarker: String? = nil
    ) throws -> String {
        guard let start = source.range(of: startMarker) else {
            throw TestSourceError.missingMarker(startMarker)
        }
        let end = endMarker.flatMap {
            source.range(of: $0, range: start.upperBound..<source.endIndex)?.lowerBound
        } ?? source.endIndex
        return String(source[start.lowerBound..<end])
    }

    private func lifecycleBlocks(in source: String) -> String {
        [".task", ".onAppear"]
            .flatMap { blocks(after: $0, in: source) }
            .joined(separator: "\n")
    }

    private func blocks(after marker: String, in source: String) -> [String] {
        var blocks: [String] = []
        var searchStart = source.startIndex

        while let markerRange = source.range(
            of: marker,
            range: searchStart..<source.endIndex
        ) {
            guard let openBrace = source[markerRange.upperBound...].firstIndex(of: "{") else {
                break
            }
            var depth = 0
            var cursor = openBrace
            while cursor < source.endIndex {
                switch source[cursor] {
                case "{": depth += 1
                case "}":
                    depth -= 1
                    if depth == 0 {
                        blocks.append(String(source[openBrace...cursor]))
                        searchStart = source.index(after: cursor)
                        break
                    }
                default: break
                }
                if depth == 0 { break }
                cursor = source.index(after: cursor)
            }
            if depth != 0 { break }
        }
        return blocks
    }

    private enum TestSourceError: Error {
        case missingMarker(String)
    }
}
