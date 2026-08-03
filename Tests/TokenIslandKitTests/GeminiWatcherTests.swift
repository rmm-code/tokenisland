import XCTest
@testable import TokenIslandKit

final class GeminiWatcherTests: XCTestCase {
    // MARK: - Parser

    func testParserReadsConversationRecord() {
        let fixture = """
        {
          "sessionId": "abc-123",
          "projectHash": "deadbeef",
          "startTime": "\(isoNow(offset: -60))",
          "lastUpdated": "\(isoNow())",
          "messages": [
            {"id": "1", "timestamp": "\(isoNow(offset: -50))", "type": "user", "content": "fix the bug"},
            {"id": "2", "timestamp": "\(isoNow(offset: -10))", "type": "gemini", "content": "Done.",
             "model": "gemini-2.5-pro",
             "toolCalls": [
               {"id": "t1", "name": "read_file", "args": {"absolute_path": "/a.py"}, "status": "Success"},
               {"id": "t2", "name": "run_shell_command", "args": {"command": "swift test"}, "status": "Executing"}
             ]},
            {"id": "3", "timestamp": "\(isoNow())", "type": "info", "content": "quota note"}
          ]
        }
        """

        let record = GeminiLogParser.sessionRecord(fromChatData: Data(fixture.utf8))
        XCTAssertEqual(record?.sessionID, "abc-123")
        XCTAssertEqual(record?.messages.count, 3)
        XCTAssertEqual(record?.messages.map(\.role), [.user, .model, .other])
        XCTAssertEqual(record?.messages[0].text, "fix the bug")
        XCTAssertEqual(record?.messages[1].toolCalls, [
            GeminiToolCall(name: "read_file", detail: "/a.py", isTerminal: true),
            GeminiToolCall(name: "run_shell_command", detail: "swift test", isTerminal: false)
        ])
        XCTAssertEqual(record?.messages[1].model, "gemini-2.5-pro")
        XCTAssertNotNil(record?.lastUpdated)
        XCTAssertNotNil(record?.messages.first?.timestamp)
    }

    func testParserReadsCheckpointHistoryArray() {
        let fixture = """
        [
          {"role": "user", "parts": [{"text": "list files"}]},
          {"role": "model", "parts": [{"functionCall": {"name": "run_shell_command", "args": {"command": "ls"}}}]},
          {"role": "user", "parts": [{"functionResponse": {"name": "run_shell_command", "response": {"output": "a b"}}}]},
          {"role": "model", "parts": [{"text": "Two files."}]}
        ]
        """

        let record = GeminiLogParser.sessionRecord(fromChatData: Data(fixture.utf8))
        XCTAssertNil(record?.sessionID)
        // The functionResponse carrier must not read as a real user prompt.
        XCTAssertEqual(record?.messages.map(\.role), [.user, .model, .other, .model])
        XCTAssertEqual(record?.messages[1].toolCalls.map(\.name), ["run_shell_command"])
        XCTAssertEqual(record?.messages[3].text, "Two files.")
    }

    func testParserReadsPromptLogAndSkipsJunk() {
        let fixture = """
        [
          {"sessionId": "s-1", "messageId": 0, "type": "user", "message": "hello", "timestamp": "\(isoNow())"},
          {"sessionId": "s-1", "messageId": 1, "type": "user", "message": "   "},
          {"messageId": 2, "type": "user", "message": "no session"},
          {"sessionId": "s-2", "messageId": 0, "type": "user", "message": "second session"}
        ]
        """

        let entries = GeminiLogParser.promptEntries(fromLogsData: Data(fixture.utf8))
        XCTAssertEqual(entries.map(\.text), ["hello", "second session"])
        XCTAssertEqual(entries.map(\.sessionID), ["s-1", "s-2"])
        XCTAssertEqual(GeminiLogParser.promptEntries(fromLogsData: Data("not json".utf8)), [])
    }

    // MARK: - Watcher (chat recordings)

