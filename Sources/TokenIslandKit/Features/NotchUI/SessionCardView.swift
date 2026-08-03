import SwiftUI

/// Small rounded chip. The Claude chip uses the amber brand tint from the
/// reference; everything else stays neutral gray.
struct SessionChip: View {
    enum Style {
        case agent
        case neutral
    }

    var text: String
    var style: Style = .neutral

    var body: some View {
        Text(text)
            .font(.system(size: 10.5, weight: .semibold))
            .foregroundStyle(style == .agent ? Color(red: 0.91, green: 0.60, blue: 0.34) : Color.white.opacity(0.72))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(
                style == .agent ? Color(red: 0.30, green: 0.19, blue: 0.10) : Color.white.opacity(0.10),
                in: RoundedRectangle(cornerRadius: 6, style: .continuous)
            )
    }
}

/// One session row in the expanded panel — flat on black like the reference:
/// pet + cursor, bold title with trailing chips, activity line, TLDR line.
struct SessionCardView: View {
    @EnvironmentObject private var appState: AppState
    var session: AgentSession
    var isFocused: Bool = false
    var showSubagents: Bool = true
    /// Reveals show fewer subagent rows than the panel — the card is a glance,
    /// not the full list.
    var compactSubagents: Bool = false
    /// Reveals run tighter than the panel: every point above the first row is
    /// black the notch already owns.
    var verticalPadding: CGFloat = 8
    var onJump: (AgentSession) -> Void

    @State private var isHovering = false

