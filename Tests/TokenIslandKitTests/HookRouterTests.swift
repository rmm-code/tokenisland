import XCTest
@testable import TokenIslandKit

final class HookRouterTests: XCTestCase {
    func testDecodesPreToolUsePayload() throws {
        let payload: [String: Any] = [
            "session_id": "s-1",
            "hook_event_name": "PreToolUse",
            "cwd": "/Users/dev/proj",
            "transcript_path": "/tmp/x.jsonl",
            "tool_name": "Edit",
            "tool_use_id": "tu-9",
            "tool_input": ["file_path": "/Users/dev/proj/src/main.swift"]
        ]
        let body = try JSONSerialization.data(withJSONObject: payload)
        let event = try HookRouter.decodeClaudeEvent(
            body: body,
            headers: ["X-TI-Term": "Apple_Terminal", "X-TI-TTY": "/dev/ttys004"]
        )
        XCTAssertEqual(event.context.sessionID, "s-1")
        XCTAssertEqual(event.context.terminalHint?.termProgram, "Apple_Terminal")
        XCTAssertEqual(event.context.terminalHint?.bundleIdentifier, "com.apple.Terminal")
        guard case .preTool(let tool, let detail, let toolUseID, let subagentLabel) = event.kind else {
            return XCTFail("expected preTool, got \(event.kind)")
        }
        XCTAssertEqual(tool, "Edit")
        XCTAssertEqual(detail, "src/main.swift")
        XCTAssertEqual(toolUseID, "tu-9")
        XCTAssertNil(subagentLabel)
    }

    /// The fan-out tool is `Agent` on current Claude Code and `Task` on older
    /// builds. Matching only one of them meant no subagent ever registered.
    func testDecodesSubagentSpawnUnderBothToolNames() throws {
        for toolName in ["Agent", "Task"] {
            let payload: [String: Any] = [
                "session_id": "s-sub",
                "hook_event_name": "PreToolUse",
                "cwd": "/Users/dev/proj",
                "tool_name": toolName,
                "tool_use_id": "tu-sub",
                "tool_input": [
                    "description": "Audit non-notch fallback path",
                    "subagent_type": "general-purpose"
                ]
            ]
            let body = try JSONSerialization.data(withJSONObject: payload)
            let event = try HookRouter.decodeClaudeEvent(body: body, headers: [:])
            guard case .preTool(_, _, _, let subagentLabel) = event.kind else {
                return XCTFail("expected preTool, got \(event.kind)")
            }
            XCTAssertEqual(
                subagentLabel,
                "General-Purpose (Audit non-notch fallback path)",
                "\(toolName) spawns must register a subagent row"
            )
        }
    }

    func testDecodesAsyncSpawnAndIdentifiedSubagentStop() throws {
        let launch: [String: Any] = [
            "session_id": "s-async",
            "hook_event_name": "PostToolUse",
            "tool_name": "Agent",
            "tool_use_id": "toolu_01MH",
            "tool_response": ["isAsync": true, "status": "async_launched", "agentId": "a728691b0e0960cd7"]
        ]
        let launchEvent = try HookRouter.decodeClaudeEvent(
            body: try JSONSerialization.data(withJSONObject: launch),
            headers: [:]
        )
        guard case .postTool(_, _, let asyncAgentID) = launchEvent.kind else {
            return XCTFail("expected postTool, got \(launchEvent.kind)")
        }
        XCTAssertEqual(asyncAgentID, "a728691b0e0960cd7", "a background launch is not a completion")

        // A synchronous tool result carries no agent handle.
        let sync: [String: Any] = [
            "session_id": "s-sync",
            "hook_event_name": "PostToolUse",
            "tool_name": "Agent",
            "tool_use_id": "toolu_02",
            "tool_response": ["content": "the agent's report"]
        ]
        let syncEvent = try HookRouter.decodeClaudeEvent(
            body: try JSONSerialization.data(withJSONObject: sync),
            headers: [:]
        )
        guard case .postTool(_, _, let syncAgentID) = syncEvent.kind else {
            return XCTFail("expected postTool, got \(syncEvent.kind)")
        }
        XCTAssertNil(syncAgentID)

        let stop: [String: Any] = [
            "session_id": "s-async",
            "hook_event_name": "SubagentStop",
            "agent_id": "a728691b0e0960cd7",
            "agent_type": "general-purpose"
        ]
        let stopEvent = try HookRouter.decodeClaudeEvent(
            body: try JSONSerialization.data(withJSONObject: stop),
            headers: [:]
        )
        XCTAssertEqual(stopEvent.kind, .subagentStop(agentID: "a728691b0e0960cd7"))
    }

