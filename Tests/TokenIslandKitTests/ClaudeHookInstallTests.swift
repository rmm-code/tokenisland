import XCTest
@testable import TokenIslandKit

final class ClaudeHookInstallTests: XCTestCase {
    func testMergedSettingsCoversAllEventsAndIsIdempotent() {
        let merged = ClaudeHookCommand.mergedSettings(existing: [:], port: 47791)
        let hooks = merged["hooks"] as? [String: Any]
        XCTAssertNotNil(hooks)
        for event in ClaudeHookCommand.subscribedEvents {
            let groups = hooks?[event] as? [[String: Any]]
            XCTAssertEqual(groups?.count, 1, "expected exactly one group for \(event)")
        }

        // Re-merging must not duplicate entries.
        let remerged = ClaudeHookCommand.mergedSettings(existing: merged, port: 47791)
        let rehooks = remerged["hooks"] as? [String: Any]
        for event in ClaudeHookCommand.subscribedEvents {
            let groups = rehooks?[event] as? [[String: Any]]
            XCTAssertEqual(groups?.count, 1, "re-merge duplicated group for \(event)")
        }
    }

    func testMergePreservesUserEntriesAndPortChangeReplacesOurs() {
        let userHook: [String: Any] = [
            "matcher": "Bash",
            "hooks": [["type": "command", "command": "echo user-hook"]]
        ]
        let existing: [String: Any] = [
            "model": "opus",
            "hooks": ["PreToolUse": [userHook]]
        ]

        let merged = ClaudeHookCommand.mergedSettings(existing: existing, port: 47791)
        let portChanged = ClaudeHookCommand.mergedSettings(existing: merged, port: 50000)

        XCTAssertEqual(portChanged["model"] as? String, "opus", "unrelated settings must survive")
        let groups = (portChanged["hooks"] as? [String: Any])?["PreToolUse"] as? [[String: Any]]
        XCTAssertEqual(groups?.count, 2, "user group + exactly one of ours")

        let ourGroups = groups?.filter { ClaudeHookCommand.ownsGroup($0) } ?? []
        XCTAssertEqual(ourGroups.count, 1)
        let command = ((ourGroups.first?["hooks"] as? [[String: Any]])?.first?["command"] as? String) ?? ""
        XCTAssertTrue(command.contains("127.0.0.1:50000"), "port change must rewrite the command")

        let userGroups = groups?.filter { !ClaudeHookCommand.ownsGroup($0) } ?? []
        XCTAssertEqual(userGroups.count, 1)
        XCTAssertEqual(userGroups.first?["matcher"] as? String, "Bash")
    }

    func testStrippedSettingsRemovesOnlyOurEntries() {
        let userHook: [String: Any] = [
            "hooks": [["type": "command", "command": "say done"]]
        ]
        var existing = ClaudeHookCommand.mergedSettings(existing: ["hooks": ["Stop": [userHook]]], port: 47791)
        existing["theme"] = "dark"

        let stripped = ClaudeHookCommand.strippedSettings(existing: existing)
        XCTAssertEqual(stripped["theme"] as? String, "dark")
        let hooks = stripped["hooks"] as? [String: Any]
        XCTAssertEqual((hooks?["Stop"] as? [[String: Any]])?.count, 1, "user Stop hook must remain")
        for event in ClaudeHookCommand.subscribedEvents where event != "Stop" {
            XCTAssertNil(hooks?[event], "our-only event \(event) should be dropped entirely")
        }
    }

    func testInstallStateDetection() {
        XCTAssertEqual(
            ClaudeHookCommand.installState(settings: [:], port: 47791),
            AdapterStatus.needsSetup
        )

        let merged = ClaudeHookCommand.mergedSettings(existing: [:], port: 47791)
        XCTAssertEqual(
            ClaudeHookCommand.installState(settings: merged, port: 47791),
            AdapterStatus.active
        )

        // Same install inspected against a different port → repair.
        if case .needsRepair = ClaudeHookCommand.installState(settings: merged, port: 50000) {
        } else {
            XCTFail("expected needsRepair for port mismatch")
        }
    }

    func testAdapterInstallsIntoTempHomeWithBackup() throws {
        let tempHome = FileManager.default.temporaryDirectory
            .appendingPathComponent("ti-test-home-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempHome) }

        let claudeDir = tempHome.appendingPathComponent(".claude", isDirectory: true)
        try FileManager.default.createDirectory(at: claudeDir, withIntermediateDirectories: true)
        let settingsURL = claudeDir.appendingPathComponent("settings.json")
        try Data(#"{"model":"opus"}"#.utf8).write(to: settingsURL)

        let adapter = ClaudeCodeAdapter(homeDirectory: tempHome)
        XCTAssertTrue(adapter.detect())
        XCTAssertEqual(adapter.status(hookPort: 47791), .needsSetup)

        try adapter.installHooks(hookPort: 47791)
        XCTAssertEqual(adapter.status(hookPort: 47791), .active)
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: claudeDir.appendingPathComponent("settings.json.tokenisland-backup").path
            ),
            "backup must exist after first install"
        )

        let written = try JSONSerialization.jsonObject(
            with: Data(contentsOf: settingsURL)
        ) as? [String: Any]
        XCTAssertEqual(written?["model"] as? String, "opus")

        try adapter.uninstallHooks()
        XCTAssertEqual(adapter.status(hookPort: 47791), .needsSetup)
        let stripped = try JSONSerialization.jsonObject(
            with: Data(contentsOf: settingsURL)
        ) as? [String: Any]
        XCTAssertEqual(stripped?["model"] as? String, "opus")
        XCTAssertNil(stripped?["hooks"])
    }

    func testSlugify() {
        XCTAssertEqual(TitleMarkerService.slugify("Fix the Auth Bug!"), "fix-the-auth-bug")
        XCTAssertEqual(TitleMarkerService.slugify("   "), "session")
        XCTAssertEqual(
            TitleMarkerService.slugify("a very long title that should be trimmed down hard"),
            "a-very-long-title-that-shoul"
        )
    }
}
