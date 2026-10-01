import XCTest
@testable import TokenIslandKit

/// External CLI contracts, rather than assertions that mirror our serializer.
final class UserFacingIntegrationRegressionTests: XCTestCase {
    func testClaudePermissionRequestUsesDecisionBehavior() throws {
        for decision in [ApprovalDecision.allow, .deny] {
            let reply = try XCTUnwrap(HookResponses.permission(decision, reason: "From notch"))
            let json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(reply.utf8)) as? [String: Any])
            let output = try XCTUnwrap(json["hookSpecificOutput"] as? [String: Any])
            XCTAssertEqual(output["hookEventName"] as? String, "PermissionRequest")
            let verdict = output["decision"] as? [String: Any]
            XCTAssertEqual(verdict?["behavior"] as? String, decision.rawValue)
            XCTAssertNil(output["permissionDecision"], "This field belongs to PreToolUse")
            if decision == .deny { XCTAssertEqual(verdict?["message"] as? String, "From notch") }
        }
    }

    func testCursorInstallationUsesFlatCommandsAndCursorEventNames() throws {
        try withHome { home in
            let cli = try XCTUnwrap(HookFamilyCLI.roster.first { $0.source == "cursor" })
            let adapter = HookFamilyAdapter(cli: cli, homeDirectory: home)
            try adapter.installHooks(hookPort: 47791)
            let json = try read(adapter.settingsURL)
            XCTAssertEqual(json["version"] as? Int, 1)
            let hooks = try XCTUnwrap(json["hooks"] as? [String: Any])
            for event in ["sessionStart", "beforeSubmitPrompt", "beforeShellExecution", "postToolUse", "stop"] {
                let entries = hooks[event] as? [[String: Any]]
                XCTAssertTrue(entries?.first?["command"] is String, "Missing flat command for \(event)")
                XCTAssertNil(entries?.first?["hooks"])
            }
            XCTAssertNil(hooks["PermissionRequest"])
            XCTAssertNil(hooks["PreToolUse"])
        }
    }

    func testGeminiInstallationUsesGeminiEventsAndMilliseconds() throws {
        try withHome { home in
            let cli = try XCTUnwrap(HookFamilyCLI.roster.first { $0.source == "gemini" })
            let adapter = HookFamilyAdapter(cli: cli, homeDirectory: home)
            try adapter.installHooks(hookPort: 47791)
            let hooks = try XCTUnwrap(try read(adapter.settingsURL)["hooks"] as? [String: Any])
            for event in ["BeforeAgent", "AfterAgent", "BeforeTool", "AfterTool", "PreCompress"] {
                XCTAssertNotNil(hooks[event], "Missing Gemini event \(event)")
            }
            let beforeTool = (hooks["BeforeTool"] as? [[String: Any]])?.first
            XCTAssertEqual(beforeTool?["matcher"] as? String, ".*")
            let command = (beforeTool?["hooks"] as? [[String: Any]])?.first
            XCTAssertEqual(command?["timeout"] as? Int, 8_000, "Monitoring hook timeout is milliseconds")
            XCTAssertNil(hooks["PermissionRequest"])
            XCTAssertNil(hooks["PreToolUse"])
        }
    }

    func testMalformedClaudeSettingsAreNeverReplaced() throws {
        try withHome { home in
            let adapter = ClaudeCodeAdapter(homeDirectory: home)
            try assertMalformedSettingsPreserved(adapter, at: adapter.settingsURL)
        }
    }

    func testMalformedFamilySettingsAreNeverReplaced() throws {
        try withHome { home in
            let cli = try XCTUnwrap(HookFamilyCLI.roster.first { $0.source == "qwen" })
            let adapter = HookFamilyAdapter(cli: cli, homeDirectory: home)
            try assertMalformedSettingsPreserved(adapter, at: adapter.settingsURL)
        }
    }

    func testMixedHookGroupPreservesForeignCommandOnRepairAndRemoval() throws {
        let foreign: [String: Any] = ["type": "command", "command": "echo foreign"]
        let owned: [String: Any] = ["type": "command", "command": "curl old-port #tokenisland-hook"]
        let original: [String: Any] = [
            "hooks": ["PermissionRequest": [["matcher": "Bash", "hooks": [foreign, owned]]]],
            "unrelated": NSNull()
        ]
        let repaired = HookConfigBuilder.merged(existing: original, source: "claude", port: 47791)
        for result in [repaired, HookConfigBuilder.stripped(existing: original)] {
            let hooks = result["hooks"] as? [String: Any]
            let groups = hooks?["PermissionRequest"] as? [[String: Any]] ?? []
            let preserved = groups.first { ($0["matcher"] as? String) == "Bash" }
            let commands = preserved?["hooks"] as? [[String: Any]]
            XCTAssertEqual(commands?.count, 1)
            XCTAssertEqual(commands?.first?["command"] as? String, "echo foreign")
            XCTAssertTrue(result["unrelated"] is NSNull)
        }
    }

    @MainActor
    func testNativeApprovalsOverrideRememberedAlwaysAllow() async {
        let center = ApprovalCenter()
        let event = SessionEvent(
            context: SessionEventContext(sessionID: "native-test", agent: .claude),
            kind: .permissionRequest(toolName: "Bash", detail: nil, toolUseID: "native-1", preview: nil)
        )
        let id = center.register(event: event)
        center.alwaysAllow(id: id)
        _ = await center.wait(id: id)
        XCTAssertTrue(center.shouldAutoAllow(event: event))
        center.useNativeApprovals = true
        XCTAssertFalse(center.shouldAutoAllow(event: event))
    }

    private func assertMalformedSettingsPreserved(_ adapter: any CLIAdapter, at url: URL) throws {
        let original = Data(#"{"model":"custom",broken"#.utf8)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try original.write(to: url)
        XCTAssertThrowsError(try adapter.installHooks(hookPort: 47791))
        XCTAssertEqual(try Data(contentsOf: url), original)
    }

    private func read(_ url: URL) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    }

    private func withHome(_ body: (URL) throws -> Void) throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("ti-regression-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: home) }
        try body(home)
    }
}
