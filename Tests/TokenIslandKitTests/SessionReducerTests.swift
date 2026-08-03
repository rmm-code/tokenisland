import XCTest
@testable import TokenIslandKit

final class SessionReducerTests: XCTestCase {
    private func context(
        id: String = "sess-1234-abcd",
        cwd: String? = "/Users/dev/my-app"
    ) -> SessionEventContext {
        SessionEventContext(sessionID: id, agent: .claude, cwd: cwd, transcriptPath: "/tmp/t.jsonl")
    }

    func testSessionStartCreatesIdleSession() {
        var sessions: [String: AgentSession] = [:]
        let effects = SessionReducer.reduce(
            sessions: &sessions,
            event: SessionEvent(context: context(), kind: .sessionStart(source: "startup"))
        )
        // A resumed session never sends UserPromptSubmit, so session start has
        // to reach for the transcript or the card stays "New session".
        XCTAssertEqual(effects, [.refreshTranscript(sessionID: "sess-1234-abcd")])
        let session = sessions["sess-1234-abcd"]
        // Opening a CLI is not the agent working — it sits at its prompt.
        XCTAssertEqual(session?.phase, .idle)
        XCTAssertEqual(session?.phase.isActive, false)
        XCTAssertEqual(session?.statusWord, "Idle")
        XCTAssertEqual(session?.projectName, "my-app")
        XCTAssertEqual(session?.agent, .claude)
    }

    func testResumeAndClearStayIdleButCompactKeepsWorking() {
        for source in ["resume", "clear", nil] {
            var sessions: [String: AgentSession] = [:]
            _ = SessionReducer.reduce(
                sessions: &sessions,
                event: SessionEvent(context: context(), kind: .sessionStart(source: source))
            )
            XCTAssertEqual(sessions["sess-1234-abcd"]?.phase, .idle, "source \(source ?? "nil")")
        }
        // Auto-compaction is the one SessionStart that fires mid-turn.
        var sessions: [String: AgentSession] = [:]
        _ = SessionReducer.reduce(
            sessions: &sessions,
            event: SessionEvent(context: context(), kind: .sessionStart(source: "compact"))
        )
        XCTAssertEqual(sessions["sess-1234-abcd"]?.phase, .working)
    }

    func testIdleSessionStartsWorkingOnPrompt() {
        var sessions: [String: AgentSession] = [:]
        _ = SessionReducer.reduce(
            sessions: &sessions,
            event: SessionEvent(context: context(), kind: .sessionStart(source: "resume"))
        )
        XCTAssertEqual(sessions["sess-1234-abcd"]?.phase, .idle)
        _ = SessionReducer.reduce(
            sessions: &sessions,
            event: SessionEvent(context: context(), kind: .userPrompt(prompt: "go"))
        )
        XCTAssertEqual(sessions["sess-1234-abcd"]?.phase, .working)
    }

    /// A finished session that gets resumed must drop its stale activity line
    /// rather than re-showing the tool it was running when it ended.
    func testSessionStartClearsStaleActivity() {
        var sessions: [String: AgentSession] = [:]
        _ = SessionReducer.reduce(
            sessions: &sessions,
            event: SessionEvent(
                context: context(),
                kind: .preTool(toolName: "Bash", detail: "npm test", toolUseID: "t1", subagentLabel: nil)
            )
        )
        XCTAssertNotNil(sessions["sess-1234-abcd"]?.activity)
        _ = SessionReducer.reduce(
            sessions: &sessions,
            event: SessionEvent(context: context(), kind: .sessionStart(source: "resume"))
        )
        XCTAssertEqual(sessions["sess-1234-abcd"]?.phase, .idle)
        XCTAssertNil(sessions["sess-1234-abcd"]?.activity)
    }

