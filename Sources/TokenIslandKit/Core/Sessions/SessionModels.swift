import Foundation

/// Which CLI agent produced a session.
enum AgentKind: String, Codable, CaseIterable, Sendable {
    case claude
    case codex
    case gemini
    case cursor
    case opencode
    case copilot
    case qwen
    case qoder
    case trae
    case codebuddy
    case droid
    case other

    var displayName: String {
        switch self {
        case .claude: "Claude"
        case .codex: "Codex"
        case .gemini: "Gemini"
        case .cursor: "Cursor"
        case .opencode: "OpenCode"
        case .copilot: "Copilot"
        case .qwen: "Qwen"
        case .qoder: "Qoder"
        case .trae: "Trae"
        case .codebuddy: "CodeBuddy"
        case .droid: "Droid"
        case .other: "Agent"
        }
    }
}

/// Lifecycle phase of a session, drives pet color and card status line.
/// Why a session is in `.waitingApproval`.
enum PendingApprovalSource: String, Codable, Sendable {
    /// A held `PermissionRequest` — the notch owns the verdict (⌃Y/⌃N/⌃A).
    case notchVerdict
    /// The CLI is prompting in its own terminal and is not waiting on us; the
    /// only useful action from the notch is to jump there.
    case terminalOnly
}

enum SessionPhase: String, Codable, Sendable {
    /// Open but doing nothing — the CLI is sitting at its prompt waiting for
    /// the user to type. Distinct from `.ready`, which means a turn just
    /// finished and there is a result worth reading.
    case idle
    case working
    case waitingApproval
    case question
    case ready
    case error
    case ended

    var isActive: Bool {
        switch self {
        case .working, .waitingApproval, .question: true
        case .idle, .ready, .error, .ended: false
        }
    }
}

/// The current tool action shown on a session card ("Read /path/…").
struct SessionActivity: Equatable, Sendable {
    var toolName: String
    var detail: String
    var startedAt: Date

    /// One-word verb for the collapsed strip's Detailed mode.
    var statusWord: String {
        switch toolName {
        case "Read", "Glob", "Grep": "Reading"
        case "Edit", "Write", "NotebookEdit": "Writing"
        case "Bash": "Running"
        case "WebFetch", "WebSearch": "Browsing"
        case "Task": "Delegating"
        default: "Working"
        }
    }
}

/// A fan-out subagent row rendered under a session card. `id` is the spawning
/// tool-use id; `agentID` is the CLI's own handle for the run, learned from the
/// subagent's metadata file and the only thing `SubagentStop` reports.
struct SubagentRow: Identifiable, Equatable, Sendable {
    var id: String
    var label: String
    var detail: String?
    var isDone: Bool
    var startedAt: Date
    var agentID: String?
    /// Background spawns return from their tool call immediately, so the tool
    /// finishing says nothing about the agent finishing.
    var isAsync: Bool = false
}

/// Hints for binding a session to its terminal window (click-to-jump).
struct TerminalHint: Equatable, Sendable {
    var termProgram: String?
    var termSessionID: String?
    var ttyPath: String?

    /// Best-guess bundle identifier for the hosting terminal app.
    var bundleIdentifier: String? {
        switch termProgram?.lowercased() {
        case "apple_terminal": "com.apple.Terminal"
        case "iterm.app": "com.googlecode.iterm2"
        case "ghostty": "com.mitchellh.ghostty"
        case "warpterminal": "dev.warp.Warp-Stable"
        case "vscode": "com.microsoft.VSCode"
        case "cursor": "com.todesktop.230313mzl4w4u92"
        case "wezterm": "com.github.wez.wezterm"
        case "kitty": "net.kovidgoyal.kitty"
        case "alacritty": "org.alacritty"
        case "hyper": "co.zeit.hyper"
        case "tabby": "org.tabby"
        default: nil
        }
    }

    var displayName: String? {
        switch termProgram?.lowercased() {
        case "apple_terminal": "Terminal"
        case "iterm.app": "iTerm"
        case "ghostty": "Ghostty"
        case "warpterminal": "Warp"
        case "vscode": "VS Code"
        case "cursor": "Cursor"
        case "wezterm": "WezTerm"
        case "kitty": "kitty"
        case "alacritty": "Alacritty"
        default: termProgram
        }
    }
}

/// One live (or recently ended) AI CLI session.
struct AgentSession: Identifiable, Equatable, Sendable {
    let id: String
    var agent: AgentKind
    var projectPath: String
    var title: String?
    var lastUserPrompt: String?
    /// Condensed one/two-line summary shown on the card status line.
    var completionTLDR: String?
    /// Longer completion excerpt rendered in the completion card (capped).
    var completionText: String?
    var model: String?
    var phase: SessionPhase
    var activity: SessionActivity?
    var pendingApprovalMessage: String?
    /// Structured command/diff preview for the pending approval card.
    var pendingApprovalPreview: ToolCallPreview?
    /// Which kind of approval put this session in `.waitingApproval`. The phase
    /// alone cannot say: a parked `PermissionRequest` is answerable from the
    /// notch, a `Notification(permission_prompt)` only reports that the CLI is
    /// prompting in its own terminal.
    var pendingApprovalSource: PendingApprovalSource?
    var pendingQuestionMessage: String?
    /// Option labels for a pending `AskUserQuestion` (max 9, answer via ⌃1–9).
    var questionOptions: [String] = []
    var terminalHint: TerminalHint?
    /// Git branch of the working directory ("⌥ branch" in the card title).
    var worktreeBranch: String?
    var transcriptPath: String?
    var startedAt: Date
    var lastEventAt: Date
    var endedAt: Date?
    var subagents: [SubagentRow] = []
    var errorMessage: String?

    var projectName: String {
        let name = URL(fileURLWithPath: projectPath).lastPathComponent
        return name.isEmpty ? "session" : name
    }

    /// Short stable marker used in terminal titles for window binding.
    var markerID: String {
        String(id.replacingOccurrences(of: "-", with: "").prefix(8))
    }

    var displayTitle: String {
        if let title, !title.isEmpty { return title }
        if let lastUserPrompt, !lastUserPrompt.isEmpty { return lastUserPrompt }
        return "New session"
    }

    /// Status word for the collapsed strip (Detailed mode).
    var statusWord: String {
        switch phase {
        case .idle: "Idle"
        case .working: activity?.statusWord ?? "Working"
        case .waitingApproval: "Approval"
        case .question: "Question"
        case .ready: "Ready"
        case .error: "Error"
        case .ended: "Ended"
        }
    }

    var elapsedSinceLastEvent: TimeInterval {
        Date().timeIntervalSince(lastEventAt)
    }
}
