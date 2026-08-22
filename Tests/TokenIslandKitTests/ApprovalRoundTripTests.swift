import XCTest
@testable import TokenIslandKit

/// The approval round trip, end to end over real HTTP: a parked
/// `PermissionRequest` arrives exactly as the installed curl hook sends it, a
/// verdict is given the same way the notch card gives it, and the assertion is
/// on the HTTP body the CLI actually reads.
///
/// This exists because "I pressed Allow and nothing happened" could not be
/// reproduced by hand — every manual attempt hit the 55s timeout before the
/// press landed. The sink below mirrors `AppEnvironment`'s wiring so the whole
/// chain (park → verdict → serialize → respond) is covered without a UI.
@MainActor
final class ApprovalRoundTripTests: XCTestCase {
    private nonisolated static let port: UInt16 = 49_741

    private func makeServer(
        store: SessionStore,
        center: ApprovalCenter
    ) -> HookServer {
        HookServer(port: Self.port) { event in
            enum Route { case none, hold(String), autoAllow }
            let route = await MainActor.run { () -> Route in
                store.apply(event)
                guard case .permissionRequest = event.kind else { return .none }
                if center.shouldAutoAllow(event: event) {
                    store.clearApprovalPending(sessionID: event.context.sessionID)
                    return .autoAllow
                }
                guard center.shouldHold(event: event) else { return .none }
                return .hold(center.register(event: event))
            }
            switch route {
            case .autoAllow:
                return HookResponses.permission(.allow, reason: "Always allowed from the notch")
            case .hold(let id):
                let decision = await center.wait(id: id)
                await MainActor.run { store.clearApprovalPending(sessionID: event.context.sessionID) }
                return HookResponses.permission(decision, reason: "Decided from the notch")
            case .none:
                return nil
            }
        }
    }

    /// Built as `Data` and posted from a nonisolated helper: under Swift 6 a
    /// `[String: Any]` crossing into an `async let` is a data-race error.
    private nonisolated static func permissionBody(
        toolUseID: String,
        sessionID: String = "rt-1"
    ) -> Data {
        let body: [String: Any] = [
            "session_id": sessionID,
            "hook_event_name": "PermissionRequest",
            "tool_name": "Edit",
            "tool_use_id": toolUseID,
            "cwd": "/tmp/demo-app",
            "tool_input": [
                "file_path": "/tmp/demo-app/src/webhooks/stripe.ts",
                "old_string": "await handleEvent(event)",
                "new_string": "await withRetry(3, () => handleEvent(event))"
            ]
        ]
        return try! JSONSerialization.data(withJSONObject: body)
    }

    private nonisolated static func post(_ body: Data) async throws -> String {
        var request = URLRequest(url: URL(string: "http://127.0.0.1:\(Self.port)/hook/claude")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        let (data, response) = try await URLSession.shared.data(for: request)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
        return String(data: data, encoding: .utf8) ?? ""
    }

    /// Waits for the card to exist, then answers it the way the card does.
    private func answer(
        _ center: ApprovalCenter,
        sessionID: String = "rt-1",
        _ verdict: (ApprovalCenter, String) -> Void
    ) async {
        for _ in 0..<80 where center.pendingApproval(forSessionID: sessionID) == nil {
            try? await Task.sleep(for: .milliseconds(25))
        }
        guard let approval = center.pendingApproval(forSessionID: sessionID) else {
            return XCTFail("no approval card was ever registered")
        }
        verdict(center, approval.id)
    }

    func testAllowReachesTheCLIAsAPermissionDecision() async throws {
        let store = SessionStore()
        let center = ApprovalCenter()
        let server = makeServer(store: store, center: center)
        try server.start()
        defer { server.stop() }
        try await Task.sleep(for: .milliseconds(150))

        async let reply = Self.post(Self.permissionBody(toolUseID: "rt-allow"))
        await answer(center) { $0.approve(id: $1) }

        let body = try await reply
        XCTAssertTrue(body.contains("\"permissionDecision\":\"allow\""), "body was: \(body)")
        XCTAssertTrue(body.contains("\"hookEventName\":\"PermissionRequest\""), "body was: \(body)")
        // The phase must not be left stuck on waitingApproval after a verdict.
        XCTAssertEqual(store.sessions.first?.phase, .working)
    }

    func testDenyReachesTheCLI() async throws {
        let store = SessionStore()
        let center = ApprovalCenter()
        let server = makeServer(store: store, center: center)
        try server.start()
        defer { server.stop() }
        try await Task.sleep(for: .milliseconds(150))

        async let reply = Self.post(Self.permissionBody(toolUseID: "rt-deny"))
        await answer(center) { $0.deny(id: $1) }

        let body = try await reply
        XCTAssertTrue(body.contains("\"permissionDecision\":\"deny\""), "body was: \(body)")
    }

    /// Always-Allow has to survive into the NEXT request, with no card at all.
    func testAlwaysAllowAutoAnswersTheFollowingRequest() async throws {
        let store = SessionStore()
        let center = ApprovalCenter()
        let server = makeServer(store: store, center: center)
        try server.start()
        defer { server.stop() }
        try await Task.sleep(for: .milliseconds(150))

        async let first = Self.post(Self.permissionBody(toolUseID: "rt-always-1"))
        await answer(center) { $0.alwaysAllow(id: $1) }
        let firstBody = try await first
        XCTAssertTrue(firstBody.contains("\"permissionDecision\":\"allow\""), "body was: \(firstBody)")

        // Second one must answer itself immediately — no verdict given here.
        let second = try await Self.post(Self.permissionBody(toolUseID: "rt-always-2"))
        XCTAssertTrue(second.contains("\"permissionDecision\":\"allow\""), "body was: \(second)")
        XCTAssertTrue(center.pending.isEmpty, "auto-allow must not leave a card behind")
    }

    /// Fail-open: an unanswered request returns a body with no directive, which
    /// is what lets the CLI fall back to its own prompt.
    func testTimeoutFailsOpenWithNoDecision() async throws {
        let store = SessionStore()
        let center = ApprovalCenter()
        center.holdTimeoutSeconds = 0.4
        let server = makeServer(store: store, center: center)
        try server.start()
        defer { server.stop() }
        try await Task.sleep(for: .milliseconds(150))

        let body = try await Self.post(Self.permissionBody(toolUseID: "rt-timeout"))
        XCTAssertFalse(body.contains("permissionDecision"), "body was: \(body)")
        XCTAssertEqual(body, "{\"ok\":true}")
    }

    /// The race the audit found: a verdict pressed before `wait` installs its
    /// continuation must still reach the CLI, not be swallowed to the timeout.
    func testVerdictRacingTheParkStillReachesTheCLI() async throws {
        let store = SessionStore()
        let center = ApprovalCenter()
        center.holdTimeoutSeconds = 20
        let server = makeServer(store: store, center: center)
        try server.start()
        defer { server.stop() }
        try await Task.sleep(for: .milliseconds(150))

        // Approve the instant the card appears — as close to the register/wait
        // boundary as the harness can get.
        async let reply = Self.post(Self.permissionBody(toolUseID: "rt-race"))
        await answer(center) { $0.approve(id: $1) }

        let started = Date()
        let body = try await reply
        XCTAssertTrue(body.contains("\"permissionDecision\":\"allow\""), "body was: \(body)")
        XCTAssertLessThan(Date().timeIntervalSince(started), 2, "verdict was lost and only the timeout released it")
    }
}