    func testUserPromptSetsTitleAndPrompt() {
        var sessions: [String: AgentSession] = [:]
        _ = SessionReducer.reduce(
            sessions: &sessions,
            event: SessionEvent(context: context(), kind: .sessionStart(source: nil))
        )
        _ = SessionReducer.reduce(
            sessions: &sessions,
            event: SessionEvent(
                context: context(),
                kind: .userPrompt(prompt: "fix   the auth\nbug in middleware")
            )
        )
        let session = sessions["sess-1234-abcd"]
        XCTAssertEqual(session?.title, "fix the auth bug in middleware")
        XCTAssertEqual(session?.lastUserPrompt, "fix the auth bug in middleware")
        XCTAssertEqual(session?.phase, .working)
    }

    func testPreToolSetsActivityAndOrphanEventSynthesizesSession() {
        var sessions: [String: AgentSession] = [:]
        _ = SessionReducer.reduce(
            sessions: &sessions,
            event: SessionEvent(
                context: context(id: "orphan-1"),
                kind: .preTool(toolName: "Read", detail: "src/db.ts", toolUseID: "t1", subagentLabel: nil)
            )
        )
        let session = sessions["orphan-1"]
        XCTAssertNotNil(session, "orphan events must synthesize a session")
        XCTAssertEqual(session?.activity?.toolName, "Read")
        XCTAssertEqual(session?.activity?.detail, "src/db.ts")
        XCTAssertEqual(session?.statusWord, "Reading")
    }

    func testFirstToolRetriesTranscriptRefreshWhileModelIsMissing() {
        var sessions: [String: AgentSession] = [:]
        let effects = SessionReducer.reduce(
            sessions: &sessions,
            event: SessionEvent(
                context: context(),
                kind: .preTool(toolName: "Read", detail: "src/db.ts", toolUseID: "t1", subagentLabel: nil)
            )
        )

        XCTAssertEqual(effects, [.refreshTranscript(sessionID: "sess-1234-abcd")])
    }

    func testTaskToolAddsSubagentAndSubagentStopCompletesIt() {
        var sessions: [String: AgentSession] = [:]
        _ = SessionReducer.reduce(
            sessions: &sessions,
            event: SessionEvent(
                context: context(),
                kind: .preTool(toolName: "Task", detail: "Search API endpoints", toolUseID: "task-1", subagentLabel: "Explore (Search API endpoints)")
            )
        )
        XCTAssertEqual(sessions["sess-1234-abcd"]?.subagents.count, 1)
        XCTAssertEqual(sessions["sess-1234-abcd"]?.subagents.first?.isDone, false)

        _ = SessionReducer.reduce(
            sessions: &sessions,
            event: SessionEvent(context: context(), kind: .subagentStop())
        )
        XCTAssertEqual(sessions["sess-1234-abcd"]?.subagents.first?.isDone, true)
    }

    /// `SubagentStop` carries no id. With a fan-out running it used to mark
    /// whichever row it felt like done, so agents went green while still
    /// working; PostToolUse is the exact signal.
    func testSubagentStopOnlySettlesWhenOneAgentIsRunning() {
        var sessions: [String: AgentSession] = [:]
        for index in 1...3 {
            _ = SessionReducer.reduce(
                sessions: &sessions,
                event: SessionEvent(
                    context: context(),
                    kind: .preTool(
                        toolName: "Agent",
                        detail: nil,
                        toolUseID: "task-\(index)",
                        subagentLabel: "Explore (job \(index))"
                    )
                )
            )
        }

        _ = SessionReducer.reduce(sessions: &sessions, event: SessionEvent(context: context(), kind: .subagentStop()))
        XCTAssertEqual(
            sessions["sess-1234-abcd"]?.subagents.filter(\.isDone).count,
            0,
            "an id-less stop must not guess which of three agents finished"
        )

        // PostToolUse settles them exactly, by tool-use id.
        _ = SessionReducer.reduce(
            sessions: &sessions,
            event: SessionEvent(context: context(), kind: .postTool(toolName: "Agent", toolUseID: "task-2"))
        )
        let settled = sessions["sess-1234-abcd"]?.subagents.first { $0.id == "task-2" }
        XCTAssertEqual(settled?.isDone, true)
        XCTAssertEqual(sessions["sess-1234-abcd"]?.subagents.filter(\.isDone).count, 1)

        // Once one is left in flight, the stop hook is unambiguous again.
        _ = SessionReducer.reduce(
            sessions: &sessions,
            event: SessionEvent(context: context(), kind: .postTool(toolName: "Agent", toolUseID: "task-1"))
        )
        _ = SessionReducer.reduce(sessions: &sessions, event: SessionEvent(context: context(), kind: .subagentStop()))
        XCTAssertEqual(sessions["sess-1234-abcd"]?.subagents.filter(\.isDone).count, 3)
    }