    func testDecodesTypedNotification() throws {
        let payload: [String: Any] = [
            "session_id": "s-2",
            "hook_event_name": "Notification",
            "notification_type": "permission_prompt",
            "message": "Claude needs your permission to use Bash"
        ]
        let body = try JSONSerialization.data(withJSONObject: payload)
        let event = try HookRouter.decodeClaudeEvent(body: body, headers: [:])
        guard case .notification(_, let category) = event.kind else {
            return XCTFail("expected notification, got \(event.kind)")
        }
        XCTAssertEqual(category, .permission)
    }

    func testDecodesStopWithLastAssistantMessage() throws {
        let payload: [String: Any] = [
            "session_id": "s-3",
            "hook_event_name": "Stop",
            "last_assistant_message": "Done. Rebuilt the checkout flow."
        ]
        let body = try JSONSerialization.data(withJSONObject: payload)
        let event = try HookRouter.decodeClaudeEvent(body: body, headers: [:])
        guard case .stop(let message) = event.kind else {
            return XCTFail("expected stop, got \(event.kind)")
        }
        XCTAssertEqual(message, "Done. Rebuilt the checkout flow.")
    }

    func testRejectsPayloadWithoutSessionID() {
        let body = Data(#"{"hook_event_name":"Stop"}"#.utf8)
        XCTAssertThrowsError(try HookRouter.decodeClaudeEvent(body: body, headers: [:]))
    }

    func testDecodesAskUserQuestionAsQuestionEvent() throws {
        let payload: [String: Any] = [
            "session_id": "s-q",
            "hook_event_name": "PreToolUse",
            "tool_name": "AskUserQuestion",
            "tool_input": [
                "questions": [
                    [
                        "question": "Which fix should I apply?",
                        "header": "Approach",
                        "options": [
                            ["label": "Fix the auth bug", "description": "Patch middleware"],
                            ["label": "Ship as-is", "description": "Defer the fix"]
                        ],
                        "multiSelect": false
                    ]
                ]
            ]
        ]
        let body = try JSONSerialization.data(withJSONObject: payload)
        let event = try HookRouter.decodeClaudeEvent(body: body, headers: [:])
        guard case .question(let text, let options) = event.kind else {
            return XCTFail("expected question, got \(event.kind)")
        }
        XCTAssertEqual(text, "Which fix should I apply?")
        XCTAssertEqual(options, ["Fix the auth bug", "Ship as-is"])
    }

    func testAskUserQuestionCapsOptionsAtNine() throws {
        let options = (1...12).map { ["label": "Option \($0)"] }
        let payload: [String: Any] = [
            "session_id": "s-q9",
            "hook_event_name": "PreToolUse",
            "tool_name": "AskUserQuestion",
            "tool_input": ["questions": [["question": "Pick", "options": options]]]
        ]
        let body = try JSONSerialization.data(withJSONObject: payload)
        let event = try HookRouter.decodeClaudeEvent(body: body, headers: [:])
        guard case .question(_, let decoded) = event.kind else {
            return XCTFail("expected question, got \(event.kind)")
        }
        XCTAssertEqual(decoded.count, 9)
        XCTAssertEqual(decoded.last, "Option 9")
    }

    func testPermissionRequestBuildsBashPreview() throws {
        let payload: [String: Any] = [
            "session_id": "s-p1",
            "hook_event_name": "PermissionRequest",
            "tool_name": "Bash",
            "tool_use_id": "tu-1",
            "tool_input": ["command": "rm -rf build && swift build"]
        ]
        let body = try JSONSerialization.data(withJSONObject: payload)
        let event = try HookRouter.decodeClaudeEvent(body: body, headers: [:])
        guard case .permissionRequest(let tool, _, _, let preview) = event.kind else {
            return XCTFail("expected permissionRequest, got \(event.kind)")
        }
        XCTAssertEqual(tool, "Bash")
        XCTAssertEqual(preview, ToolCallPreview(kind: .bashCommand("rm -rf build && swift build")))
    }

    func testPermissionRequestBuildsEditDiffPreviewWithCompactPath() throws {
        let payload: [String: Any] = [
            "session_id": "s-p2",
            "hook_event_name": "PermissionRequest",
            "cwd": "/Users/dev/proj",
            "tool_name": "Edit",
            "tool_input": [
                "file_path": "/Users/dev/proj/src/main.swift",
                "old_string": "let a = 1",
                "new_string": "let a = 2"
            ]
        ]
        let body = try JSONSerialization.data(withJSONObject: payload)
        let event = try HookRouter.decodeClaudeEvent(body: body, headers: [:])
        guard case .permissionRequest(_, _, _, let preview) = event.kind else {
            return XCTFail("expected permissionRequest, got \(event.kind)")
        }
        XCTAssertEqual(
            preview,
            ToolCallPreview(kind: .editDiff(path: "src/main.swift", old: "let a = 1", new: "let a = 2"))
        )
    }

    func testPermissionRequestUsesFirstMultiEditAsDiff() throws {
        let payload: [String: Any] = [
            "session_id": "s-p3",
            "hook_event_name": "PermissionRequest",
            "tool_name": "MultiEdit",
            "tool_input": [
                "file_path": "/x/y.swift",
                "edits": [
                    ["old_string": "foo", "new_string": "bar"],
                    ["old_string": "baz", "new_string": "qux"]
                ]
            ]
        ]
        let body = try JSONSerialization.data(withJSONObject: payload)
        let event = try HookRouter.decodeClaudeEvent(body: body, headers: [:])
        guard case .permissionRequest(_, _, _, let preview) = event.kind else {
            return XCTFail("expected permissionRequest, got \(event.kind)")
        }
        XCTAssertEqual(preview, ToolCallPreview(kind: .editDiff(path: "/x/y.swift", old: "foo", new: "bar")))
    }

    func testPermissionRequestCapsBashCommandAt600() throws {
        let long = String(repeating: "x", count: 700)
        let payload: [String: Any] = [
            "session_id": "s-p4",
            "hook_event_name": "PermissionRequest",
            "tool_name": "Bash",
            "tool_input": ["command": long]
        ]
        let body = try JSONSerialization.data(withJSONObject: payload)
        let event = try HookRouter.decodeClaudeEvent(body: body, headers: [:])
        guard case .permissionRequest(_, _, _, let preview) = event.kind,
              case .bashCommand(let command)? = preview?.kind else {
            return XCTFail("expected bash preview")
        }
        XCTAssertEqual(command.count, 601, "600 chars + ellipsis")
        XCTAssertTrue(command.hasSuffix("…"))
    }

    func testPermissionRequestFallsBackToGenericDetail() throws {
        let payload: [String: Any] = [
            "session_id": "s-p5",
            "hook_event_name": "PermissionRequest",
            "tool_name": "WebFetch",
            "tool_input": ["url": "https://example.com/docs"]
        ]
        let body = try JSONSerialization.data(withJSONObject: payload)
        let event = try HookRouter.decodeClaudeEvent(body: body, headers: [:])
        guard case .permissionRequest(_, _, _, let preview) = event.kind else {
            return XCTFail("expected permissionRequest, got \(event.kind)")
        }
        XCTAssertEqual(preview, ToolCallPreview(kind: .generic("https://example.com/docs")))
    }

    func testAskUserQuestionWithoutQuestionsFallsBackToPreTool() throws {
        let payload: [String: Any] = [
            "session_id": "s-qf",
            "hook_event_name": "PreToolUse",
            "tool_name": "AskUserQuestion",
            "tool_input": ["unexpected": "shape"]
        ]
        let body = try JSONSerialization.data(withJSONObject: payload)
        let event = try HookRouter.decodeClaudeEvent(body: body, headers: [:])
        guard case .preTool(let toolName, _, _, _) = event.kind else {
            return XCTFail("expected preTool fallback, got \(event.kind)")
        }
        XCTAssertEqual(toolName, "AskUserQuestion")
    }
}