    @MainActor
    func testPollEmitsCatchUpThenOnlyChangedEvents() async throws {
        let root = try makeRootDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = try makeChatsFile(root: root, name: "session-2026-07-17T10-00-00-abc12345.json")

        try write(chatJSON(
            sessionID: "sess-1",
            messages: [
                userMessage("add tests", offset: -120),
                modelMessage(nil, offset: -5, toolCalls: [
                    toolCallJSON(name: "run_shell_command", command: "swift test", status: "Executing")
                ])
            ]
        ), to: file)

        let sink = EventSink()
        let watcher = GeminiSessionWatcher(rootDirectory: root) { sink.append($0) }

        await watcher.pollOnce()
        XCTAssertEqual(sink.events.map(\.kind), [
            .sessionStart(source: "gemini"),
            .userPrompt(prompt: "add tests"),
            .preTool(toolName: "Gemini", detail: "working…", toolUseID: nil, subagentLabel: nil)
        ])
        XCTAssertEqual(sink.events.first?.context.sessionID, "gemini-sess-1")
        XCTAssertEqual(sink.events.first?.context.agent, .gemini)
        XCTAssertTrue(sink.events.allSatisfy { $0.context.model == "gemini-2.5-pro" })
        // No cwd on disk — readable fallback so cards say "gemini · <title>".
        XCTAssertEqual(sink.events.first?.context.cwd, "gemini")

        // Nothing changed → nothing new emitted (fingerprint watermark).
        await watcher.pollOnce()
        XCTAssertEqual(sink.events.count, 3)

        // The recording is rewritten in place: the tool call finishes and
        // the final answer lands on the same trailing message.
        try write(chatJSON(
            sessionID: "sess-1",
            messages: [
                userMessage("add tests", offset: -120),
                modelMessage("Tests added.", offset: 0, toolCalls: [
                    toolCallJSON(name: "run_shell_command", command: "swift test", status: "Success")
                ])
            ]
        ), to: file)

        await watcher.pollOnce()
        XCTAssertEqual(sink.events.count, 4)
        XCTAssertEqual(sink.events.last?.kind, .stop(lastAssistantMessage: "Tests added."))

        // Next turn: a new user message and a fresh tool call stream in.
        try write(chatJSON(
            sessionID: "sess-1",
            messages: [
                userMessage("add tests", offset: -120),
                modelMessage("Tests added.", offset: -60, toolCalls: [
                    toolCallJSON(name: "run_shell_command", command: "swift test", status: "Success")
                ]),
                userMessage("now lint", offset: -2),
                modelMessage(nil, offset: 0, toolCalls: [
                    toolCallJSON(name: "run_shell_command", command: "swiftlint", status: "Executing")
                ], model: "gemini-3.1-pro-preview")
            ]
        ), to: file)

        await watcher.pollOnce()
        let kinds = sink.events.map(\.kind)
        XCTAssertEqual(kinds.count, 6)
        XCTAssertEqual(kinds[4], .userPrompt(prompt: "now lint"))
        XCTAssertEqual(kinds[5], .preTool(
            toolName: "run_shell_command", detail: "swiftlint", toolUseID: nil, subagentLabel: nil
        ))
        XCTAssertEqual(sink.events[5].context.model, "gemini-3.1-pro-preview")
    }

    @MainActor
    func testStaleRecordingIsTrackedSilentlyUntilNewActivity() async throws {
        let root = try makeRootDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = try makeChatsFile(root: root, name: "session-old.json")

        try write(chatJSON(
            sessionID: "sess-2",
            lastUpdatedOffset: -3 * 3600,
            messages: [
                userMessage("old prompt", offset: -3 * 3600),
                modelMessage("Old answer.", offset: -3 * 3600)
            ]
        ), to: file)

        let sink = EventSink()
        let watcher = GeminiSessionWatcher(rootDirectory: root) { sink.append($0) }

        await watcher.pollOnce()
        XCTAssertTrue(sink.events.isEmpty, "stale history must not surface a session")

        try write(chatJSON(
            sessionID: "sess-2",
            messages: [
                userMessage("old prompt", offset: -3 * 3600),
                modelMessage("Old answer.", offset: -3 * 3600),
                userMessage("back again", offset: 0)
            ]
        ), to: file)

        await watcher.pollOnce()
        XCTAssertEqual(sink.events.map(\.kind), [
            .sessionStart(source: "gemini"),
            .userPrompt(prompt: "back again")
        ])
        XCTAssertEqual(sink.events.first?.context.sessionID, "gemini-sess-2")
    }