    /// A background spawn returns from its tool call at launch. Treating that
    /// as completion turned every background agent green a second after it
    /// started; the agent's own stop event is the real signal.
    func testBackgroundSpawnStaysRunningUntilItsAgentStops() {
        var sessions: [String: AgentSession] = [:]
        for index in 1...2 {
            _ = SessionReducer.reduce(
                sessions: &sessions,
                event: SessionEvent(
                    context: context(),
                    kind: .preTool(
                        toolName: "Agent",
                        detail: nil,
                        toolUseID: "task-\(index)",
                        subagentLabel: "Explore (job \(index))"
                    )
                )
            )
            _ = SessionReducer.reduce(
                sessions: &sessions,
                event: SessionEvent(
                    context: context(),
                    kind: .postTool(toolName: "Agent", toolUseID: "task-\(index)", asyncAgentID: "agent-\(index)")
                )
            )
        }

        var subagents = sessions["sess-1234-abcd"]?.subagents ?? []
        XCTAssertEqual(subagents.filter(\.isDone).count, 0, "launching is not finishing")
        XCTAssertEqual(subagents.first?.agentID, "agent-1", "the stop handle is recorded at launch")

        // Two agents in flight: the stop event names which one ended.
        _ = SessionReducer.reduce(
            sessions: &sessions,
            event: SessionEvent(context: context(), kind: .subagentStop(agentID: "agent-2"))
        )
        subagents = sessions["sess-1234-abcd"]?.subagents ?? []
        XCTAssertEqual(subagents.first { $0.id == "task-2" }?.isDone, true)
        XCTAssertEqual(subagents.first { $0.id == "task-1" }?.isDone, false, "the wrong row must not settle")
    }

    /// A flat `suffix(6)` dropped live agents off the front of a wide fan-out.
    func testWideFanOutKeepsEveryRunningAgent() {
        var sessions: [String: AgentSession] = [:]
        for index in 1...12 {
            _ = SessionReducer.reduce(
                sessions: &sessions,
                event: SessionEvent(
                    context: context(),
                    kind: .preTool(
                        toolName: "Agent",
                        detail: nil,
                        toolUseID: "task-\(index)",
                        subagentLabel: "Explore (job \(index))"
                    )
                )
            )
        }
        let session = try? XCTUnwrap(sessions["sess-1234-abcd"])
        XCTAssertEqual(session?.subagents.count, 12, "every in-flight agent stays on the card")

        // Finished ones are what gets trimmed, oldest first.
        for index in 1...12 {
            _ = SessionReducer.reduce(
                sessions: &sessions,
                event: SessionEvent(context: context(), kind: .postTool(toolName: "Agent", toolUseID: "task-\(index)"))
            )
        }
        _ = SessionReducer.reduce(
            sessions: &sessions,
            event: SessionEvent(
                context: context(),
                kind: .preTool(toolName: "Agent", detail: nil, toolUseID: "task-13", subagentLabel: "Explore (job 13)")
            )
        )
        let trimmed = sessions["sess-1234-abcd"]?.subagents
        XCTAssertEqual(trimmed?.count, SessionReducer.subagentHistoryLimit)
        XCTAssertEqual(trimmed?.last?.id, "task-13", "the newest agent is never the one dropped")
        XCTAssertTrue(trimmed?.contains { !$0.isDone } == true)
    }

    func testPermissionNotificationFlipsToWaitingApproval() {
        var sessions: [String: AgentSession] = [:]
        _ = SessionReducer.reduce(
            sessions: &sessions,
            event: SessionEvent(context: context(), kind: .sessionStart(source: nil))
        )
        let effects = SessionReducer.reduce(
            sessions: &sessions,
            event: SessionEvent(
                context: context(),
                kind: .notification(message: "Claude needs your permission to use Bash", category: .permission)
            )
        )
        XCTAssertEqual(sessions["sess-1234-abcd"]?.phase, .waitingApproval)
        XCTAssertEqual(effects, [.revealAttention(sessionID: "sess-1234-abcd")])
    }

