import Combine
import Foundation

/// What kind of auto-reveal a store event should trigger in the notch.
enum SessionRevealKind: Equatable, Sendable {
    case completion
    case attention
}

/// Single source of truth for live agent sessions. Fed by `HookServer`
/// (via `apply`), read by the notch UI. Main-actor because every consumer
/// is UI-side; the reducer keeps transitions pure and testable.
@MainActor
final class SessionStore: ObservableObject {
    @Published private(set) var sessions: [AgentSession] = []
    @Published private(set) var focusedSessionID: String?

    /// Fired when the notch should auto-reveal (completion/approval/question).
    var onReveal: ((SessionRevealKind, AgentSession) -> Void)?
    /// Fired when a session's transcript should be re-read (title/TLDR).
    var onTranscriptRefreshNeeded: ((AgentSession) -> Void)?
    /// Fired on a slow tick while a session has agents in flight, so their
    /// current tool call can be read from their own transcripts.
    var onSubagentRefreshNeeded: ((AgentSession) -> Void)?
    /// Fired after a session leaves the store (cleanup for markers/approvals).
    var onSessionRemoved: ((String) -> Void)?
    /// Answers a pending `AskUserQuestion` (1-based option index). Set by the
    /// window controller; invoked by `QuestionCardView` and ⌃1–9 shortcuts.
    var onAnswerQuestion: ((AgentSession, Int) -> Void)?
    /// Blocked-launcher gate: when set and it returns false for an event's
    /// terminal hint, the event is dropped (no session created or updated).
    var launcherFilter: ((TerminalHint?) -> Bool)?
    /// Sound cues for events that don't surface as reveals (prompt
    /// acknowledge, context limit, idle reminder).
    var onSoundCue: ((SoundEvent) -> Void)?

    /// Sessions without a close signal are dropped after this idle interval.
    var idleCleanupSeconds: TimeInterval = 7200
    /// Grace period an `ended` session stays visible before removal.
    var endedRemovalGraceSeconds: TimeInterval = 8

    private var sessionMap: [String: AgentSession] = [:]
    private var removalTasks: [String: Task<Void, Never>] = [:]
    private var cleanupTask: Task<Void, Never>?
    private var subagentTask: Task<Void, Never>?

    init() {
        startCleanupLoop()
    }

    deinit {
        cleanupTask?.cancel()
        subagentTask?.cancel()
    }

    // MARK: - Derived state

    var activeSessions: [AgentSession] {
        sessions.filter { $0.phase != .ended }
    }

    var workingCount: Int { sessions.count { $0.phase == .working } }
    var attentionCount: Int {
        sessions.count { $0.phase == .waitingApproval || $0.phase == .question }
    }

    var focusedSession: AgentSession? {
        if let focusedSessionID, let session = sessionMap[focusedSessionID] {
            return session
        }
        return sessions.first
    }

    /// What the collapsed strip says in Detailed mode: the title of the session
    /// it is speaking for ("fix auth bug"), like the reference — a one-word
    /// status is all we can say when that session has no title yet.
    var stripDetailLabel: String? {
        guard let session = stripLeadSession else { return stripStatusWord }
        if let title = session.title ?? session.lastUserPrompt, !title.isEmpty {
            return SessionReducer.condense(title, limit: 24)
        }
        return stripStatusWord
    }

    /// The session the strip speaks for — same precedence as the status word.
    private var stripLeadSession: AgentSession? {
        if let attention = sessions.first(where: { $0.phase == .waitingApproval || $0.phase == .question }) {
            return attention
        }
        if let failed = sessions.first(where: { $0.phase == .error }) {
            return failed
        }
        if let working = sessions.first(where: { $0.phase == .working }) {
            return working
        }
        // A session with a result to read outranks one merely sitting open.
        if let ready = sessions.first(where: { $0.phase == .ready }) {
            return ready
        }
        return sessions.first
    }

    /// One-word status for the collapsed strip's Detailed mode: attention
    /// beats working beats ready beats idle.
    var stripStatusWord: String? {
        if let attention = sessions.first(where: { $0.phase == .waitingApproval || $0.phase == .question }) {
            return attention.statusWord
        }
        if sessions.contains(where: { $0.phase == .error }) {
            return "Error"
        }
        if let working = sessions.first(where: { $0.phase == .working }) {
            return working.statusWord
        }
        if let ready = sessions.first(where: { $0.phase == .ready }) {
            return ready.statusWord
        }
        // Nothing has run yet — say so rather than claiming "Ready".
        return sessions.first?.statusWord
    }

    // MARK: - Event intake

    func apply(_ event: SessionEvent) {
        if let launcherFilter, !launcherFilter(event.context.terminalHint) {
            return
        }
        switch event.kind {
        case .userPrompt:
            onSoundCue?(.taskAcknowledge)
        case .preCompact:
            onSoundCue?(.contextLimit)
        case .notification(_, .idle):
            onSoundCue?(.idleReminder)
        default:
            break
        }
        let effects = SessionReducer.reduce(sessions: &sessionMap, event: event)
        focusedSessionID = event.context.sessionID
        publish()

        for effect in effects {
            switch effect {
            case .revealCompletion(let id):
                if let session = sessionMap[id] {
                    onReveal?(.completion, session)
                }
            case .revealAttention(let id):
                if let session = sessionMap[id] {
                    onReveal?(.attention, session)
                }
            case .refreshTranscript(let id):
                if let session = sessionMap[id] {
                    onTranscriptRefreshNeeded?(session)
                }
            case .scheduleRemoval(let id):
                scheduleRemoval(of: id)
            }
        }
    }

