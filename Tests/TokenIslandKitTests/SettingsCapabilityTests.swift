import Foundation
import XCTest
@testable import TokenIslandKit

final class SettingsCapabilityTests: XCTestCase {
    /// The roster may only list CLIs we genuinely integrate: Claude Code, the
    /// Claude-family derivatives whose real config shape was verified before
    /// being added, and the two file-watch adapters. Adding a name here has to
    /// be a deliberate act, not a hopeful one.
    @MainActor
    func testIntegrationRosterContainsOnlyMonitoredAgents() {
        let registry = AdapterRegistry()
        XCTAssertEqual(
            Set(registry.entries.map(\.id)),
            [
                // Claude dialect
                "claude-code", "qwen-code", "qoder", "trae", "codebuddy", "droid", "copilot-cli",
                // Their own dialects
                "cursor-agent", "gemini-cli",
                // File-watch
                "codex"
            ]
        )
    }

    /// Every family member needs a distinct route and agent, or two CLIs would
    /// land in the same session bucket.
    func testHookFamilyRouteAndAgentAreUnique() {
        let sources = HookFamilyCLI.roster.map(\.source)
        XCTAssertEqual(Set(sources).count, sources.count, "duplicate hook route")
        XCTAssertFalse(sources.contains("claude"), "claude's route belongs to Claude Code")

        let agents = HookFamilyCLI.roster.map(\.agentKind)
        XCTAssertEqual(Set(agents).count, agents.count, "duplicate agent kind")

        for cli in HookFamilyCLI.roster {
            XCTAssertEqual(
                HookFamilyCLI.agentKind(forSource: cli.source),
                cli.agentKind,
                "\(cli.id) route does not resolve back to its agent"
            )
        }
    }

    func testSettingsDoNotExposeReservedOrPlaceholderCapabilities() throws {
        let notifications = try sourceFile(
            "Sources/TokenIslandKit/Features/Settings/NotificationsSettingsPane.swift"
        )
        let labs = try sourceFile(
            "Sources/TokenIslandKit/Features/Settings/LabsSettingsPane.swift"
        )
        let integrations = try sourceFile(
            "Sources/TokenIslandKit/Features/Settings/IntegrationsSettingsPane.swift"
        )
        let display = try sourceFile(
            "Sources/TokenIslandKit/Features/Settings/DisplaySettingsPane.swift"
        )
        let sections = try sourceFile(
            "Sources/TokenIslandKit/Features/Settings/SettingsSection.swift"
        )

        XCTAssertFalse(notifications.contains("quietWhenScreenSharing"))
        XCTAssertFalse(labs.contains("useAutoModeInsteadOfBypass"))
        XCTAssertFalse(integrations.contains("IDE Extensions"))
        XCTAssertFalse(integrations.contains("monitoring soon"))
        XCTAssertFalse(display.contains("Hide in fullscreen"))
        XCTAssertFalse(sections.contains("sshRemote"))
    }

    /// Update checking used to be a dead toggle, which is why it was removed.
    /// It may only be visible while something actually consumes it.
    func testUpdateToggleHasARuntimeConsumer() throws {
        let about = try sourceFile("Sources/TokenIslandKit/Features/Settings/AboutSettingsPane.swift")
        let delegate = try sourceFile("Sources/TokenIslandKit/App/AppDelegate.swift")

        XCTAssertTrue(about.contains("Auto check for updates"), "the control is back")
        XCTAssertTrue(
            delegate.contains("autoCheckForUpdates"),
            "…and the setting gates a real check"
        )
        XCTAssertTrue(
            delegate.contains("checkIfDue"),
            "…which runs on launch and on a timer"
        )
    }

    func testLegacyListenersAndThresholdNotificationsAreOptIn() {
        XCTAssertFalse(AppSettings.defaults.enableOTLPReceiver)
        XCTAssertFalse(AppSettings.defaults.enableOpenAIProxy)
        XCTAssertFalse(AppSettings.defaults.enableThresholdNotifications)
    }

    func testOlderSettingsFilesGainGeminiMonitoringDefault() throws {
        let encoded = try JSONEncoder().encode(AppSettings.defaults)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object.removeValue(forKey: "enableGeminiMonitoring")
        let legacyData = try JSONSerialization.data(withJSONObject: object)

        let decoded = try JSONDecoder().decode(AppSettings.self, from: legacyData)
        XCTAssertTrue(decoded.enableGeminiMonitoring)
    }

    func testRuntimeIntegrationsAreGatedByCompletedOnboarding() throws {
        let appState = try sourceFile("Sources/TokenIslandKit/App/AppState.swift")
        XCTAssertTrue(appState.contains("if settings.hasCompletedOnboarding"))
        XCTAssertTrue(appState.contains("await activateRuntimeIntegrations()"))
        XCTAssertTrue(appState.contains("telemetryConfigurationChanged(from: previous, to: next)"))
    }

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
}
