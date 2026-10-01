import XCTest
@testable import TokenIslandKit

@MainActor
final class ApprovalCenterTests: XCTestCase {
    private func permissionEvent(
        tool: String,
        sessionID: String = "s1",
        preview: ToolCallPreview? = nil
    ) -> SessionEvent {
        SessionEvent(
            context: SessionEventContext(
                sessionID: sessionID,
                agent: .claude,
                permissionMode: "default"
            ),
            kind: .permissionRequest(toolName: tool, detail: "npm test", toolUseID: "t1", preview: preview)
        )
    }

    private func preToolEvent(tool: String, sessionID: String = "s1") -> SessionEvent {
        SessionEvent(
            context: SessionEventContext(sessionID: sessionID, agent: .claude),
            kind: .preTool(toolName: tool, detail: nil, toolUseID: "t1", subagentLabel: nil)
        )
    }

    func testHoldsPermissionRequests() {
        let center = ApprovalCenter()
        XCTAssertTrue(center.shouldHold(event: permissionEvent(tool: "Bash")))
        XCTAssertTrue(center.shouldHold(event: permissionEvent(tool: "Edit")))
    }

    func testNeverHoldsPlainPreToolTelemetry() {
        let center = ApprovalCenter()
        for tool in ["Bash", "Edit", "Read"] {
            XCTAssertFalse(center.shouldHold(event: preToolEvent(tool: tool)), "\(tool) PreToolUse must pass through")
        }
    }

    func testNativeModeDisablesHolding() {
        let center = ApprovalCenter()
        center.useNativeApprovals = true
        XCTAssertFalse(center.shouldHold(event: permissionEvent(tool: "Bash")))
    }

    func testRegisterCarriesToolPreview() {
        let center = ApprovalCenter()
        let preview = ToolCallPreview(kind: .bashCommand("npm test"))
        _ = center.register(event: permissionEvent(tool: "Bash", preview: preview))
        XCTAssertEqual(center.pending.first?.preview, preview)
        XCTAssertEqual(center.pendingApproval(forSessionID: "s1")?.preview, preview)
    }

    func testApproveResolvesWait() async {
        let center = ApprovalCenter()
        let id = center.register(event: permissionEvent(tool: "Bash"))
        XCTAssertEqual(center.pending.count, 1)

        Task { @MainActor in
            center.approve(id: id)
        }
        let decision = await center.wait(id: id)
        XCTAssertEqual(decision, .allow)
        XCTAssertTrue(center.pending.isEmpty)
    }

    func testAlwaysAllowSkipsFutureHolds() async {
        let center = ApprovalCenter()
        let id = center.register(event: permissionEvent(tool: "Bash"))
        Task { @MainActor in
            center.alwaysAllow(id: id)
        }
        _ = await center.wait(id: id)
        XCTAssertTrue(center.shouldAutoAllow(event: permissionEvent(tool: "Bash")), "always-allowed tool auto-approves")
        XCTAssertFalse(center.shouldAutoAllow(event: permissionEvent(tool: "Edit")), "other tools still ask")
    }

    func testTimeoutFailsOpen() async {
        let center = ApprovalCenter()
        center.holdTimeoutSeconds = 0.05
        let id = center.register(event: permissionEvent(tool: "Bash"))
        let decision = await center.wait(id: id)
        XCTAssertEqual(decision, .passthrough)
    }

    func testPermissionResponsePayloads() {
        XCTAssertNil(HookResponses.permission(.passthrough, reason: "x"))
        let allow = HookResponses.permission(.allow, reason: "notch")
        XCTAssertNotNil(allow)
        XCTAssertTrue(allow?.contains("\"behavior\":\"allow\"") == true || allow?.contains("\"behavior\" : \"allow\"") == true)
    }

    /// The card is clickable from the moment `register` publishes it, which is
    /// before `wait` installs its continuation. A verdict pressed in that gap
    /// used to be discarded, leaving the CLI parked to the full timeout — the
    /// "I pressed Allow and nothing happened" report.
    @MainActor
    func testVerdictPressedBeforeWaitIsNotLost() async {
        let center = ApprovalCenter()
        let id = center.register(event: Self.permissionEvent(toolUseID: "race-1"))

        // Verdict lands first, then the hook gets around to waiting.
        center.approve(id: id)
        let decision = await center.wait(id: id)

        XCTAssertEqual(decision, .allow)
        XCTAssertTrue(center.pending.isEmpty)
    }

    /// Re-registering the same tool_use_id used to overwrite the continuation
    /// of the in-flight request, hanging that CLI call until its own timeout.
    @MainActor
    func testRepeatRegistrationReleasesThePreviousRequest() async {
        let center = ApprovalCenter()
        // Deliberately long: with the orphan bug the first caller is only
        // released by its own timeout, so a generous timeout is what makes
        // this test meaningful rather than accidentally passing.
        center.holdTimeoutSeconds = 30
        let id = center.register(event: Self.permissionEvent(toolUseID: "dup-1"))

        let first = Task { await center.wait(id: id) }
        await Task.yield()

        // Same id arrives again; the first caller must be released, not orphaned.
        let started = Date()
        _ = center.register(event: Self.permissionEvent(toolUseID: "dup-1"))
        let firstDecision = await first.value
        let elapsed = Date().timeIntervalSince(started)

        XCTAssertEqual(firstDecision, .passthrough)
        XCTAssertLessThan(elapsed, 2, "first request was orphaned until its timeout")
    }

    private static func permissionEvent(toolUseID: String) -> SessionEvent {
        SessionEvent(
            context: SessionEventContext(sessionID: "s1", agent: .claude),
            kind: .permissionRequest(
                toolName: "Edit",
                detail: "src/x.ts",
                toolUseID: toolUseID,
                preview: nil
            )
        )
    }
}