    /// Merges transcript-derived fields into a session (from TranscriptReader).
    func applyTranscriptDigest(
        sessionID: String,
        title: String?,
        lastPrompt: String?,
        tldr: String?,
        completionText: String?,
        model: String?
    ) {
        guard var session = sessionMap[sessionID] else { return }
        if let title, !title.isEmpty { session.title = title }
        if let lastPrompt, !lastPrompt.isEmpty { session.lastUserPrompt = lastPrompt }
        if let tldr, !tldr.isEmpty { session.completionTLDR = tldr }
        if let completionText, !completionText.isEmpty { session.completionText = completionText }
        if let model, !model.isEmpty { session.model = model }
        sessionMap[sessionID] = session
        publish()
    }

    /// Records the session's git branch (read off-main by the environment).
    func applyWorktreeBranch(sessionID: String, branch: String?) {
        guard var session = sessionMap[sessionID], session.worktreeBranch != branch else { return }
        session.worktreeBranch = branch
        sessionMap[sessionID] = session
        publish()
    }

    func session(withID id: String) -> AgentSession? {
        sessionMap[id]
    }

    /// Marks a session as waiting on a notch approval (held PreToolUse).
    func setApprovalPending(sessionID: String, message: String) {
        guard var session = sessionMap[sessionID] else { return }
        session.phase = .waitingApproval
        session.pendingApprovalMessage = message
        sessionMap[sessionID] = session
        publish()
        onReveal?(.attention, session)
    }

    /// Clears the approval state once the verdict is in.
    func clearApprovalPending(sessionID: String) {
        guard var session = sessionMap[sessionID], session.phase == .waitingApproval else { return }
        session.phase = .working
        session.pendingApprovalMessage = nil
        session.pendingApprovalPreview = nil
        sessionMap[sessionID] = session
        publish()
    }

    func removeSession(withID id: String) {
        removalTasks[id]?.cancel()
        removalTasks[id] = nil
        guard sessionMap.removeValue(forKey: id) != nil else { return }
        if focusedSessionID == id { focusedSessionID = nil }
        publish()
        onSessionRemoved?(id)
    }

    func removeAllSessions() {
        removalTasks.values.forEach { $0.cancel() }
        removalTasks.removeAll()
        let ids = Array(sessionMap.keys)
        sessionMap.removeAll()
        focusedSessionID = nil
        publish()
        ids.forEach { onSessionRemoved?($0) }
    }

    // MARK: - Internals

    private func publish() {
        sessions = sessionMap.values.sorted { lhs, rhs in
            if lhs.phase.isActive != rhs.phase.isActive {
                return lhs.phase.isActive
            }
            return lhs.startedAt > rhs.startedAt
        }
    }

    private func scheduleRemoval(of id: String) {
        removalTasks[id]?.cancel()
        removalTasks[id] = Task { [weak self] in
            let grace = self?.endedRemovalGraceSeconds ?? 8
            try? await Task.sleep(for: .seconds(grace))
            guard !Task.isCancelled else { return }
            guard let self else { return }
            if self.sessionMap[id]?.phase == .ended {
                self.removeSession(withID: id)
            }
        }
    }

    private func startCleanupLoop() {
        cleanupTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(300))
                guard let self else { return }
                self.removeStaleSessions()
            }
        }
        subagentTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                guard let self else { return }
                self.refreshRunningSubagents()
            }
        }
    }

    /// A subagent's inner tool calls arrive with no marker tying them to their
    /// parent, so their transcripts are polled instead — but only while agents
    /// are actually in flight.
    private func refreshRunningSubagents() {
        guard let onSubagentRefreshNeeded else { return }
        for session in sessionMap.values
        where session.transcriptPath != nil && session.subagents.contains(where: { !$0.isDone }) {
            onSubagentRefreshNeeded(session)
        }
    }

    /// Merges what each in-flight subagent is doing (from SubagentActivityReader).
    func applySubagentActivity(sessionID: String, activities: [SubagentActivity]) {
        guard var session = sessionMap[sessionID], !session.subagents.isEmpty else { return }
        var changed = false
        for activity in activities {
            guard let index = session.subagents.firstIndex(where: { $0.id == activity.toolUseID }),
                  !session.subagents[index].isDone
            else {
                continue
            }
            if session.subagents[index].agentID != activity.agentID {
                session.subagents[index].agentID = activity.agentID
                changed = true
            }
            if let detail = activity.detail, session.subagents[index].detail != detail {
                session.subagents[index].detail = detail
                changed = true
            }
            if let label = activity.label, session.subagents[index].label != label {
                session.subagents[index].label = label
                changed = true
            }
        }
        guard changed else { return }
        sessionMap[sessionID] = session
        publish()
    }

    private func removeStaleSessions() {
        let cutoff = Date().addingTimeInterval(-idleCleanupSeconds)
        let staleIDs = sessionMap.values
            .filter { $0.lastEventAt < cutoff }
            .map(\.id)
        guard !staleIDs.isEmpty else { return }
        for id in staleIDs {
            removalTasks[id]?.cancel()
            removalTasks[id] = nil
            sessionMap.removeValue(forKey: id)
            if focusedSessionID == id { focusedSessionID = nil }
        }
        publish()
        staleIDs.forEach { onSessionRemoved?($0) }
    }
}
