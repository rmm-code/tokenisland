import XCTest
@testable import TokenIslandKit

@MainActor
final class DialectHookRoundTripTests: XCTestCase {
    func testCursorObservationalHooksReturnValidNonblockingOutput() async throws {
        let port = UInt16.random(in: 53_000...54_000)
        let store = SessionStore()
        let center = ApprovalCenter()
        let handler = HookEventHandler(sessionStore: store, approvalCenter: center)
        let server = HookServer(port: port) { await handler.handle($0) }
        try server.start()
        defer { server.stop() }
        try await Task.sleep(for: .milliseconds(150))
        for (event, key) in [("preToolUse", "permission"), ("subagentStart", "permission"), ("beforeSubmitPrompt", "continue")] {
            let body: [String: Any] = ["hook_event_name": event, "conversation_id": "cursor-test", "tool_name": "Read"]
            let (data, status) = try await Self.post(port: port, source: "cursor", body: JSONSerialization.data(withJSONObject: body))
            XCTAssertEqual(status, 200)
            let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
            if key == "permission" { XCTAssertEqual(json[key] as? String, "allow") }
            else { XCTAssertEqual(json[key] as? Bool, true) }
            XCTAssertNil(json["terminalSequence"])
        }
    }

    func testCursorToolMonitoringDoesNotAddANativeApprovalWait() async throws {
        let port = UInt16.random(in: 54_001...55_000)
        let center = ApprovalCenter()
        center.useNativeApprovals = true
        let handler = HookEventHandler(sessionStore: SessionStore(), approvalCenter: center)
        let server = HookServer(port: port) { await handler.handle($0) }
        try server.start()
        defer { server.stop() }
        try await Task.sleep(for: .milliseconds(150))
        let body = Data(#"{"hook_event_name":"beforeShellExecution","conversation_id":"native","command":"echo test"}"#.utf8)
        let (reply, status) = try await Self.post(port: port, source: "cursor", body: body)
        XCTAssertEqual(status, 200)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: reply) as? [String: Any])
        XCTAssertEqual(json["permission"] as? String, "allow")
        XCTAssertTrue(center.pending.isEmpty)
    }

    func testCursorAndGeminiToolGatesMonitorWithoutParkingOrGrantingNativeApprovals() async throws {
        for (source, body) in [
            ("cursor", #"{"hook_event_name":"beforeShellExecution","conversation_id":"rt","command":"echo test"}"#),
            ("gemini", #"{"hook_event_name":"BeforeTool","session_id":"rt","tool_name":"run_shell_command","tool_input":{"command":"echo test"}}"#)
        ] {
            let port = UInt16.random(in: 55_001...56_000)
            let store = SessionStore()
            let center = ApprovalCenter()
            center.holdTimeoutSeconds = 2
            let handler = HookEventHandler(sessionStore: store, approvalCenter: center)
            let server = HookServer(port: port) { await handler.handle($0) }
            try server.start()
            defer { server.stop() }
            try await Task.sleep(for: .milliseconds(150))
            let data = Data(body.utf8)
            let (reply, status) = try await Self.post(port: port, source: source, body: data)
            XCTAssertEqual(status, 200)
            let json = try XCTUnwrap(JSONSerialization.jsonObject(with: reply) as? [String: Any])
            if source == "cursor" { XCTAssertEqual(json["permission"] as? String, "allow") }
            else { XCTAssertNil(json["decision"]) }
            XCTAssertTrue(center.pending.isEmpty)
            XCTAssertEqual(store.sessions.first?.phase, .working)
        }
    }

    private nonisolated static func post(port: UInt16, source: String, body: Data) async throws -> (Data, Int) {
        var request = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/hook/\(source)")!)
        request.httpMethod = "POST"
        request.httpBody = body
        request.timeoutInterval = 4
        let (data, response) = try await URLSession.shared.data(for: request)
        return (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
    }
}
