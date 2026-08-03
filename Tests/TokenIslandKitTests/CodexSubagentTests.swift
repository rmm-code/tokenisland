import XCTest
@testable import TokenIslandKit

/// Codex writes one rollout file per thread, and most of them are not
/// conversations: fan-out subagents get their own file, and so does every
/// internal guardian reviewer. Shapes below are taken from real rollouts.
final class CodexSubagentTests: XCTestCase {
    private func meta(_ json: String) throws -> CodexRolloutEvent? {
        try XCTUnwrap(CodexRolloutParser.record(fromLine: Data(json.utf8))).event
    }

    func testFanOutThreadCarriesParentAndLabel() throws {
        let line = """
        {"timestamp":"2026-07-21T21:30:41.682Z","type":"session_meta","payload":{\
        "id":"019f8696-child","cwd":"/Users/dev/taxi","thread_source":"subagent",\
        "source":{"subagent":{"thread_spawn":{"parent_thread_id":"019f5a9a-parent","depth":1,\
        "agent_path":"/root/backend_logic_audit","agent_nickname":"Linnaeus","agent_role":null}}}}}
        """
        guard case .sessionMeta(let id, let cwd, let thread) = try meta(line) else {
            return XCTFail("expected session_meta")
        }
        XCTAssertEqual(id, "019f8696-child")
        XCTAssertEqual(cwd, "/Users/dev/taxi")
        XCTAssertEqual(thread?.isSubagent, true)
        XCTAssertEqual(thread?.isInternalWorker, false)
        XCTAssertEqual(thread?.parentThreadID, "019f5a9a-parent")
        XCTAssertEqual(thread?.label, "Linnaeus")
    }

    func testGuardianThreadIsFlaggedAsInternal() throws {
        let line = """
        {"timestamp":"2026-07-21T21:30:41.682Z","type":"session_meta","payload":{\
        "id":"019f-guardian","cwd":"/Users/dev/taxi","thread_source":"subagent",\
        "parent_thread_id":"019f5a9a-parent","source":{"subagent":{"other":"guardian"}}}}
        """
        guard case .sessionMeta(_, _, let thread) = try meta(line) else {
            return XCTFail("expected session_meta")
        }
        XCTAssertEqual(thread?.isInternalWorker, true, "guardian threads are machinery, not sessions")
    }

    func testAgentPathIsTheLabelWhenThereIsNoNickname() throws {
        let line = """
        {"type":"session_meta","payload":{"id":"c1","thread_source":"subagent",\
        "source":{"subagent":{"thread_spawn":{"parent_thread_id":"p1","agent_path":"/root/reliability_review"}}}}}
        """
        guard case .sessionMeta(_, _, let thread) = try meta(line) else {
            return XCTFail("expected session_meta")
        }
        XCTAssertEqual(thread?.label, "reliability_review")
    }

    func testOrdinaryConversationHasNoThreadInfo() throws {
        let line = """
        {"type":"session_meta","payload":{"id":"019f-user","cwd":"/Users/dev/app",\
        "thread_source":"user","originator":"codex-tui"}}
        """
        guard case .sessionMeta(_, _, let thread) = try meta(line) else {
            return XCTFail("expected session_meta")
        }
        XCTAssertNil(thread, "a user thread must stay a normal session")
    }

    // MARK: - Watcher routing

    private final class EventSink: @unchecked Sendable {
        private(set) var events: [SessionEvent] = []
        func append(_ event: SessionEvent) { events.append(event) }
    }

    @MainActor
    private func events(fromRollout lines: [String], fileName: String) async -> [SessionEvent] {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("codex-subagent-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent(fileName)
        try? (lines.joined(separator: "\n") + "\n").write(to: file, atomically: true, encoding: .utf8)

        let sink = EventSink()
        let watcher = CodexSessionWatcher(sessionsDirectory: directory) { sink.append($0) }
        await watcher.pollOnce()
        return sink.events
    }

    @MainActor
    func testGuardianRolloutProducesNoSessionAtAll() async {
        let now = ISO8601DateFormatter().string(from: Date())
        let events = await events(
            fromRollout: [
                """
                {"timestamp":"\(now)","type":"session_meta","payload":{"id":"g1","cwd":"/Users/dev/app",\
                "thread_source":"subagent","parent_thread_id":"p1","source":{"subagent":{"other":"guardian"}}}}
                """,
                """
                {"timestamp":"\(now)","type":"event_msg","payload":{"type":"user_message",\
                "message":"The following is the Codex agent history whose request action you are assessing"}}
                """
            ],
            fileName: "rollout-2026-07-21T21-30-41-g1.jsonl"
        )
        XCTAssertTrue(events.isEmpty, "a guardian reviewer must never surface as a card")
    }

    @MainActor
    func testFanOutRolloutBecomesARowOnItsParent() async {
        let now = ISO8601DateFormatter().string(from: Date())
        let events = await events(
            fromRollout: [
                """
                {"timestamp":"\(now)","type":"session_meta","payload":{"id":"c1","cwd":"/Users/dev/taxi",\
                "thread_source":"subagent","source":{"subagent":{"thread_spawn":{"parent_thread_id":"p1",\
                "agent_nickname":"Linnaeus","agent_path":"/root/backend_logic_audit"}}}}}
                """,
                """
                {"timestamp":"\(now)","type":"event_msg","payload":{"type":"task_complete",\
                "last_agent_message":"audit done"}}
                """
            ],
            fileName: "rollout-2026-07-21T21-30-41-c1.jsonl"
        )

        XCTAssertTrue(
            events.allSatisfy { $0.context.sessionID == "codex-p1" },
            "a subagent thread reports to its parent, never as its own session"
        )
        guard case .preTool(let tool, _, let toolUseID, let label)? = events.first?.kind else {
            return XCTFail("expected a subagent row, got \(String(describing: events.first?.kind))")
        }
        XCTAssertEqual(tool, "Agent")
        XCTAssertEqual(label, "Linnaeus")
        XCTAssertEqual(toolUseID, "codex-c1")
        XCTAssertEqual(events.last?.kind, .postTool(toolName: "Agent", toolUseID: "codex-c1"))
    }

    /// Re-announcing a running row is how the watcher reports progress; it must
    /// update the row rather than stack another one.
    @MainActor
    func testRepeatedAnnouncementUpdatesTheSameRow() {
        var sessions: [String: AgentSession] = [:]
        let context = SessionEventContext(sessionID: "codex-p1", agent: .codex, cwd: "/Users/dev/taxi")
        for detail in ["working…", "audited the payment guard"] {
            _ = SessionReducer.reduce(
                sessions: &sessions,
                event: SessionEvent(
                    context: context,
                    kind: .preTool(toolName: "Agent", detail: detail, toolUseID: "codex-c1", subagentLabel: "Linnaeus")
                )
            )
        }
        let subagents = sessions["codex-p1"]?.subagents ?? []
        XCTAssertEqual(subagents.count, 1, "one agent, one row")
        XCTAssertEqual(subagents.first?.detail, "audited the payment guard")
    }
}