    // MARK: - Watcher (logs.json fallback)

    @MainActor
    func testPromptLogFallbackEmitsPromptsAndSkipsRecordedSessions() async throws {
        let root = try makeRootDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let project = root.appendingPathComponent("hash-1", isDirectory: true)
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        let logs = project.appendingPathComponent("logs.json")

        // "covered" also has a chat recording — the richer stream wins.
        let chatFile = try makeChatsFile(root: root, name: "session-covered.json")
        try write(chatJSON(sessionID: "covered", messages: [userMessage("from recording", offset: -30)]), to: chatFile)

        try write("""
        [
          {"sessionId": "solo", "messageId": 0, "type": "user", "message": "prompt only", "timestamp": "\(isoNow(offset: -20))"}
        ]
        """, to: logs)

        let sink = EventSink()
        let watcher = GeminiSessionWatcher(rootDirectory: root) { sink.append($0) }

        await watcher.pollOnce()
        var kinds = sink.events.map(\.kind)
        XCTAssertEqual(kinds, [
            .sessionStart(source: "gemini"),
            .userPrompt(prompt: "from recording"),
            .sessionStart(source: "gemini"),
            .userPrompt(prompt: "prompt only")
        ])
        XCTAssertEqual(sink.events[2].context.sessionID, "gemini-solo")

        // Appended entries: covered session suppressed, solo emits prompt only.
        try write("""
        [
          {"sessionId": "solo", "messageId": 0, "type": "user", "message": "prompt only", "timestamp": "\(isoNow(offset: -20))"},
          {"sessionId": "covered", "messageId": 0, "type": "user", "message": "dup prompt", "timestamp": "\(isoNow())"},
          {"sessionId": "solo", "messageId": 1, "type": "user", "message": "again", "timestamp": "\(isoNow())"}
        ]
        """, to: logs)

        await watcher.pollOnce()
        kinds = sink.events.map(\.kind)
        XCTAssertEqual(kinds.count, 5)
        XCTAssertEqual(kinds.last, .userPrompt(prompt: "again"))
        XCTAssertEqual(sink.events.last?.context.sessionID, "gemini-solo")
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

    private func makeRootDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("gemini-watcher-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func makeChatsFile(root: URL, name: String) throws -> URL {
        let chats = root
            .appendingPathComponent("project-hash", isDirectory: true)
            .appendingPathComponent("chats", isDirectory: true)
        try FileManager.default.createDirectory(at: chats, withIntermediateDirectories: true)
        return chats.appendingPathComponent(name)
    }

    private func write(_ contents: String, to url: URL) throws {
        try Data(contents.utf8).write(to: url)
    }

    private func isoNow(offset: TimeInterval = 0) -> String {
        ISO8601DateFormatter().string(from: Date().addingTimeInterval(offset))
    }

    private func chatJSON(
        sessionID: String,
        lastUpdatedOffset: TimeInterval = 0,
        messages: [String]
    ) -> String {
        """
        {
          "sessionId": "\(sessionID)",
          "projectHash": "abc",
          "startTime": "\(isoNow(offset: -3600))",
          "lastUpdated": "\(isoNow(offset: lastUpdatedOffset))",
          "messages": [\(messages.joined(separator: ","))]
        }
        """
    }

    private func userMessage(_ text: String, offset: TimeInterval) -> String {
        #"{"id":"u","timestamp":"\#(isoNow(offset: offset))","type":"user","content":"\#(text)"}"#
    }

    private func modelMessage(
        _ text: String?,
        offset: TimeInterval,
        toolCalls: [String] = [],
        model: String = "gemini-2.5-pro"
    ) -> String {
        let content = text.map { #""content":"\#($0)","# } ?? ""
        return #"{"id":"m","timestamp":"\#(isoNow(offset: offset))","type":"gemini","model":"\#(model)",\#(content)"toolCalls":[\#(toolCalls.joined(separator: ","))]}"#
    }

    private func toolCallJSON(name: String, command: String, status: String) -> String {
        #"{"id":"t","name":"\#(name)","args":{"command":"\#(command)"},"status":"\#(status)"}"#
    }
}
