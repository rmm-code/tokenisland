import Foundation

/// Pure presentation policy for the expanded session list.
enum SessionPanelPresentation {
    static let initialVisibleCount = 2
    static let fullPanelCompletionInitiallyExpanded = false

    static func orderedSessions(
        _ sessions: [AgentSession],
        focusedSessionID: String?
    ) -> [AgentSession] {
        sessions.sorted { lhs, rhs in
            let lhsPriority = priority(for: lhs.phase)
            let rhsPriority = priority(for: rhs.phase)

            if lhsPriority != rhsPriority {
                return lhsPriority < rhsPriority
            }
            if lhs.lastEventAt != rhs.lastEventAt {
                return lhs.lastEventAt > rhs.lastEventAt
            }
            if lhs.startedAt != rhs.startedAt {
                return lhs.startedAt > rhs.startedAt
            }
            return lhs.id < rhs.id
        }
    }

    static func visibleSessions(
        from orderedSessions: [AgentSession],
        showAll: Bool
    ) -> [AgentSession] {
        guard !showAll else { return orderedSessions }
        return Array(orderedSessions.prefix(initialVisibleCount))
    }

    static func hiddenCount(totalCount: Int, visibleCount: Int) -> Int {
        max(0, totalCount - visibleCount)
    }

    static func showMoreLabel(hiddenCount: Int) -> String {
        hiddenCount == 1
            ? "Show 1 more session"
            : "Show \(hiddenCount) more sessions"
    }

    /// Keeps the focused completion available without letting focus reorder
    /// active sessions. Falls back to the most recent completed session.
    static func completionDetailSessionID(
        in orderedSessions: [AgentSession],
        focusedSessionID: String?
    ) -> String? {
        let completed = orderedSessions.filter {
            $0.phase == .ready && ($0.completionText != nil || $0.completionTLDR != nil)
        }
        if let focusedSessionID,
           completed.contains(where: { $0.id == focusedSessionID }) {
            return focusedSessionID
        }
        return completed.first?.id
    }

    private static func priority(for phase: SessionPhase) -> Int {
        switch phase {
        case .waitingApproval, .question, .error:
            0
        case .working:
            1
        case .ready:
            2
        // An open-but-untouched window ranks below one with a result to read.
        case .idle:
            3
        case .ended:
            4
        }
    }
}
