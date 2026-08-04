import Foundation

/// Category of a Notification hook payload.
enum SessionNotificationCategory: Equatable, Sendable {
    case permission
    case idle
    case other
}

/// Structured preview of the tool call awaiting approval — powers the
/// command/diff block inside the approval card (reference-style).
struct ToolCallPreview: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case bashCommand(String)
        case editDiff(path: String, old: String, new: String)
        case writeFile(path: String, content: String)
        case generic(String)
    }

    var kind: Kind
}

/// Shared fields present on every normalized hook event.
struct SessionEventContext: Equatable, Sendable {
    var sessionID: String
    var agent: AgentKind
    var cwd: String?
    /// Provider model reported by the live session, when available.
    var model: String?
    var transcriptPath: String?
    var terminalHint: TerminalHint?
    /// Claude Code permission mode ("default", "acceptEdits",
    /// "bypassPermissions", …) — drives the approval-hold decision.
    var permissionMode: String?
    var timestamp: Date

    init(
        sessionID: String,
        agent: AgentKind,
        cwd: String? = nil,
        model: String? = nil,
        transcriptPath: String? = nil,
        terminalHint: TerminalHint? = nil,
        permissionMode: String? = nil,
        timestamp: Date = Date()
    ) {
        self.sessionID = sessionID
        self.agent = agent
        self.cwd = cwd
        self.model = model
        self.transcriptPath = transcriptPath
        self.terminalHint = terminalHint
        self.permissionMode = permissionMode
        self.timestamp = timestamp
    }
}

/// Normalized inbound event from any CLI hook.
enum SessionEventKind: Equatable, Sendable {
    case sessionStart(source: String?)
    case userPrompt(prompt: String?)
    /// `subagentLabel` is set when the tool is a fan-out Task spawn.
    case preTool(toolName: String, detail: String?, toolUseID: String?, subagentLabel: String?)
    /// Claude Code is about to show a permission prompt for this tool call —
    /// the hook blocks awaiting our verdict (the notch approval channel).
    case permissionRequest(toolName: String, detail: String?, toolUseID: String?, preview: ToolCallPreview?)
    /// `asyncAgentID` is set when the finished tool call was a *background*
    /// subagent spawn: the call returns at launch, so the agent is still
    /// running and only `subagentStop` can settle it.
    case postTool(toolName: String, toolUseID: String?, asyncAgentID: String? = nil)
    /// Claude's `AskUserQuestion` tool: a multiple-choice question answerable
    /// from the notch (option labels capped at 9 for ⌃1–9 shortcuts).
    case question(text: String, options: [String])
    case notification(message: String?, category: SessionNotificationCategory)
    /// The agent produced a message but the turn continues — Cursor reports
    /// these separately from its `stop` event, so the completion card has
    /// something to show when the turn does end.
    case assistantMessage(text: String?)
    case stop(lastAssistantMessage: String?)
    /// The turn ended in an error (API failure, tool crash).
    case stopFailure(message: String?)
    /// The CLI reports which agent stopped by its own id — the id a
    /// tool-use-keyed row learns from the subagent metadata on disk.
    case subagentStop(agentID: String? = nil)
    case preCompact
    case sessionEnd(reason: String?)
}

struct SessionEvent: Equatable, Sendable {
    var context: SessionEventContext
    var kind: SessionEventKind
}

/// Side effects the reducer asks the store to perform after a transition.
enum SessionReduceEffect: Equatable, Sendable {
    /// A session finished its turn — candidates for completion auto-reveal.
    case revealCompletion(sessionID: String)
    /// A session needs the user (permission or question) — auto-reveal + sound.
    case revealAttention(sessionID: String)
    /// Session ended and should be removed after a grace period.
    case scheduleRemoval(sessionID: String)
    /// Refresh title/TLDR from the transcript file for this session.
    case refreshTranscript(sessionID: String)
}