    func testPermissionRequestSetsPreviewAndPreToolClearsIt() {
        var sessions: [String: AgentSession] = [:]
        let preview = ToolCallPreview(kind: .editDiff(path: "src/a.swift", old: "let x = 1", new: "let x = 2"))
        let effects = SessionReducer.reduce(
            sessions: &sessions,
            event: SessionEvent(
                context: context(),
                kind: .permissionRequest(toolName: "Edit", detail: "src/a.swift", toolUseID: "t1", preview: preview)
            )
        )
        var session = sessions["sess-1234-abcd"]
        XCTAssertEqual(session?.phase, .waitingApproval)
        XCTAssertEqual(session?.pendingApprovalMessage, "Allow Edit: src/a.swift?")
        XCTAssertEqual(session?.pendingApprovalPreview, preview)
        XCTAssertEqual(effects, [.revealAttention(sessionID: "sess-1234-abcd")])

        _ = SessionReducer.reduce(
            sessions: &sessions,
            event: SessionEvent(
                context: context(),
                kind: .preTool(toolName: "Edit", detail: "src/a.swift", toolUseID: "t1", subagentLabel: nil)
            )
        )
        session = sessions["sess-1234-abcd"]
        XCTAssertNil(session?.pendingApprovalMessage)
        XCTAssertNil(session?.pendingApprovalPreview)
    }

    func testStopClearsApprovalPreview() {
        var sessions: [String: AgentSession] = [:]
        _ = SessionReducer.reduce(
            sessions: &sessions,
            event: SessionEvent(
                context: context(),
                kind: .permissionRequest(
                    toolName: "Bash",
                    detail: "npm test",
                    toolUseID: "t1",
                    preview: ToolCallPreview(kind: .bashCommand("npm test"))
                )
            )
        )
        _ = SessionReducer.reduce(
            sessions: &sessions,
            event: SessionEvent(context: context(), kind: .stop(lastAssistantMessage: "Done."))
        )
        XCTAssertNil(sessions["sess-1234-abcd"]?.pendingApprovalPreview)
    }

    func testStopWithMessageProducesCompletionAndReveal() {
        var sessions: [String: AgentSession] = [:]
        _ = SessionReducer.reduce(
            sessions: &sessions,
            event: SessionEvent(context: context(), kind: .sessionStart(source: nil))
        )
        let effects = SessionReducer.reduce(
            sessions: &sessions,
            event: SessionEvent(
                context: context(),
                kind: .stop(lastAssistantMessage: "I've refactored the function to use early returns.\nKey changes follow.")
            )
        )
        let session = sessions["sess-1234-abcd"]
        XCTAssertEqual(session?.phase, .ready)
        XCTAssertEqual(session?.completionTLDR, "I've refactored the function to use early returns. Key changes follow.")
        // Transcript refresh always runs on Stop now — it supplies the model name.
        XCTAssertEqual(effects, [
            .refreshTranscript(sessionID: "sess-1234-abcd"),
            .revealCompletion(sessionID: "sess-1234-abcd")
        ])
    }

    func testStopWithoutMessageRequestsTranscriptRefresh() {
        var sessions: [String: AgentSession] = [:]
        _ = SessionReducer.reduce(
            sessions: &sessions,
            event: SessionEvent(context: context(), kind: .sessionStart(source: nil))
        )
        let effects = SessionReducer.reduce(
            sessions: &sessions,
            event: SessionEvent(context: context(), kind: .stop(lastAssistantMessage: nil))
        )
        XCTAssertEqual(effects, [
            .refreshTranscript(sessionID: "sess-1234-abcd"),
            .revealCompletion(sessionID: "sess-1234-abcd")
        ])
    }

