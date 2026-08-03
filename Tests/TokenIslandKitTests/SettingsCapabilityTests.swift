import Foundation
import XCTest
@testable import TokenIslandKit

final class SettingsCapabilityTests: XCTestCase {
    @MainActor
    func testIntegrationRosterContainsOnlyMonitoredAgents() {
        let registry = AdapterRegistry()
        XCTAssertEqual(Set(registry.entries.map(\.id)), ["claude-code", "codex", "gemini-cli"])
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
        let about = try sourceFile(
            "Sources/TokenIslandKit/Features/Settings/AboutSettingsPane.swift"
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
        XCTAssertFalse(about.contains("Auto check for updates"))
        XCTAssertFalse(display.contains("Hide in fullscreen"))
        XCTAssertFalse(sections.contains("sshRemote"))
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
