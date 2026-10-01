import XCTest
@testable import TokenIslandKit

@MainActor
final class HookEventHandlerTests: XCTestCase {
    private func request(_ id: String, tool: String = "Bash") -> SessionEvent {
        SessionEvent(context: SessionEventContext(sessionID: "same-session", agent: .claude),
                     kind: .permissionRequest(toolName: tool, detail: nil, toolUseID: id,
                                              preview: ToolCallPreview(kind: .generic(tool))))
    }

    func testNativeModeReleasesAlreadyParkedRequestsWithoutGrantingPermission() async {
        let store = SessionStore()
        let center = ApprovalCenter()
        let handler = HookEventHandler(sessionStore: store, approvalCenter: center)
        let event = request("native-pending")
        let reply = Task { await handler.handle(event) }
        for _ in 0..<100 where center.pending.isEmpty { await Task.yield() }
        XCTAssertEqual(center.pending.count, 1)
        center.useNativeApprovals = true
        let result = await reply.value
        XCTAssertNil(result)
        XCTAssertTrue(center.pending.isEmpty)
        XCTAssertEqual(store.sessions.first?.phase, .waitingApproval)
        XCTAssertEqual(store.sessions.first?.pendingApprovalSource, .terminalOnly)
    }

    func testResolvingOneRequestKeepsTheOtherApprovalAndItsPreview() async {
        let store = SessionStore()
        let center = ApprovalCenter()
        let handler = HookEventHandler(sessionStore: store, approvalCenter: center)
        let firstEvent = request("first")
        let first = Task { await handler.handle(firstEvent) }
        for _ in 0..<100 where center.pending.count < 1 { await Task.yield() }
        let secondEvent = request("second", tool: "Edit")
        let second = Task { await handler.handle(secondEvent) }
        for _ in 0..<100 where center.pending.count < 2 { await Task.yield() }
        XCTAssertEqual(center.pending.count, 2)
        center.approve(id: "first")
        _ = await first.value
        XCTAssertEqual(store.sessions.first?.phase, .waitingApproval)
        XCTAssertEqual(store.sessions.first?.pendingApprovalPreview, ToolCallPreview(kind: .generic("Edit")))
        center.deny(id: "second")
        _ = await second.value
        XCTAssertEqual(store.sessions.first?.phase, .working)
    }

    func testDisabledIntegrationDoesNotCreateSessionOrParkApproval() async {
        let store = SessionStore()
        let center = ApprovalCenter()
        let handler = HookEventHandler(sessionStore: store, approvalCenter: center, isEnabled: { _ in false })
        let result = await handler.handle(request("disabled"))
        XCTAssertNil(result)
        XCTAssertTrue(store.sessions.isEmpty)
        XCTAssertTrue(center.pending.isEmpty)
    }
}
