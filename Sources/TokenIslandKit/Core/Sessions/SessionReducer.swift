import Foundation

/// Pure event → session-state transitions. Owns no storage; the store applies
/// results. Unit-tested in `SessionReducerTests`.
enum SessionReducer {
    /// Applies one event to the session map, returning any follow-up effects.
    static func reduce(
        sessions: inout [String: AgentSession],
        event: SessionEvent
    ) -> [SessionReduceEffect] {
        var session = sessions[event.context.sessionID] ?? synthesizeSession(from: event.context)
        mergeContext(into: &session, from: event.context)
        session.lastEventAt = event.context.timestamp

        var effects: [SessionReduceEffect] = []

        switch event.kind {
        case .sessionStart(let source):
            // Starting a CLI is not the agent doing work: it opens, prints its
            // banner and waits for you to type. Only auto-compaction fires
            // SessionStart mid-turn, so that alone stays "working" — everything
            // else (startup, resume, clear, and the file watchers' first
            // sighting) is idle until a prompt or tool event says otherwise.
            session.phase = (source == "compact") ? .working : .idle
            session.activity = nil
            session.endedAt = nil
            // A resumed session (or one the app only just started watching)
            // never sends UserPromptSubmit, so the transcript is the only
            // place its title can come from.
            effects.append(.refreshTranscript(sessionID: session.id))

        case .userPrompt(let prompt):
            session.phase = .working
            session.pendingApprovalMessage = nil
            session.pendingApprovalPreview = nil
            session.pendingQuestionMessage = nil
            session.questionOptions = []
            session.completionTLDR = nil
            // Injected blocks (reminders, task notifications, attachment
            // placeholders) are not what the user typed — a turn made only of
            // those keeps the previous title instead of showing machinery.
            if let cleaned = SessionText.sanitizedPrompt(prompt, limit: 160) {
                session.lastUserPrompt = cleaned
                if session.title == nil {
                    session.title = SessionText.sanitizedPrompt(prompt, limit: 60)
                }
            }
            if session.model == nil || session.title == nil {
                effects.append(.refreshTranscript(sessionID: session.id))
            }

        case .preTool(let toolName, let detail, let toolUseID, let subagentLabel):
            session.phase = .working
            session.pendingApprovalMessage = nil
            session.pendingApprovalPreview = nil
            session.activity = SessionActivity(
                toolName: toolName,
                detail: detail ?? "",
                startedAt: event.context.timestamp
            )
            if let subagentLabel {
                let rowID = toolUseID ?? UUID().uuidString
                // Idempotent: a watcher that re-announces a running agent (to
                // update what it is doing) must not stack duplicate rows.
                if let index = session.subagents.firstIndex(where: { $0.id == rowID }) {
                    session.subagents[index].label = subagentLabel
                    if let detail, !detail.isEmpty {
                        session.subagents[index].detail = detail
                    }
                } else {
                    session.subagents.append(
                        SubagentRow(
                            id: rowID,
                            label: subagentLabel,
                            detail: detail,
                            isDone: false,
                            startedAt: event.context.timestamp
                        )
                    )
                    session.subagents = prunedSubagents(session.subagents)
                }
            }
            // Claude's first assistant transcript entry often lands with the
            // first tool call, after the user-prompt refresh ran too early.
            // The title lags the same way, so one known model must not stop
            // the retry — that left resumed sessions reading "New session".
            if session.model == nil || session.title == nil {
                effects.append(.refreshTranscript(sessionID: session.id))
            }

        case .permissionRequest(let toolName, let detail, _, let preview):
            session.phase = .waitingApproval
            let suffix = detail.map { ": \(condense($0, limit: 80))" } ?? ""
            session.pendingApprovalMessage = "Allow \(toolName)\(suffix)?"
            session.pendingApprovalPreview = preview
            effects.append(.revealAttention(sessionID: session.id))

        case .assistantMessage(let text):
            // Records the text without touching the phase: the turn is still
            // running, this is just the newest thing the agent said.
            if let text, !text.isEmpty {
                session.completionText = String(text.prefix(2000))
                session.completionTLDR = condense(text, limit: 180)
            }

        case .stopFailure(let message):
            session.phase = .error
            session.activity = nil
            session.errorMessage = message ?? "The turn failed"
            effects.append(.revealAttention(sessionID: session.id))

        case .postTool(let toolName, let toolUseID, let asyncAgentID):
            if session.activity?.toolName == toolName {
                session.activity = nil
            }
            if let toolUseID,
               let index = session.subagents.firstIndex(where: { $0.id == toolUseID }) {
                if let asyncAgentID {
                    // Launched, not finished: keep the row running and record
                    // the handle its stop event will arrive under.
                    session.subagents[index].agentID = asyncAgentID
                    session.subagents[index].isAsync = true
                } else {
                    session.subagents[index].isDone = true
                }
            }
            // The AskUserQuestion tool finishing means the question was
            // answered (in the notch or the terminal) — clear the card.
            if toolName == "AskUserQuestion", session.phase == .question {
                session.pendingQuestionMessage = nil
                session.questionOptions = []
                session.phase = .working
            }
            if session.phase != .waitingApproval, session.phase != .question {
                session.phase = .working
            }

        case .question(let text, let options):
            session.phase = .question
            session.pendingQuestionMessage = text
            session.questionOptions = options
            effects.append(.revealAttention(sessionID: session.id))

        case .notification(let message, let category):
            switch category {
            case .permission:
                session.phase = .waitingApproval
                session.pendingApprovalMessage = message
                session.pendingApprovalPreview = nil
                effects.append(.revealAttention(sessionID: session.id))
            case .idle:
                if session.phase == .working {
                    session.phase = .ready
                }
            case .other:
                if let message, !message.isEmpty {
                    session.pendingQuestionMessage = message
                    session.phase = .question
                    effects.append(.revealAttention(sessionID: session.id))
                }
            }

        case .stop(let lastAssistantMessage):
            session.phase = .ready
            session.activity = nil
            session.pendingApprovalMessage = nil
            session.pendingApprovalPreview = nil
            session.pendingQuestionMessage = nil
            session.questionOptions = []
            session.subagents.removeAll { $0.isDone }
            if let message = lastAssistantMessage, !message.isEmpty {
                session.completionText = String(message.prefix(2000))
                session.completionTLDR = condense(message, limit: 180)
            }
            // Always re-read the transcript on turn end: it supplies the
            // model name (and fills completion text on older CLI versions).
            effects.append(.refreshTranscript(sessionID: session.id))
            effects.append(.revealCompletion(sessionID: session.id))

        case .subagentStop(let agentID):
            if let agentID,
               let index = session.subagents.firstIndex(where: { $0.agentID == agentID }) {
                session.subagents[index].isDone = true
            } else {
                // Without an id this can only be trusted when a single
                // subagent is in flight. With a fan-out running, guessing marks
                // the wrong row done — PostToolUse settles those exactly.
                let running = session.subagents.indices.filter { !session.subagents[$0].isDone }
                if running.count == 1 {
                    session.subagents[running[0]].isDone = true
                }
            }

        case .preCompact:
            // Compaction is real work, and it is the one thing that can happen
            // to a session with no prompt in flight.
            session.phase = .working

        case .sessionEnd:
            session.phase = .ended
            session.activity = nil
            session.endedAt = event.context.timestamp
            effects.append(.scheduleRemoval(sessionID: session.id))
        }

        sessions[session.id] = session
        return effects
    }

