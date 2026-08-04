import XCTest
@testable import TokenIslandKit

/// Cursor and Gemini CLI speak their own hook dialects. Payload shapes below
/// are taken from each CLI's published hooks reference — field names verbatim,
/// because a single wrong key means the session silently never appears.
final class DialectRouterTests: XCTestCase {
    private func cursor(_ json: [String: Any]) throws -> SessionEvent {
        try CursorHookRouter.decode(
            body: try JSONSerialization.data(withJSONObject: json),
            headers: [:]
        )
    }

    private func gemini(_ json: [String: Any]) throws -> SessionEvent {
        try GeminiHookRouter.decode(
            body: try JSONSerialization.data(withJSONObject: json),
            headers: [:]
        )
    }

    // MARK: - Cursor

    func testCursorIdentifiesSessionAndWorkspace() throws {
        let event = try cursor([
            "hook_event_name": "sessionStart",
            "conversation_id": "conv-1",
            "session_id": "sess-1",
            "workspace_roots": ["/Users/dev/app", "/Users/dev/other"],
            "composer_mode": "agent"
        ])
        XCTAssertEqual(event.context.sessionID, "sess-1")
        XCTAssertEqual(event.context.agent, .cursor)
        XCTAssertEqual(event.context.cwd, "/Users/dev/app", "workspace_roots is an array")
        XCTAssertEqual(event.kind, .sessionStart(source: "agent"))
    }

    func testCursorFallsBackToConversationID() throws {
        let event = try cursor([
            "hook_event_name": "beforeSubmitPrompt",
            "conversation_id": "conv-9",
            "prompt": "fix the auth bug"
        ])
        XCTAssertEqual(event.context.sessionID, "conv-9")
        XCTAssertEqual(event.kind, .userPrompt(prompt: "fix the auth bug"))
    }

    /// Cursor gates shell commands on their own event, not `preToolUse`.
    func testCursorShellExecutionBecomesAnApprovalWithPreview() throws {
        let event = try cursor([
            "hook_event_name": "beforeShellExecution",
            "conversation_id": "conv-1",
            "command": "npm run build",
            "cwd": "/Users/dev/app"
        ])
        guard case .permissionRequest(let tool, let detail, _, let preview) = event.kind else {
            return XCTFail("expected an approval, got \(event.kind)")
        }
        XCTAssertEqual(tool, "Shell")
        XCTAssertEqual(detail, "npm run build")
        XCTAssertEqual(preview, ToolCallPreview(kind: .bashCommand("npm run build")))
    }

    func testCursorSubagentStartBecomesARow() throws {
        let event = try cursor([
            "hook_event_name": "subagentStart",
            "conversation_id": "conv-1",
            "subagent_id": "sub-1",
            "tool_call_id": "call-1",
            "subagent_type": "explore",
            "task": "Search the API endpoints"
        ])
        guard case .preTool(let tool, _, let toolUseID, let label) = event.kind else {
            return XCTFail("expected preTool, got \(event.kind)")
        }
        XCTAssertEqual(tool, "Agent")
        XCTAssertEqual(toolUseID, "call-1", "the tool call is what postToolUse will settle")
        XCTAssertEqual(label, "Explore (Search the API endpoints)")
    }

    func testCursorAgentTextFillsTheCompletionWithoutEndingTheTurn() throws {
        let event = try cursor([
            "hook_event_name": "afterAgentResponse",
            "conversation_id": "conv-1",
            "text": "Fixed the crash and added a test."
        ])
        XCTAssertEqual(event.kind, .assistantMessage(text: "Fixed the crash and added a test."))

        var sessions: [String: AgentSession] = [:]
        _ = SessionReducer.reduce(sessions: &sessions, event: event)
        let session = sessions["conv-1"]
        XCTAssertEqual(session?.completionTLDR, "Fixed the crash and added a test.")
        XCTAssertNotEqual(session?.phase, .ready, "the turn is still running")
    }