    func testSessionEndSchedulesRemoval() {
        var sessions: [String: AgentSession] = [:]
        _ = SessionReducer.reduce(
            sessions: &sessions,
            event: SessionEvent(context: context(), kind: .sessionStart(source: nil))
        )
        let effects = SessionReducer.reduce(
            sessions: &sessions,
            event: SessionEvent(context: context(), kind: .sessionEnd(reason: "exit"))
        )
        XCTAssertEqual(sessions["sess-1234-abcd"]?.phase, .ended)
        XCTAssertEqual(effects, [.scheduleRemoval(sessionID: "sess-1234-abcd")])
    }

    func testQuestionEventSetsPhaseOptionsAndReveals() {
        var sessions: [String: AgentSession] = [:]
        _ = SessionReducer.reduce(
            sessions: &sessions,
            event: SessionEvent(context: context(), kind: .sessionStart(source: nil))
        )
        let effects = SessionReducer.reduce(
            sessions: &sessions,
            event: SessionEvent(
                context: context(),
                kind: .question(text: "Which approach?", options: ["Fix the auth bug", "Ship as-is"])
            )
        )
        let session = sessions["sess-1234-abcd"]
        XCTAssertEqual(session?.phase, .question)
        XCTAssertEqual(session?.pendingQuestionMessage, "Which approach?")
        XCTAssertEqual(session?.questionOptions, ["Fix the auth bug", "Ship as-is"])
        XCTAssertEqual(effects, [.revealAttention(sessionID: "sess-1234-abcd")])
    }

    func testUserPromptClearsQuestionOptions() {
        var sessions: [String: AgentSession] = [:]
        _ = SessionReducer.reduce(
            sessions: &sessions,
            event: SessionEvent(context: context(), kind: .question(text: "Pick one", options: ["A", "B"]))
        )
        _ = SessionReducer.reduce(
            sessions: &sessions,
            event: SessionEvent(context: context(), kind: .userPrompt(prompt: "go with A"))
        )
        let session = sessions["sess-1234-abcd"]
        XCTAssertEqual(session?.phase, .working)
        XCTAssertNil(session?.pendingQuestionMessage)
        XCTAssertEqual(session?.questionOptions, [])
    }

    func testStopClearsQuestionOptions() {
        var sessions: [String: AgentSession] = [:]
        _ = SessionReducer.reduce(
            sessions: &sessions,
            event: SessionEvent(context: context(), kind: .question(text: "Pick one", options: ["A"]))
        )
        _ = SessionReducer.reduce(
            sessions: &sessions,
            event: SessionEvent(context: context(), kind: .stop(lastAssistantMessage: "Done."))
        )
        let session = sessions["sess-1234-abcd"]
        XCTAssertEqual(session?.phase, .ready)
        XCTAssertEqual(session?.questionOptions, [])
    }

    func testPostToolForAskUserQuestionClearsQuestion() {
        var sessions: [String: AgentSession] = [:]
        _ = SessionReducer.reduce(
            sessions: &sessions,
            event: SessionEvent(context: context(), kind: .question(text: "Pick one", options: ["A", "B"]))
        )
        _ = SessionReducer.reduce(
            sessions: &sessions,
            event: SessionEvent(context: context(), kind: .postTool(toolName: "AskUserQuestion", toolUseID: "q1"))
        )
        let session = sessions["sess-1234-abcd"]
        XCTAssertEqual(session?.phase, .working)
        XCTAssertNil(session?.pendingQuestionMessage)
        XCTAssertEqual(session?.questionOptions, [])
    }

    func testMarkerIDIsStableEightChars() {
        let session = AgentSession(
            id: "abc-def-123456789",
            agent: .claude,
            projectPath: "/tmp",
            title: nil,
            lastUserPrompt: nil,
            completionTLDR: nil,
            completionText: nil,
            model: nil,
            phase: .working,
            activity: nil,
            pendingApprovalMessage: nil,
            pendingQuestionMessage: nil,
            terminalHint: nil,
            transcriptPath: nil,
            startedAt: .now,
            lastEventAt: .now,
            endedAt: nil
        )
        XCTAssertEqual(session.markerID, "abcdef12")
    }
}

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
