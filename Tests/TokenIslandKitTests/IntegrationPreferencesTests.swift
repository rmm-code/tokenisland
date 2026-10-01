import XCTest
@testable import TokenIslandKit

@MainActor
final class IntegrationPreferencesTests: XCTestCase {
    func testRemovedIntegrationStaysRemovedAfterRestartAndAutoConfigure() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("ti-optout-\(UUID().uuidString)")
        let suite = "ti-optout-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer {
            try? FileManager.default.removeItem(at: home)
            defaults.removePersistentDomain(forName: suite)
        }
        let cli = try XCTUnwrap(HookFamilyCLI.roster.first { $0.source == "qwen" })
        let adapter = HookFamilyAdapter(cli: cli, homeDirectory: home)
        let registry = AdapterRegistry(adapters: [adapter], defaults: defaults)
        registry.install(adapterID: adapter.id)
        XCTAssertEqual(adapter.status(hookPort: 47791), .active)
        registry.uninstall(adapterID: adapter.id)
        XCTAssertEqual(adapter.status(hookPort: 47791), .needsSetup)

        let restarted = AdapterRegistry(adapters: [adapter], defaults: defaults)
        restarted.autoConfigure()
        XCTAssertEqual(adapter.status(hookPort: 47791), .needsSetup, "An explicit opt-out must survive automatic repair")
        XCTAssertFalse(restarted.isEnabled(adapterID: adapter.id))
        restarted.setEnabled(true, adapterID: adapter.id)
        XCTAssertEqual(adapter.status(hookPort: 47791), .active)
        XCTAssertTrue(AdapterRegistry(adapters: [adapter], defaults: defaults).isEnabled(adapterID: adapter.id))
    }

    func testFailedRemovalKeepsEnabledPreferenceAndReportsTheError() throws {
        let suite = "ti-optout-error-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let registry = AdapterRegistry(adapters: [FailingRemovalAdapter()], defaults: defaults)
        registry.refreshStatuses()
        registry.setEnabled(false, adapterID: "fixture")
        XCTAssertTrue(registry.isEnabled(adapterID: "fixture"))
        XCTAssertEqual(registry.entries.first?.status, .active)
        XCTAssertNotNil(registry.lastError)
    }

    private struct FailingRemovalAdapter: CLIAdapter {
        let id = "fixture"
        let displayName = "Fixture"
        let agentKind = AgentKind.claude
        func detect() -> Bool { true }
        func status(hookPort: UInt16) -> AdapterStatus { .active }
        func installHooks(hookPort: UInt16) throws {}
        func uninstallHooks() throws { throw CocoaError(.fileWriteNoPermission) }
    }

    func testGeminiHookSourceIsSelectedOnlyAfterValidInstallation() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("ti-gemini-source-\(UUID().uuidString)")
        let suite = "ti-gemini-source-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer {
            try? FileManager.default.removeItem(at: home)
            defaults.removePersistentDomain(forName: suite)
        }
        let cli = try XCTUnwrap(HookFamilyCLI.roster.first { $0.source == "gemini" })
        let adapter = HookFamilyAdapter(cli: cli, homeDirectory: home)
        let registry = AdapterRegistry(adapters: [adapter], defaults: defaults)
        registry.refreshStatuses()
        XCTAssertFalse(registry.hasActiveHooks(for: .gemini))
        registry.install(adapterID: adapter.id)
        XCTAssertTrue(registry.hasActiveHooks(for: .gemini))
        registry.uninstall(adapterID: adapter.id)
        XCTAssertFalse(registry.hasActiveHooks(for: .gemini))
    }
}
