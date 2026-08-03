import XCTest
@testable import TokenIslandKit

final class CodexWatcherTests: XCTestCase {
    // MARK: - Parser

    func testParserHandlesKnownAndUnknownLineShapes() {
        let fixture = """
        {"timestamp":"\(isoNow())","type":"session_meta","payload":{"id":"0199-abcd","cwd":"/Users/dev/proj","cli_version":"0.125.0"}}
        {"timestamp":"\(isoNow())","type":"event_msg","payload":{"type":"task_started","turn_id":"t1","model_context_window":258400}}
        {"timestamp":"\(isoNow())","type":"event_msg","payload":{"type":"user_message","message":"# Context from my IDE setup:\\n\\n## Active file: a.py\\n\\n## My request for Codex:\\nfix the login bug"}}
        {"timestamp":"\(isoNow())","type":"event_msg","payload":{"type":"token_count","info":null,"rate_limits":{"primary":{"used_percent":2.0}}}}
        {"timestamp":"\(isoNow())","type":"response_item","payload":{"type":"message","role":"assistant","content":[{"type":"output_text","text":"Found it, patching now."}]}}
        {"timestamp":"\(isoNow())","type":"response_item","payload":{"type":"message","role":"developer","content":[{"type":"input_text","text":"<permissions instructions>"}]}}
        {"timestamp":"\(isoNow())","type":"event_msg","payload":{"type":"agent_message","message":"Patched the guard.","phase":"commentary"}}
        {"timestamp":"\(isoNow())","type":"event_msg","payload":{"type":"exec_command_end","call_id":"c1","stdout":""}}
        {"timestamp":"\(isoNow())","type":"event_msg","payload":{"type":"task_complete","turn_id":"t1","last_agent_message":"Fixed the login bug."}}
        not json at all
        """

        let records = CodexRolloutParser.records(fromLines: Data(fixture.utf8))
        let events = records.map(\.event)
        XCTAssertEqual(events, [
            .sessionMeta(id: "0199-abcd", cwd: "/Users/dev/proj"),
            .taskStarted,
            .userMessage(text: "fix the login bug"),
            .tokenCount,
            .agentMessage(text: "Found it, patching now."),
            .agentMessage(text: "Patched the guard."),
            .taskComplete(lastAgentMessage: "Fixed the login bug.")
        ])
        XCTAssertNotNil(records.first?.timestamp)
    }

    func testParserSkipsInjectedUserContextItems() {
        let line = #"{"type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"<environment_context>sandbox</environment_context>"}]}}"#
        XCTAssertNil(CodexRolloutParser.record(fromLine: Data(line.utf8)))
    }

    func testParserCapturesTurnContextModel() {
        let line = #"{"type":"turn_context","payload":{"cwd":"/Users/dev/proj","model":"gpt-5.3-codex"}}"#
        let record = CodexRolloutParser.record(fromLine: Data(line.utf8))

        XCTAssertEqual(
            record?.event,
            .turnContext(cwd: "/Users/dev/proj", model: "gpt-5.3-codex")
        )
    }

    func testModelNameFormatterUsesCodexBranding() {
        XCTAssertEqual(ModelNameFormatter.displayName("gpt-5.3-codex"), "GPT-5.3 Codex")
        XCTAssertEqual(ModelNameFormatter.displayName("openai/gpt-5.1-codex-max"), "GPT-5.1 Codex Max")
        XCTAssertEqual(ModelNameFormatter.displayName("codex-mini-latest"), "Codex Mini")
        XCTAssertEqual(ModelNameFormatter.displayName("gpt-5.6-sol"), "GPT-5.6 Sol")
        XCTAssertEqual(ModelNameFormatter.displayName("codex-auto-review"), "Codex Auto Review")
    }