    func testCursorAnswersApprovalsInItsOwnShape() throws {
        let json = try XCTUnwrap(CursorHookRouter.permissionResponse(.deny, reason: "Denied from the notch"))
        let payload = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any]
        )
        XCTAssertEqual(payload["permission"] as? String, "deny", "Cursor reads `permission`")
        XCTAssertNil(payload["hookSpecificOutput"], "that is Claude Code's shape")
    }

    // MARK: - Gemini

    func testGeminiTurnLifecycle() throws {
        let start = try gemini([
            "hook_event_name": "BeforeAgent",
            "session_id": "g-1",
            "cwd": "/Users/dev/app",
            "prompt": "add retry handling"
        ])
        XCTAssertEqual(start.context.agent, .gemini)
        XCTAssertEqual(start.context.cwd, "/Users/dev/app")
        XCTAssertEqual(start.kind, .userPrompt(prompt: "add retry handling"))

        let end = try gemini([
            "hook_event_name": "AfterAgent",
            "session_id": "g-1",
            "prompt": "add retry handling",
            "prompt_response": "Added exponential backoff."
        ])
        XCTAssertEqual(end.kind, .stop(lastAssistantMessage: "Added exponential backoff."))
    }

    /// `BeforeTool` is Gemini's only gate, so it is the approval channel.
    func testGeminiBeforeToolIsTheApprovalChannel() throws {
        let event = try gemini([
            "hook_event_name": "BeforeTool",
            "session_id": "g-1",
            "tool_name": "run_shell_command",
            "tool_input": ["command": "rm -rf build"]
        ])
        guard case .permissionRequest(let tool, _, _, let preview) = event.kind else {
            return XCTFail("expected an approval, got \(event.kind)")
        }
        XCTAssertEqual(tool, "Bash", "gemini's snake_case tools read like every other agent's")
        XCTAssertEqual(preview, ToolCallPreview(kind: .bashCommand("rm -rf build")))
    }

    func testGeminiToolNamesAreNormalised() {
        XCTAssertEqual(GeminiHookRouter.displayToolName("read_file"), "Read")
        XCTAssertEqual(GeminiHookRouter.displayToolName("write_file"), "Write")
        XCTAssertEqual(GeminiHookRouter.displayToolName("search_file_content"), "Grep")
        XCTAssertEqual(GeminiHookRouter.displayToolName("mcp_github_list_issues"), "McpGithubListIssues")
        XCTAssertEqual(GeminiHookRouter.displayToolName(nil), "Tool")
    }

    func testGeminiAnswersApprovalsInItsOwnShape() throws {
        let json = try XCTUnwrap(GeminiHookRouter.permissionResponse(.allow, reason: "Allowed from the notch"))
        let payload = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any]
        )
        XCTAssertEqual(payload["decision"] as? String, "allow", "Gemini reads `decision`")
        XCTAssertEqual(payload["reason"] as? String, "Allowed from the notch")
    }

    // MARK: - Routing

    func testEachSourceResolvesToItsDialect() {
        XCTAssertEqual(HookFamilyCLI.dialect(forSource: "claude"), .claude)
        XCTAssertEqual(HookFamilyCLI.dialect(forSource: "qwen"), .claude)
        XCTAssertEqual(HookFamilyCLI.dialect(forSource: "cursor"), .cursor)
        XCTAssertEqual(HookFamilyCLI.dialect(forSource: "gemini"), .gemini)
        XCTAssertNil(HookFamilyCLI.dialect(forSource: "nope"))
    }

    /// A payload with no session id must be refused, not turned into a card.
    func testMissingSessionIsRejectedInBothDialects() throws {
        let body = try JSONSerialization.data(withJSONObject: ["hook_event_name": "stop"])
        XCTAssertThrowsError(try CursorHookRouter.decode(body: body, headers: [:]))
        XCTAssertThrowsError(try GeminiHookRouter.decode(body: body, headers: [:]))
    }
}
