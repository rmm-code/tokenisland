import XCTest
@testable import TokenIslandKit

/// End-to-end pipeline test: real HTTP POSTs (as the installed curl hooks
/// would send) through HookServer into SessionStore — no app launch, no
/// settings.json writes.
@MainActor
final class HookServerTests: XCTestCase {
    private static let port: UInt16 = 49_733

    func testSeedSequenceDrivesSessionLifecycle() async throws {
        let store = SessionStore()
        let markerService = TitleMarkerService()

        let server = HookServer(port: Self.port) { event in
            await MainActor.run { () -> String? in
                store.apply(event)
                guard let session = store.session(withID: event.context.sessionID) else { return nil }
                guard let payload = markerService.responsePayload(for: event, session: session) else { return nil }
                return HookResponses.serialize(payload)
            }
        }
        try server.start()
        defer { server.stop() }
        try await Task.sleep(for: .milliseconds(150))

        // Health check.
        let healthURL = URL(string: "http://127.0.0.1:\(Self.port)/health")!
        let (healthData, healthResponse) = try await URLSession.shared.data(from: healthURL)
        XCTAssertEqual((healthResponse as? HTTPURLResponse)?.statusCode, 200)
        XCTAssertTrue(String(data: healthData, encoding: .utf8)?.contains("ok") == true)

        // SessionStart → idle (the CLI just opened), and the response carries
        // the title marker.
        let startBody: [String: Any] = [
            "session_id": "it-1",
            "hook_event_name": "SessionStart",
            "source": "startup",
            "cwd": "/tmp/demo-app",
            "transcript_path": "/tmp/none.jsonl"
        ]
        let startReply = try await post(startBody, headers: ["X-TI-Term": "Apple_Terminal", "X-TI-TTY": "/dev/ttys002"])
        XCTAssertTrue(startReply.contains("terminalSequence"), "SessionStart should stamp the title marker")
        XCTAssertTrue(startReply.contains("claude — demo-app"))

        await drainMainQueue()
        XCTAssertEqual(store.sessions.count, 1)
        XCTAssertEqual(store.sessions.first?.phase, .idle)
        XCTAssertEqual(store.sessions.first?.terminalHint?.termProgram, "Apple_Terminal")

        // Typing a prompt is what starts the work.
        _ = try await post([
            "session_id": "it-1",
            "hook_event_name": "UserPromptSubmit",
            "prompt": "ship the fix"
        ])
        await drainMainQueue()
        XCTAssertEqual(store.sessions.first?.phase, .working)

        // Stop with a final message → ready + TLDR.
        _ = try await post([
            "session_id": "it-1",
            "hook_event_name": "Stop",
            "last_assistant_message": "Done. Shipped the fix."
        ])
        await drainMainQueue()
        XCTAssertEqual(store.sessions.first?.phase, .ready)
        XCTAssertEqual(store.sessions.first?.completionTLDR, "Done. Shipped the fix.")

        // Malformed payload must not crash and must stay fail-open (HTTP 200).
        var request = URLRequest(url: URL(string: "http://127.0.0.1:\(Self.port)/hook/claude")!)
        request.httpMethod = "POST"
        request.httpBody = Data("not json".utf8)
        let (_, badResponse) = try await URLSession.shared.data(for: request)
        XCTAssertEqual((badResponse as? HTTPURLResponse)?.statusCode, 200)
    }

    private func post(_ body: [String: Any], headers: [String: String] = [:]) async throws -> String {
        var request = URLRequest(url: URL(string: "http://127.0.0.1:\(Self.port)/hook/claude")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
        return String(data: data, encoding: .utf8) ?? ""
    }

    /// Lets MainActor tasks scheduled by the server settle.
    private func drainMainQueue() async {
        for _ in 0..<3 {
            await Task.yield()
            try? await Task.sleep(for: .milliseconds(40))
        }
    }
}
