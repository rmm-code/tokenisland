import Combine
import Foundation

enum ApprovalDecision: String, Sendable {
    /// Allow this tool call (hook returns permissionDecision "allow").
    case allow
    /// Deny it (hook returns "deny").
    case deny
    /// No opinion — empty hook output, Claude Code proceeds normally
    /// (its own permission system asks in the terminal).
    case passthrough
}

/// One held PreToolUse call awaiting the user's verdict in the notch.
struct PendingApproval: Identifiable, Equatable, Sendable {
    let id: String
    let sessionID: String
    let toolName: String
    let detail: String?
    /// Structured command/diff preview for the approval card.
    let preview: ToolCallPreview?
    let createdAt: Date
}

/// Coordinates blocking PreToolUse round-trips: the hook server parks the
/// HTTP response here; the approval card resolves it. Fail-open by design —
/// timeout or any uncertainty yields `.passthrough` so Claude Code's native
/// prompt takes over.
@MainActor
final class ApprovalCenter: ObservableObject {
    @Published private(set) var pending: [PendingApproval] = []

    /// Labs: skip notch approvals entirely (reference "Use Native Claude
    /// Code Approvals").
    var useNativeApprovals = false
    /// How long a hook may stay parked before we fail open.
    var holdTimeoutSeconds: Double = 55

    private var continuations: [String: CheckedContinuation<ApprovalDecision, Never>] = [:]
    private var timeoutTasks: [String: Task<Void, Never>] = [:]
    /// Ids that have been registered but whose `wait` has not run yet.
    private var awaitingRegistration: Set<String> = []
    /// Verdicts that arrived before `wait` installed its continuation. Without
    /// this the press is dropped and the CLI hangs to the timeout.
    private var earlyDecisions: [String: ApprovalDecision] = [:]
    /// Tools the user already always-allowed, per session.
    private var sessionAllowlist: [String: Set<String>] = [:]
    /// Sessions the user bypassed entirely.
    private var bypassedSessions: Set<String> = []

    // MARK: - Hold decision

    /// Whether this PermissionRequest should be parked for a notch verdict.
    /// The event only fires when Claude Code is about to prompt, so no
    /// tool-type or permission-mode guessing is needed.
    func shouldHold(event: SessionEvent) -> Bool {
        guard !useNativeApprovals else { return false }
        guard case .permissionRequest = event.kind else { return false }
        return !bypassedSessions.contains(event.context.sessionID)
    }

    /// Whether to auto-answer "allow" without a card (session Always-Allow
    /// or Bypass granted earlier from the notch).
    func shouldAutoAllow(event: SessionEvent) -> Bool {
        guard case .permissionRequest(let toolName, _, _, _) = event.kind else { return false }
        let sessionID = event.context.sessionID
        if bypassedSessions.contains(sessionID) { return true }
        return sessionAllowlist[sessionID]?.contains(toolName) == true
    }

    /// Registers a pending approval and returns its id.
    func register(event: SessionEvent) -> String {
        guard case .permissionRequest(let toolName, let detail, let toolUseID, let preview) = event.kind else {
            return UUID().uuidString
        }
        let id = toolUseID ?? UUID().uuidString
        let approval = PendingApproval(
            id: id,
            sessionID: event.context.sessionID,
            toolName: toolName,
            detail: detail,
            preview: preview,
            createdAt: event.context.timestamp
        )
        // A repeat of the same tool_use_id replaces the visible card. If the
        // previous one is still parked, resolve it first — otherwise `wait`
        // overwrites its continuation and that CLI call hangs forever.
        if continuations[id] != nil || earlyDecisions[id] != nil {
            finish(id: id, decision: .passthrough)
        }
        pending.removeAll { $0.id == id }
        pending.append(approval)
        awaitingRegistration.insert(id)
        return id
    }

