import Foundation

/// Assigns each session a human-readable terminal-title slug
/// ("claude — fix-auth-bug") and produces the OSC sequence that stamps it
/// into the hosting terminal. The hook server returns that sequence as
/// `terminalSequence` hook output; click-to-jump (P4) matches window titles
/// against the same slug.
@MainActor
final class TitleMarkerService: ObservableObject {
    /// Disabled via Settings → Integrations (P6).
    var isEnabled = true

    private struct Assignment {
        var slug: String
        var isFromTitle: Bool
    }

    private var assignments: [String: Assignment] = [:]
    private var usedSlugs: Set<String> = []

    /// Title text a terminal window will carry for this session, if any.
    func markerTitle(forSessionID id: String) -> String? {
        guard let assignment = assignments[id] else { return nil }
        return Self.title(slug: assignment.slug)
    }

    /// Hook response payload for events that should (re)stamp the title.
    func responsePayload(for event: SessionEvent, session: AgentSession) -> [String: String]? {
        guard isEnabled else { return nil }

        switch event.kind {
        case .sessionStart:
            let slug = assignSlug(sessionID: session.id, preferred: session.projectName, isFromTitle: false)
            return terminalSequencePayload(slug: slug)

        case .userPrompt:
            // Upgrade a project-based slug to the task title once we have one.
            guard let title = session.title, !title.isEmpty else { return nil }
            if let existing = assignments[session.id], existing.isFromTitle { return nil }
            let slug = assignSlug(sessionID: session.id, preferred: title, isFromTitle: true)
            return terminalSequencePayload(slug: slug)

        default:
            return nil
        }
    }

    func forget(sessionID: String) {
        if let assignment = assignments.removeValue(forKey: sessionID) {
            usedSlugs.remove(assignment.slug)
        }
    }

    // MARK: - Internals

    private func terminalSequencePayload(slug: String) -> [String: String] {
        ["terminalSequence": "\u{1B}]0;\(Self.title(slug: slug))\u{07}"]
    }

    private static func title(slug: String) -> String {
        "claude — \(slug)"
    }

    private func assignSlug(sessionID: String, preferred: String, isFromTitle: Bool) -> String {
        if let existing = assignments[sessionID], existing.isFromTitle == isFromTitle {
            return existing.slug
        }
        if let previous = assignments[sessionID] {
            usedSlugs.remove(previous.slug)
        }

        let base = Self.slugify(preferred)
        var candidate = base
        var suffix = 2
        while usedSlugs.contains(candidate), suffix < 10 {
            candidate = "\(base)-\(suffix)"
            suffix += 1
        }

        usedSlugs.insert(candidate)
        assignments[sessionID] = Assignment(slug: candidate, isFromTitle: isFromTitle)
        return candidate
    }

    nonisolated static func slugify(_ text: String) -> String {
        let lowered = text.lowercased()
        var result = ""
        var previousWasDash = false
        for scalar in lowered.unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar) {
                result.unicodeScalars.append(scalar)
                previousWasDash = false
            } else if !previousWasDash, !result.isEmpty {
                result.append("-")
                previousWasDash = true
            }
        }
        while result.hasSuffix("-") { result.removeLast() }
        if result.isEmpty { result = "session" }
        return String(result.prefix(28))
    }
}