    private var baseFontSize: CGFloat {
        CGFloat(min(max(appState.settings.contentFontSize, 9), 14))
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            SessionPetBadge(session: session, pixelSize: 2.2)
                .padding(.top, 3)
                .frame(width: 44, alignment: .center)

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(titleLine)
                        .font(.system(size: baseFontSize + 3, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    Spacer(minLength: 8)

                    SessionChip(text: session.agent.displayName, style: session.agent == .claude ? .agent : .neutral)
                    if appState.settings.showAIModel,
                       let model = ModelNameFormatter.displayName(session.model) {
                        SessionChip(text: model)
                    }
                    if let terminal = session.terminalHint?.displayName {
                        SessionChip(text: terminal)
                    }
                    SessionChip(text: elapsedText)

                    if isHovering {
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(TITheme.blue)
                    }
                }

                statusLines

                if showSubagents, appState.settings.showSubagents, !session.subagents.isEmpty {
                    subagentBlock
                        .padding(.top, 2)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, verticalPadding)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(isHovering ? 0.06 : 0))
        )
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .onTapGesture { onJump(session) }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityDescription)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { onJump(session) }
    }

    private var titleLine: String {
        var prefix = appState.settings.showProjectName ? session.projectName : ""
        // Reference format: "vibe-island ⌥ chat-ui · Refactor auth…" —
        // branch shown when it isn't the default one.
        if appState.settings.showWorktree,
           let branch = session.worktreeBranch,
           branch != "main", branch != "master" {
            prefix = prefix.isEmpty ? "⌥ \(branch)" : "\(prefix) ⌥ \(branch)"
        }
        return prefix.isEmpty ? session.displayTitle : "\(prefix) · \(session.displayTitle)"
    }

    private var elapsedText: String {
        let seconds = max(0, session.elapsedSinceLastEvent)
        if seconds < 60 { return "<1m" }
        let minutes = Int(seconds / 60)
        if minutes < 60 { return "\(minutes)m" }
        return "\(minutes / 60)h \(minutes % 60)m"
    }

    private var accessibilityDescription: String {
        var parts = [session.projectName, session.displayTitle, session.statusWord]
        if let model = ModelNameFormatter.displayName(session.model) {
            parts.append(model)
        }
        if let terminal = session.terminalHint?.displayName {
            parts.append(terminal)
        }
        if let activity = session.activity {
            parts.append("\(activity.toolName), \(activity.detail)")
        }
        return parts.filter { !$0.isEmpty }.joined(separator: ", ")
    }

    @ViewBuilder
    private var statusLines: some View {
        switch session.phase {
        case .idle:
            // Open, nothing running. The last prompt still identifies which
            // conversation this window holds, so keep it — dimmed, and never
            // dressed up as live activity.
            Text("Waiting for your prompt")
                .font(.system(size: baseFontSize + 1, weight: .medium))
                .foregroundStyle(PetPalette.tint(for: .idle))
            if let prompt = session.lastUserPrompt {
                youLine(prompt)
                    .opacity(0.6)
            }

        case .working:
            if appState.settings.showAgentActivityDetail, let activity = session.activity {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(activity.toolName)
                        .font(.system(size: baseFontSize + 1, weight: .semibold))
                        .foregroundStyle(toolColor(activity.toolName))
                    Text(activity.detail)
                        .font(.system(size: baseFontSize + 1))
                        .foregroundStyle(Color.white.opacity(0.55))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            } else if let prompt = session.lastUserPrompt {
                youLine(prompt)
            } else {
                Text("Working…")
                    .font(.system(size: baseFontSize + 1))
                    .foregroundStyle(Color.white.opacity(0.55))
            }

        case .waitingApproval:
            Text(session.pendingApprovalMessage ?? "Waiting for your approval")
                .font(.system(size: baseFontSize + 1, weight: .medium))
                .foregroundStyle(TITheme.warning)
                .lineLimit(2)

        case .question:
            Text(session.pendingQuestionMessage ?? "Claude has a question")
                .font(.system(size: baseFontSize + 1, weight: .medium))
                .foregroundStyle(TITheme.warning)
                .lineLimit(2)

        case .ready:
            // Reference layout: "You: <prompt>" then a dimmer TLDR line.
            if let prompt = session.lastUserPrompt {
                youLine(prompt)
            }
            if let tldr = session.completionTLDR {
                // The TLDR is markdown — rendered, like the reference, so the
                // line reads as prose instead of showing raw ** ** and ` `.
                LiteMarkdownText(text: tldr, size: baseFontSize + 1)
                    .foregroundStyle(Color.white.opacity(0.42))
                    .lineLimit(1)
                    .truncationMode(.tail)
            } else if session.lastUserPrompt == nil {
                Text("Ready")
                    .font(.system(size: baseFontSize + 1, weight: .semibold))
                    .foregroundStyle(PetPalette.tint(for: .ready))
            }

        case .error:
            Text(session.errorMessage ?? "Error")
                .font(.system(size: baseFontSize + 1))
                .foregroundStyle(TITheme.danger)
                .lineLimit(2)

        case .ended:
            Text("Session ended")
                .font(.system(size: baseFontSize + 1))
                .foregroundStyle(Color.white.opacity(0.35))
        }
    }

    private func youLine(_ prompt: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text("You:")
                .font(.system(size: baseFontSize + 1, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.55))
            Text(prompt)
                .font(.system(size: baseFontSize + 1))
                .foregroundStyle(Color.white.opacity(0.55))
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }

    /// Running rows first — on a wide fan-out the live ones are what you came
    /// to look at — then the most recent finished ones, capped for the card.
    private var visibleSubagents: [SubagentRow] {
        let limit = compactSubagents ? 3 : 6
        let running = session.subagents.filter { !$0.isDone }
        let finished = session.subagents.filter(\.isDone)
        return Array((running + finished.reversed()).prefix(limit))
    }

    private var runningSubagentCount: Int {
        session.subagents.filter { !$0.isDone }.count
    }

    /// While agents are in flight their ages have to tick on their own —
    /// nothing else redraws the card between hook events.
    @ViewBuilder
    private var subagentBlock: some View {
        if runningSubagentCount > 0 {
            TimelineView(.periodic(from: .now, by: 1)) { _ in
                subagentList
            }
        } else {
            subagentList
        }
    }

    private var subagentList: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text("Agents (\(session.subagents.count))")
                    .font(.system(size: baseFontSize - 1, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.42))
                if runningSubagentCount > 0 {
                    Text("\(runningSubagentCount) running")
                        .font(.system(size: baseFontSize - 1))
                        .foregroundStyle(PetPalette.tint(for: .working).opacity(0.85))
                }
            }
            ForEach(visibleSubagents) { subagent in
                subagentRow(subagent)
            }
            if session.subagents.count > visibleSubagents.count {
                Text("+\(session.subagents.count - visibleSubagents.count) more")
                    .font(.system(size: baseFontSize - 1))
                    .foregroundStyle(Color.white.opacity(0.30))
            }
        }
    }

    private func subagentRow(_ subagent: SubagentRow) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Circle()
                .fill(subagent.isDone ? PetPalette.tint(for: .ready) : PetPalette.tint(for: .working))
                .frame(width: 4, height: 4)
            Text(subagent.label)
                .font(.system(size: baseFontSize - 0.5))
                .foregroundStyle(Color.white.opacity(0.55))
                .lineLimit(1)
                .layoutPriority(1)
            // What this agent is doing right now, when we can attribute it.
            if !subagent.isDone, let detail = subagent.detail, !detail.isEmpty {
                Text(detail)
                    .font(.system(size: baseFontSize - 1))
                    .foregroundStyle(Color.white.opacity(0.38))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Spacer(minLength: 4)
            Text(subagent.isDone ? "Done" : SessionCardView.elapsed(since: subagent.startedAt))
                .font(.system(size: baseFontSize - 1, design: subagent.isDone ? .default : .monospaced))
                .foregroundStyle(Color.white.opacity(0.35))
        }
    }

    /// "8s", "2m", "1h 4m" — a subagent's own age, independent of the session.
    static func elapsed(since date: Date) -> String {
        let seconds = max(0, Date().timeIntervalSince(date))
        if seconds < 60 { return "\(Int(seconds))s" }
        let minutes = Int(seconds / 60)
        if minutes < 60 { return "\(minutes)m" }
        return "\(minutes / 60)h \(minutes % 60)m"
    }

    private func toolColor(_ tool: String) -> Color {
        switch tool {
        case "Read", "Glob", "Grep": Color(red: 0.35, green: 0.65, blue: 1.0)
        case "Edit", "Write", "NotebookEdit": TITheme.warning
        case "Bash": Color(red: 0.72, green: 0.62, blue: 1.0)
        case "Task": Color(red: 0.45, green: 0.85, blue: 0.85)
        default: Color.white.opacity(0.55)
        }
    }
}