    /// Parks until the user decides or the timeout fails open.
    func wait(id: String) async -> ApprovalDecision {
        // The card is clickable from the moment `register` publishes it, which
        // is before this runs. A verdict pressed in that window is recorded
        // rather than dropped.
        if let early = earlyDecisions.removeValue(forKey: id) {
            awaitingRegistration.remove(id)
            return early
        }
        let timeout = holdTimeoutSeconds
        return await withCheckedContinuation { continuation in
            continuations[id] = continuation
            timeoutTasks[id] = Task { [weak self] in
                try? await Task.sleep(for: .seconds(timeout))
                guard !Task.isCancelled else { return }
                self?.finish(id: id, decision: .passthrough)
            }
        }
    }

    // MARK: - Resolution (from the approval card / shortcuts)

    func approve(id: String) {
        finish(id: id, decision: .allow)
    }

    func deny(id: String) {
        finish(id: id, decision: .deny)
    }

    /// Allow + remember the tool for this session.
    func alwaysAllow(id: String) {
        if let approval = pending.first(where: { $0.id == id }) {
            sessionAllowlist[approval.sessionID, default: []].insert(approval.toolName)
        }
        finish(id: id, decision: .allow)
    }

    /// Allow + stop holding anything for this session.
    func bypass(id: String) {
        if let approval = pending.first(where: { $0.id == id }) {
            bypassedSessions.insert(approval.sessionID)
        }
        finish(id: id, decision: .allow)
    }

    /// The approval a session should be answering right now.
    ///
    /// Oldest-first, deliberately: when a session has several requests parked
    /// at once, the oldest is the one closest to failing open, so surfacing the
    /// newest (LIFO) is what let the older one time out unanswered.
    func pendingApproval(forSessionID sessionID: String) -> PendingApproval? {
        pending.first { $0.sessionID == sessionID }
    }

    func dropPending(forSessionID sessionID: String) {
        for approval in pending where approval.sessionID == sessionID {
            finish(id: approval.id, decision: .passthrough)
        }
        sessionAllowlist.removeValue(forKey: sessionID)
        bypassedSessions.remove(sessionID)
    }

    private func finish(id: String, decision: ApprovalDecision) {
        timeoutTasks.removeValue(forKey: id)?.cancel()
        pending.removeAll { $0.id == id }
        if let continuation = continuations.removeValue(forKey: id) {
            awaitingRegistration.remove(id)
            earlyDecisions.removeValue(forKey: id)
            continuation.resume(returning: decision)
        } else if awaitingRegistration.remove(id) != nil {
            // Verdict beat `wait` to it — hold it so `wait` returns at once.
            earlyDecisions[id] = decision
        }
    }
}

/// Serialized hook stdout payloads (single place that knows the schema).
enum HookResponses {
    /// Each CLI family answers an approval in its own shape: Claude Code with
    /// `hookSpecificOutput`, Cursor with `permission`, Gemini with `decision`.
    /// Sending the wrong one reads as "no opinion" and the CLI prompts in the
    /// terminal anyway, so this has to match the source the event came from.
    static func permission(
        _ decision: ApprovalDecision,
        reason: String,
        agent: AgentKind
    ) -> String? {
        switch agent {
        case .cursor:
            return CursorHookRouter.permissionResponse(decision, reason: reason)
        case .gemini:
            return GeminiHookRouter.permissionResponse(decision, reason: reason)
        default:
            return permission(decision, reason: reason)
        }
    }

    static func permission(
        _ decision: ApprovalDecision,
        reason: String,
        hookEventName: String = "PermissionRequest"
    ) -> String? {
        switch decision {
        case .passthrough:
            return nil
        case .allow, .deny:
            let payload: [String: Any] = [
                "hookSpecificOutput": [
                    "hookEventName": hookEventName,
                    "permissionDecision": decision.rawValue,
                    "permissionDecisionReason": reason
                ]
            ]
            guard let data = try? JSONSerialization.data(withJSONObject: payload) else { return nil }
            return String(data: data, encoding: .utf8)
        }
    }

    static func serialize(_ payload: [String: String]) -> String? {
        guard let data = try? JSONSerialization.data(withJSONObject: payload) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
