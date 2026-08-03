@testable import TokenIslandKit
import XCTest

final class SessionStoreTests: XCTestCase {
    @MainActor
    func testCollapsedStatusReportsErrorInsteadOfReady() async {
        let store = SessionStore()
        let context = SessionEventContext(
            sessionID: "error-status-regression",
            agent: .codex,
            cwd: "/tmp/demo"
        )

        store.apply(
            SessionEvent(
                context: context,
                kind: .stopFailure(message: "Rollout failed")
            )
        )

        XCTAssertEqual(store.stripStatusWord, "Error")
    }

    @MainActor
    func testClearedStructuredApprovalPreviewDoesNotLeakIntoLaterNotification() async {
        let store = SessionStore()
        let context = SessionEventContext(
            sessionID: "approval-preview-regression",
            agent: .claude,
            cwd: "/tmp/demo"
        )
        let preview = ToolCallPreview(kind: .bashCommand("swift test"))

        store.apply(
            SessionEvent(
                context: context,
                kind: .permissionRequest(
                    toolName: "Bash",
                    detail: "swift test",
                    toolUseID: "tool-1",
                    preview: preview
                )
            )
        )
        XCTAssertEqual(
            store.session(withID: context.sessionID)?.pendingApprovalPreview,
            preview,
            "The structured permission should initially expose its own preview"
        )

        store.clearApprovalPending(sessionID: context.sessionID)
        store.apply(
            SessionEvent(
                context: context,
                kind: .notification(
                    message: "Claude needs permission to continue",
                    category: .permission
                )
            )
        )

        let laterPermission = store.session(withID: context.sessionID)
        XCTAssertEqual(laterPermission?.phase, .waitingApproval)
        XCTAssertEqual(
            laterPermission?.pendingApprovalMessage,
            "Claude needs permission to continue"
        )
        XCTAssertNil(
            laterPermission?.pendingApprovalPreview,
            "A notification-based permission must not display a preview from an already resolved tool call"
        )
    }

    @MainActor
    func testDetailedStripShowsTheSessionTitle() async {
        let store = SessionStore()
        let context = SessionEventContext(sessionID: "strip-label", agent: .claude, cwd: "/tmp/demo")

        store.apply(SessionEvent(context: context, kind: .sessionStart(source: nil)))
        XCTAssertEqual(store.stripDetailLabel, store.stripStatusWord, "no title yet — fall back to the status word")

        store.apply(SessionEvent(context: context, kind: .userPrompt(prompt: "fix auth bug")))
        XCTAssertEqual(store.stripDetailLabel, "fix auth bug", "the pill says what the agent is working on")
    }

    @MainActor
    func testDetailedStripLabelPrefersTheSessionNeedingAttention() async {
        let store = SessionStore()
        let working = SessionEventContext(sessionID: "working", agent: .claude, cwd: "/tmp/a")
        let asking = SessionEventContext(sessionID: "asking", agent: .claude, cwd: "/tmp/b")

        store.apply(SessionEvent(context: working, kind: .userPrompt(prompt: "refactor the parser")))
        store.apply(SessionEvent(context: asking, kind: .userPrompt(prompt: "add caching")))
        store.apply(SessionEvent(context: asking, kind: .question(text: "Which strategy?", options: ["Redis"])))

        XCTAssertEqual(store.stripDetailLabel, "add caching", "the session that needs you owns the strip")
    }
}
