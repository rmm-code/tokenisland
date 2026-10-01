import Foundation

/// Most agent CLIs are Claude Code derivatives: same hook event names, same
/// `{"hooks": {Event: [{"hooks": [{"type": "command", "command": …}]}]}}`
/// config shape. They differ only in where the file lives and what the binary
/// is called — so they are described here as data rather than written as an
/// adapter each.
struct HookFamilyCLI: Sendable, Equatable {
    /// Which payload dialect the CLI speaks. Event names, field names and the
    /// shape of an approval answer all differ per dialect; everything
    /// downstream of the decoder is shared.
    enum Dialect: String, Sendable, Equatable {
        /// Claude Code and its derivatives: `PreToolUse`, `tool_name`,
        /// `hookSpecificOutput.decision.behavior` for PermissionRequest.
        case claude
        /// Cursor: `preToolUse`, `beforeShellExecution`, `permission`.
        case cursor
        /// Gemini CLI: `BeforeTool`, `BeforeAgent`, `decision`.
        case gemini
    }

    /// How our entries get into the CLI's configuration.
    enum ConfigStyle: Sendable, Equatable {
        /// Merge marker-tagged entries into a shared settings file, leaving
        /// every other entry (including another app's) untouched.
        case sharedFile(path: [String])
        /// Drop a file of our own into a hooks directory — no shared file, so
        /// nothing to merge and nothing to collide with.
        case ownFile(directory: [String], fileName: String)
    }

    /// Stable id ("qwen-code") used by settings and the registry.
    var id: String
    var displayName: String
    var agentKind: AgentKind
    /// URL path segment and source tag: `/hook/<source>`.
    var source: String
    var configStyle: ConfigStyle
    var dialect: Dialect = .claude
    /// Executables that prove the CLI is installed, relative to PATH roots.
    var binaryNames: [String]
    /// Directory whose presence also counts as "installed".
    var homeDirectory: [String]
    /// Claude Code overwrites the terminal title, which destroys our jump
    /// marker; its derivatives inherit the same env var.
    var disablesTerminalTitle: Bool = false

    /// Everything we ship. Each entry was verified against a real config on a
    /// machine that has the CLI installed — nothing here is guessed, because
    /// an integration that has never seen real data is not an integration.
    static let roster: [HookFamilyCLI] = [
        HookFamilyCLI(
            id: "qwen-code",
            displayName: "Qwen Code",
            agentKind: .qwen,
            source: "qwen",
            configStyle: .sharedFile(path: [".qwen", "settings.json"]),
            binaryNames: ["qwen"],
            homeDirectory: [".qwen"]
        ),
        HookFamilyCLI(
            id: "qoder",
            displayName: "Qoder",
            agentKind: .qoder,
            source: "qoder",
            configStyle: .sharedFile(path: [".qoder", "settings.json"]),
            binaryNames: ["qoder"],
            homeDirectory: [".qoder"]
        ),
        HookFamilyCLI(
            id: "trae",
            displayName: "Trae",
            agentKind: .trae,
            source: "trae",
            configStyle: .sharedFile(path: [".trae", "hooks.json"]),
            binaryNames: ["trae"],
            homeDirectory: [".trae"]
        ),
        HookFamilyCLI(
            id: "codebuddy",
            displayName: "CodeBuddy",
            agentKind: .codebuddy,
            source: "codebuddy",
            configStyle: .sharedFile(path: [".codebuddy", "settings.json"]),
            binaryNames: ["codebuddy"],
            homeDirectory: [".codebuddy"]
        ),
        HookFamilyCLI(
            id: "droid",
            displayName: "Droid",
            agentKind: .droid,
            source: "droid",
            configStyle: .sharedFile(path: [".factory", "settings.json"]),
            binaryNames: ["droid"],
            homeDirectory: [".factory"]
        ),
        HookFamilyCLI(
            id: "cursor-agent",
            displayName: "Cursor",
            agentKind: .cursor,
            source: "cursor",
            configStyle: .sharedFile(path: [".cursor", "hooks.json"]),
            dialect: .cursor,
            binaryNames: ["cursor-agent", "cursor"],
            homeDirectory: [".cursor"]
        ),
        HookFamilyCLI(
            id: "gemini-cli",
            displayName: "Gemini CLI",
            agentKind: .gemini,
            source: "gemini",
            configStyle: .sharedFile(path: [".gemini", "settings.json"]),
            dialect: .gemini,
            binaryNames: ["gemini"],
            homeDirectory: [".gemini"]
        ),
        HookFamilyCLI(
            id: "copilot-cli",
            displayName: "Copilot CLI",
            agentKind: .copilot,
            source: "copilot",
            // Copilot reads every file in its hooks directory, so we own one
            // outright instead of editing a file another app also writes.
            configStyle: .ownFile(directory: [".copilot", "hooks"], fileName: "tokenisland.json"),
            binaryNames: ["copilot"],
            homeDirectory: [".copilot"]
        )
    ]

    /// `/hook/<source>` → the agent the session belongs to.
    static func agentKind(forSource source: String) -> AgentKind? {
        if source == "claude" { return .claude }
        return roster.first { $0.source == source }?.agentKind
    }

    /// `/hook/<source>` → which payload dialect to decode it as.
    static func dialect(forSource source: String) -> Dialect? {
        if source == "claude" { return .claude }
        return roster.first { $0.source == source }?.dialect
    }

    func settingsURL(homeDirectory home: URL) -> URL {
        switch configStyle {
        case .sharedFile(let path):
            return path.reduce(home) { $0.appendingPathComponent($1) }
        case .ownFile(let directory, let fileName):
            return directory
                .reduce(home) { $0.appendingPathComponent($1, isDirectory: true) }
                .appendingPathComponent(fileName)
        }
    }

    func configDirectoryURL(homeDirectory home: URL) -> URL {
        settingsURL(homeDirectory: home).deletingLastPathComponent()
    }
}
