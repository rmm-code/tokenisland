import XCTest
@testable import TokenIslandKit

final class HookConfigurationSafetyTests: XCTestCase {
    func testMalformedHookCollectionsAreNeverRepairedByOverwriting() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("ti-invalid-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: home) }
        let adapter = ClaudeCodeAdapter(homeDirectory: home)
        try FileManager.default.createDirectory(at: adapter.settingsURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        for fixture in [#"{"hooks":"invalid"}"#, #"{"hooks":{"Stop":"invalid"}}"#,
                        #"{"hooks":{"Stop":[{"hooks":"invalid"}]}}"#, #"{"env":"invalid"}"#, "", "[]"] {
            let data = Data(fixture.utf8)
            try data.write(to: adapter.settingsURL)
            XCTAssertThrowsError(try adapter.installHooks(hookPort: 47791))
            XCTAssertThrowsError(try adapter.uninstallHooks())
            XCTAssertEqual(try Data(contentsOf: adapter.settingsURL), data)
            if case .failed = adapter.status(hookPort: 47791) {} else { XCTFail("Invalid configuration must report a failure") }
        }
    }

    func testDialectUpgradeRemovesOnlyLegacyOwnedEntries() throws {
        for source in ["cursor", "gemini"] {
            let ownCommand = "curl http://127.0.0.1:47791/hook/\(source) #tokenisland-hook"
            let original: [String: Any] = ["theme": "dark", "hooks": [
                "PreToolUse": [["matcher": "*", "hooks": [
                    ["type": "command", "command": "echo foreign"],
                    ["type": "command", "command": ownCommand]
                ]]]
            ]]
            let upgraded = HookConfigBuilder.merged(existing: original, source: source, port: 47791)
            XCTAssertEqual(HookConfigBuilder.installState(settings: upgraded, source: source, port: 47791), .active)
            let twice = HookConfigBuilder.merged(existing: upgraded, source: source, port: 47791)
            XCTAssertEqual(try JSONSerialization.data(withJSONObject: upgraded, options: .sortedKeys),
                           try JSONSerialization.data(withJSONObject: twice, options: .sortedKeys))
            let uninstalled = HookConfigBuilder.stripped(existing: upgraded)
            let hooks = try XCTUnwrap(uninstalled["hooks"] as? [String: Any])
            let group = (hooks["PreToolUse"] as? [[String: Any]])?.first
            XCTAssertEqual((group?["hooks"] as? [[String: Any]])?.count, 1)
            XCTAssertEqual(uninstalled["theme"] as? String, "dark")
        }
    }

    func testMixedGroupStillReportsForeignApprovalHook() {
        let settings: [String: Any] = ["hooks": ["PermissionRequest": [["hooks": [
            ["command": "/bin/echo foreign"], ["command": "curl localhost #tokenisland-hook"]
        ]]]]]
        XCTAssertEqual(HookConfigBuilder.foreignApprovalHooks(settings: settings), ["echo"])
    }

    func testOldTransportIsReportedAsNeedingRepairEvenOnSamePort() throws {
        var installed = HookConfigBuilder.merged(existing: [:], source: "claude", port: 47791)
        var hooks = try XCTUnwrap(installed["hooks"] as? [String: Any])
        hooks["Stop"] = [["hooks": [["type": "command", "command": "curl http://127.0.0.1:47791/hook/claude #tokenisland-hook"]]]]
        installed["hooks"] = hooks
        if case .needsRepair = HookConfigBuilder.installState(settings: installed, source: "claude", port: 47791) {} else {
            XCTFail("An old command must be migrated on upgrade")
        }
    }

    func testCursorCommandDropsPartialRepliesAndFailsOpenOnTransportErrors() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("ti-transport-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: home) }
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        let curl = home.appendingPathComponent("curl")
        let command = HookConfigBuilder.command(source: "cursor", port: 47791, curlTimeout: 5)
        for (reply, curlStatus, expectedStatus) in [(#"{"permission":"deny"}"#, 0, 0), ("partial", 28, 3), ("", 0, 3)] {
            try Data("#!/bin/sh\nprintf '%s' '\(reply)'\nexit \(curlStatus)\n".utf8).write(to: curl)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: curl.path)
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/sh")
            process.arguments = ["-c", command]
            var environment = ProcessInfo.processInfo.environment
            environment["PATH"] = home.path + ":/usr/bin:/bin"
            process.environment = environment
            process.standardInput = FileHandle.nullDevice
            let output = Pipe()
            process.standardOutput = output
            try process.run()
            let data = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            XCTAssertEqual(process.terminationStatus, Int32(expectedStatus))
            XCTAssertEqual(String(data: data, encoding: .utf8), expectedStatus == 0 ? reply : "")
        }
    }
}
