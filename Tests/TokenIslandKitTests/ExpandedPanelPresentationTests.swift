import Foundation
import XCTest
@testable import TokenIslandKit

final class ExpandedPanelPresentationTests: XCTestCase {
    func testAttentionAndWorkingSessionsStayAboveFocusedCompletion() {
        let attention = session(id: "attention", phase: .question, lastEventAt: 100)
        let working = session(id: "working", phase: .working, lastEventAt: 200)
        let completed = session(id: "completed", phase: .ready, lastEventAt: 300)

        let ordered = SessionPanelPresentation.orderedSessions(
            [completed, working, attention],
            focusedSessionID: completed.id
        )

        XCTAssertEqual(ordered.map(\.id), [attention.id, working.id, completed.id])
    }

    func testRecencyBreaksTiesWithinPresentationPriority() {
        let older = session(id: "older", phase: .working, lastEventAt: 100)
        let newer = session(id: "newer", phase: .working, lastEventAt: 200)

        let ordered = SessionPanelPresentation.orderedSessions(
            [older, newer],
            focusedSessionID: older.id
        )

        XCTAssertEqual(ordered.map(\.id), [newer.id, older.id])
    }

    func testInitialPresentationShowsTwoSessions() {
        let sessions = [
            session(id: "one", phase: .working, lastEventAt: 300),
            session(id: "two", phase: .working, lastEventAt: 200),
            session(id: "three", phase: .ready, lastEventAt: 100)
        ]

        let visible = SessionPanelPresentation.visibleSessions(
            from: sessions,
            showAll: false
        )

        XCTAssertEqual(SessionPanelPresentation.initialVisibleCount, 2)
        XCTAssertEqual(visible.map(\.id), ["one", "two"])
    }

    func testShowMoreLabelReportsHiddenCountWithCorrectPluralization() {
        XCTAssertEqual(
            SessionPanelPresentation.showMoreLabel(hiddenCount: 1),
            "Show 1 more session"
        )
        XCTAssertEqual(
            SessionPanelPresentation.showMoreLabel(hiddenCount: 3),
            "Show 3 more sessions"
        )
        XCTAssertEqual(
            SessionPanelPresentation.hiddenCount(totalCount: 3, visibleCount: 2),
            1
        )
    }

    func testFullPanelCompletionStartsCollapsed() {
        XCTAssertFalse(SessionPanelPresentation.fullPanelCompletionInitiallyExpanded)
    }

    func testCompletedResponseHasExplicitDisclosureControl() throws {
        let source = try sourceFile(
            "Sources/TokenIslandKit/Features/NotchUI/CompletionCardView.swift"
        )

        XCTAssertTrue(
            source.contains("isExpanded ? \"chevron.up\" : \"chevron.down\"")
                && source.contains("Button"),
            "A completed response must expose an explicit expand/collapse control"
        )
    }

    func testPinnedExpandedPanelDismissalClearsPinBeforeCollapsing() throws {
        let interactionSource = try sourceFile(
            "Sources/TokenIslandKit/Core/Windowing/NotchInteractionController.swift"
        )
        let notchSource = try sourceFile(
            "Sources/TokenIslandKit/Features/NotchUI/TokenIslandNotchView.swift"
        )

        XCTAssertTrue(interactionSource.contains("func handleCollapse()"))
        XCTAssertTrue(interactionSource.contains("$0.pinExpandedNotch = false"))
        XCTAssertTrue(interactionSource.contains("stateMachine.collapse()"))
        XCTAssertTrue(
            notchSource.contains("onCollapse: interactionController.handleCollapse"),
            "The visible close button must unpin the panel before collapsing it"
        )
    }

    private func session(
        id: String,
        phase: SessionPhase,
        lastEventAt: TimeInterval
    ) -> AgentSession {
        AgentSession(
            id: id,
            agent: .codex,
            projectPath: "/tmp/project",
            title: id,
            lastUserPrompt: "Prompt",
            completionTLDR: phase == .ready ? "Done" : nil,
            completionText: phase == .ready ? "Completed response" : nil,
            model: nil,
            phase: phase,
            activity: nil,
            pendingApprovalMessage: nil,
            pendingQuestionMessage: nil,
            terminalHint: nil,
            transcriptPath: nil,
            startedAt: Date(timeIntervalSince1970: lastEventAt - 10),
            lastEventAt: Date(timeIntervalSince1970: lastEventAt),
            endedAt: nil
        )
    }

    private func sourceFile(_ relativePath: String) throws -> String {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(
            contentsOf: repositoryRoot.appendingPathComponent(relativePath),
            encoding: .utf8
        )
    }
}
