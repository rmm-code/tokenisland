import Foundation

/// Shared production/test wiring for an event and its parked approval reply.
@MainActor
final class HookEventHandler {
    private let sessionStore: SessionStore
    private let approvalCenter: ApprovalCenter
    private let titleMarkers: TitleMarkerService
    private let isEnabled: (AgentKind) -> Bool

    init(
        sessionStore: SessionStore,
        approvalCenter: ApprovalCenter,
        titleMarkers: TitleMarkerService = TitleMarkerService(),
        isEnabled: @escaping (AgentKind) -> Bool = { _ in true }
    ) {
        self.sessionStore = sessionStore
        self.approvalCenter = approvalCenter
        self.titleMarkers = titleMarkers
        self.isEnabled = isEnabled
    }

    func handle(_ event: SessionEvent) async -> String? {
        guard isEnabled(event.context.agent) else { return nil }
        if event.context.agent == .cursor || event.context.agent == .gemini,
           case .permissionRequest(let tool, let detail, let id, _) = event.kind {
            var observation = event
            observation.kind = .preTool(toolName: tool, detail: detail, toolUseID: id, subagentLabel: nil)
            sessionStore.apply(observation)
            // These CLIs expose tool gates, not a "user is being asked"
            // event. Their native permissions stay in charge; our hook adds
            // no additional policy or artificial approval wait.
            return event.context.agent == .cursor
                ? CursorHookRouter.permissionResponse(.allow, reason: "") : nil
        }
        sessionStore.apply(event)
        if case .permissionRequest = event.kind {
            let decision: ApprovalDecision
            if approvalCenter.shouldAutoAllow(event: event) {
                decision = .allow
            } else if approvalCenter.shouldHold(event: event) {
                let id = approvalCenter.register(event: event)
                decision = await approvalCenter.wait(id: id)
            } else {
                decision = .passthrough
            }
            sessionStore.resolveApproval(
                sessionID: event.context.sessionID,
                decision: decision,
                remaining: approvalCenter.pendingApproval(forSessionID: event.context.sessionID)
            )
            return HookResponses.permission(decision, reason: "Decided from the notch", agent: event.context.agent)
        }
        // Cursor/Gemini do not understand Claude's title-marker output.
        guard event.context.agent != .cursor, event.context.agent != .gemini,
              let session = sessionStore.session(withID: event.context.sessionID),
              let payload = titleMarkers.responsePayload(for: event, session: session)
        else { return nil }
        return HookResponses.serialize(payload)
    }
}