    func testModelNameFormatterHandlesCurrentProviderModelIDs() {
        XCTAssertEqual(ModelNameFormatter.displayName("claude-fable-5"), "Fable 5")
        XCTAssertEqual(ModelNameFormatter.displayName("claude-opus-4-8"), "Opus 4.8")
        XCTAssertEqual(ModelNameFormatter.displayName("claude-sonnet-5"), "Sonnet 5")
        XCTAssertEqual(ModelNameFormatter.displayName("claude-haiku-4-5-20251001"), "Haiku 4.5")
        XCTAssertEqual(ModelNameFormatter.displayName("anthropic.claude-sonnet-5"), "Sonnet 5")
        XCTAssertEqual(
            ModelNameFormatter.displayName("anthropic.claude-haiku-4-5-20251001-v1:0"),
            "Haiku 4.5"
        )
        XCTAssertEqual(ModelNameFormatter.displayName("claude-haiku-4-5@20251001"), "Haiku 4.5")
        XCTAssertEqual(ModelNameFormatter.displayName("claude-3-5-sonnet-20241022"), "Sonnet 3.5")
        XCTAssertEqual(ModelNameFormatter.displayName("gemini-3.5-flash"), "Gemini 3.5 Flash")
        XCTAssertEqual(ModelNameFormatter.displayName("gemini-3.1-pro-preview"), "Gemini 3.1 Pro Preview")
        XCTAssertEqual(ModelNameFormatter.displayName("models/gemini-2.5-flash-lite"), "Gemini 2.5 Flash Lite")
        XCTAssertEqual(ModelNameFormatter.displayName("gemini-flash-latest"), "Gemini Flash")
        XCTAssertNil(ModelNameFormatter.displayName("<synthetic>"))
        XCTAssertEqual(ModelNameFormatter.displayName("vendor/new-model-v2"), "vendor/new-model-v2")
    }

    // MARK: - Watcher

