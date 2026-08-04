import Foundation

/// Claude Code's view of the shared hook builder. Claude is one member of the
/// family (`HookConfigBuilder`); this keeps its route and terminal-title
/// override in one place and its call sites unchanged.
enum ClaudeHookCommand {
    static let source = "claude"
    static var ownershipMarker: String { HookConfigBuilder.ownershipMarker }
    static var subscribedEvents: [String] { HookConfigBuilder.subscribedEvents }

    static func command(port: UInt16, curlTimeout: Int) -> String {
        HookConfigBuilder.command(source: source, port: port, curlTimeout: curlTimeout)
    }

    static func matcherGroup(event: String, port: UInt16) -> [String: Any] {
        HookConfigBuilder.matcherGroup(event: event, source: source, port: port)
    }

    static func ownsGroup(_ group: [String: Any]) -> Bool {
        HookConfigBuilder.ownsGroup(group)
    }

    /// Claude Code overwrites the terminal title, which destroys the session
    /// marker click-to-jump relies on.
    static func mergedEnv(existing: [String: Any], titleMarkersEnabled: Bool) -> [String: Any] {
        guard titleMarkersEnabled else { return existing }
        var settings = existing
        var env = settings["env"] as? [String: Any] ?? [:]
        if env["CLAUDE_CODE_DISABLE_TERMINAL_TITLE"] == nil {
            env["CLAUDE_CODE_DISABLE_TERMINAL_TITLE"] = "1"
        }
        settings["env"] = env
        return settings
    }

    static func mergedSettings(existing: [String: Any], port: UInt16) -> [String: Any] {
        HookConfigBuilder.merged(
            existing: existing,
            source: source,
            port: port,
            disablesTerminalTitle: true
        )
    }

    static func strippedSettings(existing: [String: Any]) -> [String: Any] {
        HookConfigBuilder.stripped(existing: existing)
    }

    static func installState(settings: [String: Any], port: UInt16) -> AdapterStatus {
        HookConfigBuilder.installState(settings: settings, source: source, port: port)
    }
}
