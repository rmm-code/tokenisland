import XCTest
@testable import TokenIslandKit

@MainActor
final class NotchStateMachineTests: XCTestCase {
    func testInitialStateIsCollapsed() {
        let stateMachine = TokenIslandStateMachine()
        XCTAssertEqual(stateMachine.state, .collapsed)
    }

    func testHoverPeekOnlyFromCollapsed() {
        let stateMachine = TokenIslandStateMachine()
        stateMachine.showHoverPeek()
        XCTAssertEqual(stateMachine.state, .hoverPeek)

        stateMachine.expand()
        stateMachine.showHoverPeek()
        XCTAssertEqual(stateMachine.state, .expanded, "hover must not demote the expanded panel")
    }

    func testToggleExpandedRoundTrip() {
        let stateMachine = TokenIslandStateMachine()
        stateMachine.toggleExpanded()
        XCTAssertEqual(stateMachine.state, .expanded)
        stateMachine.toggleExpanded()
        XCTAssertEqual(stateMachine.state, .collapsed)
    }

    func testRevealDoesNotStealExpandedPanel() {
        let stateMachine = TokenIslandStateMachine()
        stateMachine.expand()
        stateMachine.showReveal(.completion, sessionID: "s1")
        XCTAssertEqual(stateMachine.state, .expanded)
    }

    func testCompletionRevealShowsAndFinishes() {
        let stateMachine = TokenIslandStateMachine()
        stateMachine.reconcile(settings: .defaults, errorMessage: nil)
        stateMachine.showReveal(.completion, sessionID: "s1")
        XCTAssertEqual(stateMachine.state, .reveal(.completion, sessionID: "s1"))

        stateMachine.finishReveal()
        XCTAssertEqual(stateMachine.state, .collapsed)
    }

    func testAttentionRevealClearsWhenSessionResolves() {
        let stateMachine = TokenIslandStateMachine()
        stateMachine.showReveal(.attention, sessionID: "s1")

        var session = AgentSession(
            id: "s1",
            agent: .claude,
            projectPath: "/tmp/app",
            title: nil,
            lastUserPrompt: nil,
            completionTLDR: nil,
            completionText: nil,
            model: nil,
            phase: .waitingApproval,
            activity: nil,
            pendingApprovalMessage: "Needs permission",
            pendingQuestionMessage: nil,
            terminalHint: nil,
            transcriptPath: nil,
            startedAt: .now,
            lastEventAt: .now,
            endedAt: nil
        )
        stateMachine.reconcileReveal(sessions: [session])
        XCTAssertEqual(stateMachine.state, .reveal(.attention, sessionID: "s1"), "unresolved approval keeps the reveal")

        session.phase = .working
        stateMachine.reconcileReveal(sessions: [session])
        XCTAssertEqual(stateMachine.state, .collapsed, "resolved approval collapses the reveal")
    }

    func testErrorStateFromReconcile() {
        let stateMachine = TokenIslandStateMachine()
        var settings = AppSettings.defaults
        settings.showErrorAlerts = true
        stateMachine.reconcile(settings: settings, errorMessage: "boom")
        XCTAssertEqual(stateMachine.state, .error("boom"))

        stateMachine.reconcile(settings: settings, errorMessage: nil)
        XCTAssertEqual(stateMachine.state, .collapsed)
    }
}