    @MainActor
    func testPollEmitsCatchUpThenOnlyAppendedEvents() async throws {
        let directory = try makeSessionsDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("rollout-2026-07-16-test.jsonl")

        let initial = [
            line(type: "session_meta", payload: #"{"id":"sess-1","cwd":"/Users/dev/proj"}"#),
            line(type: "turn_context", payload: #"{"cwd":"/Users/dev/proj","model":"gpt-5.3-codex"}"#),
            eventLine(#"{"type":"user_message","message":"add tests"}"#),
            eventLine(#"{"type":"task_started","turn_id":"t1"}"#),
            eventLine(#"{"type":"token_count","info":null}"#)
        ].joined(separator: "\n") + "\n"
        try Data(initial.utf8).write(to: file)

        let sink = EventSink()
        let watcher = CodexSessionWatcher(sessionsDirectory: directory) { sink.append($0) }

        await watcher.pollOnce()
        var kinds = sink.events.map(\.kind)
        XCTAssertEqual(kinds, [
            .sessionStart(source: "codex"),
            .userPrompt(prompt: "add tests"),
            .preTool(toolName: "Codex", detail: "working…", toolUseID: nil, subagentLabel: nil)
        ])
        XCTAssertEqual(sink.events.first?.context.sessionID, "codex-sess-1")
        XCTAssertEqual(sink.events.first?.context.cwd, "/Users/dev/proj")
        XCTAssertEqual(sink.events.first?.context.agent, .codex)
        XCTAssertTrue(sink.events.allSatisfy { $0.context.model == "gpt-5.3-codex" })

        // Nothing new appended → nothing new emitted.
        await watcher.pollOnce()
        XCTAssertEqual(sink.events.count, 3)

        // Commentary is held while a task runs; task_complete ends the turn.
        let appended = [
            line(type: "turn_context", payload: #"{"cwd":"/Users/dev/proj","model":"gpt-5.4-codex"}"#),
            eventLine(#"{"type":"agent_message","message":"working through it"}"#),
            eventLine(#"{"type":"task_complete","turn_id":"t1","last_agent_message":"Tests added."}"#)
        ].joined(separator: "\n") + "\n"
        let handle = try FileHandle(forWritingTo: file)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(appended.utf8))
        try handle.close()

        await watcher.pollOnce()
        kinds = sink.events.map(\.kind)
        XCTAssertEqual(kinds.count, 4)
        XCTAssertEqual(kinds.last, .stop(lastAssistantMessage: "Tests added."))
        XCTAssertEqual(sink.events.last?.context.model, "gpt-5.4-codex")

        var sessions: [String: AgentSession] = [:]
        for event in sink.events {
            _ = SessionReducer.reduce(sessions: &sessions, event: event)
        }
        XCTAssertEqual(sessions["codex-sess-1"]?.model, "gpt-5.4-codex")
    }

    @MainActor
    func testFirstSeenRolloutMidTaskRemainsWorking() async throws {
        let directory = try makeSessionsDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("rollout-2026-07-16-mid-task.jsonl")

        let initial = [
            line(type: "session_meta", payload: #"{"id":"sess-mid-task","cwd":"/Users/dev/proj"}"#),
            line(type: "turn_context", payload: #"{"cwd":"/Users/dev/proj","model":"gpt-5.3-codex"}"#),
            eventLine(#"{"type":"user_message","message":"keep working"}"#),
            eventLine(#"{"type":"task_started","turn_id":"t1"}"#),
            eventLine(#"{"type":"agent_message","message":"Still investigating.","phase":"commentary"}"#)
        ].joined(separator: "\n") + "\n"
        try Data(initial.utf8).write(to: file)

        let sink = EventSink()
        let watcher = CodexSessionWatcher(sessionsDirectory: directory) { sink.append($0) }

        await watcher.pollOnce()

        XCTAssertEqual(sink.events.map(\.kind), [
            .sessionStart(source: "codex"),
            .userPrompt(prompt: "keep working"),
            .preTool(toolName: "Codex", detail: "working…", toolUseID: nil, subagentLabel: nil)
        ])
        XCTAssertEqual(sink.events.last?.context.model, "gpt-5.3-codex")
    }

    @MainActor
    func testStaleHistoryIsTrackedSilentlyUntilNewActivity() async throws {
        let directory = try makeSessionsDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("rollout-2026-07-16-old.jsonl")

        let staleDate = isoNow(offset: -3 * 3600)
        let initial = [
            line(type: "session_meta", payload: #"{"id":"sess-2","cwd":"/Users/dev/old"}"#, timestamp: staleDate),
            eventLine(#"{"type":"user_message","message":"old prompt"}"#, timestamp: staleDate)
        ].joined(separator: "\n") + "\n"
        try Data(initial.utf8).write(to: file)

        let sink = EventSink()
        let watcher = CodexSessionWatcher(sessionsDirectory: directory) { sink.append($0) }

        await watcher.pollOnce()
        XCTAssertTrue(sink.events.isEmpty, "stale history must not surface a session")

        let appended = eventLine(#"{"type":"user_message","message":"back again"}"#) + "\n"
        let handle = try FileHandle(forWritingTo: file)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(appended.utf8))
        try handle.close()

        await watcher.pollOnce()
        XCTAssertEqual(sink.events.map(\.kind), [
            .sessionStart(source: "codex"),
            .userPrompt(prompt: "back again")
        ])
        XCTAssertEqual(sink.events.first?.context.sessionID, "codex-sess-2")
        XCTAssertEqual(sink.events.first?.context.cwd, "/Users/dev/old")
    }

    // MARK: - Helpers

    private final class EventSink: @unchecked Sendable {
        private let lock = NSLock()
        private var storage: [SessionEvent] = []

        func append(_ event: SessionEvent) {
            lock.lock()
            storage.append(event)
            lock.unlock()
        }

        var events: [SessionEvent] {
            lock.lock()
            defer { lock.unlock() }
            return storage
        }
    }

    /// Codex writes no exit record, so replaying a rollout at launch used to
    /// resurrect a run that had already finished — a Codex card on the notch
    /// with no Codex running. A completed-and-quiet rollout is history.
    @MainActor
    func testFinishedRunIsNotResurrectedOnFirstSight() async throws {
        let directory = try makeSessionsDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("rollout-2026-08-01-finished.jsonl")

        let finishedAt = isoNow(offset: -58 * 60)
        let contents = [
            line(type: "session_meta", payload: #"{"id":"sess-done","cwd":"/Users/dev/tmp"}"#, timestamp: finishedAt),
            eventLine(#"{"type":"user_message","message":"Say only: pong"}"#, timestamp: finishedAt),
            eventLine(#"{"type":"task_started","turn_id":"t1"}"#, timestamp: finishedAt),
            eventLine(#"{"type":"task_complete","turn_id":"t1","last_agent_message":"pong"}"#, timestamp: finishedAt),
            eventLine(#"{"type":"token_count","info":null}"#, timestamp: finishedAt)
        ].joined(separator: "\n") + "\n"
        try Data(contents.utf8).write(to: file)

        let sink = EventSink()
        let watcher = CodexSessionWatcher(sessionsDirectory: directory) { sink.append($0) }
        await watcher.pollOnce()

        XCTAssertTrue(sink.events.isEmpty, "a finished run must not surface a card")

        // Still tracked: if that same session comes back to life, it announces.
        let resumed = [
            eventLine(#"{"type":"user_message","message":"now do the next thing"}"#),
            eventLine(#"{"type":"task_started","turn_id":"t2"}"#)
        ].joined(separator: "\n") + "\n"
        let handle = try FileHandle(forWritingTo: file)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(resumed.utf8))
        try handle.close()

        await watcher.pollOnce()
        XCTAssertEqual(sink.events.map(\.kind), [
            .sessionStart(source: "codex"),
            .userPrompt(prompt: "now do the next thing"),
            .preTool(toolName: "Codex", detail: "working…", toolUseID: nil, subagentLabel: nil)
        ])
        XCTAssertEqual(sink.events.first?.context.sessionID, "codex-sess-done")
    }

    /// The narrow window right after a run ends must still show the result —
    /// that is the whole point of the completion card.
    @MainActor
    func testJustFinishedRunStillSurfaces() async throws {
        let directory = try makeSessionsDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("rollout-2026-08-01-justdone.jsonl")

        let justNow = isoNow(offset: -20)
        let contents = [
            line(type: "session_meta", payload: #"{"id":"sess-fresh","cwd":"/Users/dev/tmp"}"#, timestamp: justNow),
            eventLine(#"{"type":"user_message","message":"Say only: pong"}"#, timestamp: justNow),
            eventLine(#"{"type":"task_complete","turn_id":"t1","last_agent_message":"pong"}"#, timestamp: justNow)
        ].joined(separator: "\n") + "\n"
        try Data(contents.utf8).write(to: file)

        let sink = EventSink()
        let watcher = CodexSessionWatcher(sessionsDirectory: directory) { sink.append($0) }
        await watcher.pollOnce()

        XCTAssertEqual(sink.events.map(\.kind).first, .sessionStart(source: "codex"))
        XCTAssertEqual(sink.events.map(\.kind).last, .stop(lastAssistantMessage: "pong"))
    }

    /// An hour-old rollout with a turn still in flight is a live session that
    /// has simply been thinking, and must not be mistaken for history.
    @MainActor
    func testOlderRunWithATurnInFlightStillSurfaces() async throws {
        let directory = try makeSessionsDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("rollout-2026-08-01-inflight.jsonl")

        let awhileAgo = isoNow(offset: -40 * 60)
        let contents = [
            line(type: "session_meta", payload: #"{"id":"sess-busy","cwd":"/Users/dev/tmp"}"#, timestamp: awhileAgo),
            eventLine(#"{"type":"user_message","message":"long job"}"#, timestamp: awhileAgo),
            eventLine(#"{"type":"task_complete","turn_id":"t1","last_agent_message":"done one"}"#, timestamp: awhileAgo),
            eventLine(#"{"type":"user_message","message":"another one"}"#, timestamp: awhileAgo),
            eventLine(#"{"type":"task_started","turn_id":"t2"}"#, timestamp: awhileAgo)
        ].joined(separator: "\n") + "\n"
        try Data(contents.utf8).write(to: file)

        let sink = EventSink()
        let watcher = CodexSessionWatcher(sessionsDirectory: directory) { sink.append($0) }
        await watcher.pollOnce()

        XCTAssertFalse(sink.events.isEmpty, "a turn still running is a live session")
        XCTAssertEqual(sink.events.first?.kind, .sessionStart(source: "codex"))
    }

    func testEndsOnCompletedTurnIgnoresTrailingHeartbeats() {
        let complete = CodexRolloutRecord(timestamp: nil, event: .taskComplete(lastAgentMessage: "pong"))
        let heartbeat = CodexRolloutRecord(timestamp: nil, event: .tokenCount)
        let started = CodexRolloutRecord(timestamp: nil, event: .taskStarted)
        let prompt = CodexRolloutRecord(timestamp: nil, event: .userMessage(text: "go"))

        XCTAssertTrue(CodexSessionWatcher.endsOnCompletedTurn([prompt, complete, heartbeat]))
        XCTAssertFalse(CodexSessionWatcher.endsOnCompletedTurn([complete, prompt, started]))
        // A prompt with no completion after it means a turn is still in flight.
        XCTAssertFalse(CodexSessionWatcher.endsOnCompletedTurn([complete, prompt]))
        XCTAssertFalse(CodexSessionWatcher.endsOnCompletedTurn([]))
    }

    private func makeSessionsDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-watcher-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func isoNow(offset: TimeInterval = 0) -> String {
        ISO8601DateFormatter().string(from: Date().addingTimeInterval(offset))
    }

    private func line(type: String, payload: String, timestamp: String? = nil) -> String {
        #"{"timestamp":"\#(timestamp ?? isoNow())","type":"\#(type)","payload":\#(payload)}"#
    }

    private func eventLine(_ payload: String, timestamp: String? = nil) -> String {
        line(type: "event_msg", payload: payload, timestamp: timestamp)
    }
}