    // MARK: - Helpers

    private static func synthesizeSession(from context: SessionEventContext) -> AgentSession {
        AgentSession(
            id: context.sessionID,
            agent: context.agent,
            projectPath: context.cwd ?? "",
            title: nil,
            lastUserPrompt: nil,
            completionTLDR: nil,
            model: context.model,
            // Every event that implies work sets its own phase below; a session
            // we have only just heard of has not earned "working".
            phase: .idle,
            activity: nil,
            pendingApprovalMessage: nil,
            pendingQuestionMessage: nil,
            terminalHint: context.terminalHint,
            transcriptPath: context.transcriptPath,
            startedAt: context.timestamp,
            lastEventAt: context.timestamp,
            endedAt: nil
        )
    }

    private static func mergeContext(into session: inout AgentSession, from context: SessionEventContext) {
        if let cwd = context.cwd, !cwd.isEmpty {
            session.projectPath = cwd
        }
        if let model = context.model, !model.isEmpty {
            session.model = model
        }
        if let transcript = context.transcriptPath, !transcript.isEmpty {
            session.transcriptPath = transcript
        }
        if let hint = context.terminalHint {
            var merged = session.terminalHint ?? hint
            if let program = hint.termProgram, !program.isEmpty { merged.termProgram = program }
            if let sessionID = hint.termSessionID, !sessionID.isEmpty { merged.termSessionID = sessionID }
            if let tty = hint.ttyPath, !tty.isEmpty { merged.ttyPath = tty }
            session.terminalHint = merged
        }
    }

    /// Keeps every running subagent plus a tail of finished ones. A flat
    /// `suffix(6)` dropped live rows off the front of a wide fan-out, so a
    /// session could be running eight agents and show none of the first two.
    static let subagentHistoryLimit = 8

    static func prunedSubagents(_ rows: [SubagentRow]) -> [SubagentRow] {
        guard rows.count > subagentHistoryLimit else { return rows }
        let running = rows.filter { !$0.isDone }
        let finished = rows.filter(\.isDone)
        let keptFinished = finished.suffix(max(0, subagentHistoryLimit - running.count))
        // Preserve spawn order rather than grouping by state.
        let kept = Set(running.map(\.id)).union(keptFinished.map(\.id))
        return rows.filter { kept.contains($0.id) }
    }

    /// Collapses whitespace and trims to a display-friendly single line.
    static func condense(_ text: String, limit: Int) -> String {
        let collapsed = text
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        guard collapsed.count > limit else { return collapsed }
        return String(collapsed.prefix(limit)).trimmingCharacters(in: .whitespaces) + "…"
    }
}
