import XCTest
@testable import TokenIslandKit

/// Subagent inner tool calls arrive with no marker tying them to their parent,
/// so what an agent is doing has to come from its own transcript. Fixtures here
/// mirror the real on-disk shape:
///   <session>.jsonl
///   <session>/subagents/agent-<id>.jsonl + agent-<id>.meta.json
final class SubagentActivityTests: XCTestCase {
    private var root: URL!
    private var sessionTranscript: String!

    override func setUpWithError() throws {
        root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("subagent-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        sessionTranscript = root.appendingPathComponent("session-1.jsonl").path
        try "{}".write(toFile: sessionTranscript, atomically: true, encoding: .utf8)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func writeSubagent(
        agentID: String,
        toolUseID: String,
        type: String,
        description: String,
        lines: [String]
    ) throws {
        let directory = root
            .appendingPathComponent("session-1", isDirectory: true)
            .appendingPathComponent("subagents", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let meta = #"{"agentType":"\#(type)","description":"\#(description)","toolUseId":"\#(toolUseID)","spawnDepth":1}"#
        try meta.write(
            to: directory.appendingPathComponent("agent-\(agentID).meta.json"),
            atomically: true,
            encoding: .utf8
        )
        try lines.joined(separator: "\n").write(
            to: directory.appendingPathComponent("agent-\(agentID).jsonl"),
            atomically: true,
            encoding: .utf8
        )
    }

    private func toolUseLine(_ name: String, _ input: String) -> String {
        #"{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"t1","name":"\#(name)","input":\#(input)}]}}"#
    }

    func testReadsLabelAndCurrentToolCall() throws {
        try writeSubagent(
            agentID: "a728691b0e0960cd7",
            toolUseID: "toolu_01MH",
            type: "general-purpose",
            description: "Review notch reveal fix",
            lines: [
                toolUseLine("Read", #"{"file_path":"/Users/dev/app/Sources/DisplaySettingsPane.swift"}"#),
                toolUseLine("Grep", #"{"pattern":"handleRequest"}"#)
            ]
        )

        let activities = SubagentActivityReader.read(sessionTranscriptPath: sessionTranscript)
        let activity = try XCTUnwrap(activities.first)
        XCTAssertEqual(activity.toolUseID, "toolu_01MH", "rows are keyed by the spawning tool-use id")
        XCTAssertEqual(activity.agentID, "a728691b0e0960cd7", "the id SubagentStop will report")
        XCTAssertEqual(activity.label, "General-Purpose (Review notch reveal fix)")
        XCTAssertEqual(activity.detail, "Grep: handleRequest", "the newest tool call wins")
    }

    func testFileToolsShowJustTheFileName() throws {
        try writeSubagent(
            agentID: "agent-b", toolUseID: "toolu_02", type: "explore", description: "Search API",
            lines: [toolUseLine("Read", #"{"file_path":"/Users/dev/app/Sources/Core/SessionStore.swift"}"#)]
        )
        let activity = try XCTUnwrap(SubagentActivityReader.read(sessionTranscriptPath: sessionTranscript).first)
        XCTAssertEqual(activity.detail, "Read: SessionStore.swift")
    }

    func testEveryRunningAgentIsReported() throws {
        try writeSubagent(agentID: "a1", toolUseID: "t1", type: "explore", description: "one",
                          lines: [toolUseLine("Bash", #"{"command":"swift test"}"#)])
        try writeSubagent(agentID: "a2", toolUseID: "t2", type: "explore", description: "two",
                          lines: [toolUseLine("Bash", #"{"command":"swift build"}"#)])

        let activities = SubagentActivityReader.read(sessionTranscriptPath: sessionTranscript)
        XCTAssertEqual(Set(activities.map(\.toolUseID)), ["t1", "t2"])
    }

    func testSessionWithoutSubagentsReadsNothing() {
        XCTAssertTrue(SubagentActivityReader.read(sessionTranscriptPath: sessionTranscript).isEmpty)
        XCTAssertTrue(SubagentActivityReader.read(sessionTranscriptPath: "/nope/missing.jsonl").isEmpty)
    }

    @MainActor
    func testStoreMergesActivityIntoRunningRowsOnly() {
        let store = SessionStore()
        let context = SessionEventContext(
            sessionID: "s1", agent: .claude, cwd: "/tmp/app", transcriptPath: sessionTranscript
        )
        store.apply(SessionEvent(
            context: context,
            kind: .preTool(toolName: "Agent", detail: nil, toolUseID: "t1", subagentLabel: "Explore (one)")
        ))
        store.apply(SessionEvent(
            context: context,
            kind: .preTool(toolName: "Agent", detail: nil, toolUseID: "t2", subagentLabel: "Explore (two)")
        ))
        store.apply(SessionEvent(context: context, kind: .postTool(toolName: "Agent", toolUseID: "t2")))

        store.applySubagentActivity(sessionID: "s1", activities: [
            SubagentActivity(toolUseID: "t1", agentID: "a1", label: "Explore (one)", detail: "Grep: handleRequest"),
            SubagentActivity(toolUseID: "t2", agentID: "a2", label: "Explore (two)", detail: "Bash: swift test")
        ])

        let subagents = store.session(withID: "s1")?.subagents ?? []
        XCTAssertEqual(subagents.first { $0.id == "t1" }?.detail, "Grep: handleRequest")
        XCTAssertEqual(subagents.first { $0.id == "t1" }?.agentID, "a1")
        XCTAssertNil(
            subagents.first { $0.id == "t2" }?.detail,
            "a finished agent must not keep showing a live tool call"
        )
    }
}
