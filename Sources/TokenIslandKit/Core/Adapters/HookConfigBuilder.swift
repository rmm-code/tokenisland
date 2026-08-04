import Foundation

/// Builds and merges hook entries for any Claude-family CLI. One
/// implementation, parameterised by the hook-server route — the config shape
/// is identical across Claude Code and its derivatives (verified against real
/// `~/.qwen`, `~/.qoder`, `~/.trae`, `~/.codebuddy`, `~/.factory` configs).
enum HookConfigBuilder {
    /// Marker embedded in every command we install; identifies our entries for
    /// idempotent re-install and clean uninstall, and keeps us from ever
    /// touching another app's entries in a shared file.
    static let ownershipMarker = "#tokenisland-hook"

    /// Events every family member understands. Derivatives that don't fire one
    /// of these simply never call it — an unknown event in the config is inert.
    static let subscribedEvents: [String] = [
        "SessionStart",
        "UserPromptSubmit",
        "PreToolUse",
        "PermissionRequest",
        "PostToolUse",
        "Notification",
        "Stop",
        "StopFailure",
        "SubagentStop",
        "PreCompact",
        "SessionEnd"
    ]

    private static let matcherEvents: Set<String> = [
        "PreToolUse", "PostToolUse", "PermissionRequest", "Notification"
    ]

    /// Reads the hook JSON from stdin, resolves the controlling terminal,
    /// POSTs to the hook server and echoes the reply (so the server can return
    /// title markers and permission decisions). `|| true` keeps hooks
    /// fail-open when the app is not running.
    static func command(source: String, port: UInt16, curlTimeout: Int) -> String {
        let url = "http://127.0.0.1:\(port)/hook/\(source)"
        return #"""
        TI_TTY=$(ps -o tty= -p $$ 2>/dev/null | tr -d ' '); curl -s -m \#(curlTimeout) --connect-timeout 1 -X POST "\#(url)" -H "Content-Type: application/json" -H "X-TI-Term: ${TERM_PROGRAM:-}" -H "X-TI-Term-Session: ${TERM_SESSION_ID:-}" -H "X-TI-TTY: ${TI_TTY:+/dev/$TI_TTY}" --data-binary @- 2>/dev/null || true \#(ownershipMarker)
        """#
    }

    /// PermissionRequest gets long timeouts so a notch approval can be parked;
    /// everything else stays fast and fire-and-forget.
    static func matcherGroup(event: String, source: String, port: UInt16) -> [String: Any] {
        let isApprovalChannel = event == "PermissionRequest"
        let descriptor: [String: Any] = [
            "type": "command",
            "command": command(source: source, port: port, curlTimeout: isApprovalChannel ? 90 : 5),
            "timeout": isApprovalChannel ? 86_400 : 8
        ]
        var group: [String: Any] = ["hooks": [descriptor]]
        if matcherEvents.contains(event) {
            group["matcher"] = "*"
        }
        return group
    }

    static func ownsGroup(_ group: [String: Any]) -> Bool {
        guard let hooks = group["hooks"] as? [[String: Any]] else { return false }
        return hooks.contains { descriptor in
            (descriptor["command"] as? String)?.contains(ownershipMarker) == true
        }
    }

    /// Merges our entries into an existing config, replacing previous entries
    /// of ours (port changes, upgrades) and preserving everything else —
    /// including another agent monitor's hooks in the same file.
    static func merged(
        existing: [String: Any],
        source: String,
        port: UInt16,
        disablesTerminalTitle: Bool = false
    ) -> [String: Any] {
        var settings = existing
        var hooks = settings["hooks"] as? [String: Any] ?? [:]

        for event in subscribedEvents {
            var groups = (hooks[event] as? [[String: Any]]) ?? []
            groups.removeAll { ownsGroup($0) }
            groups.append(matcherGroup(event: event, source: source, port: port))
            hooks[event] = groups
        }
        settings["hooks"] = hooks

        guard disablesTerminalTitle else { return settings }
        var env = settings["env"] as? [String: Any] ?? [:]
        if env["CLAUDE_CODE_DISABLE_TERMINAL_TITLE"] == nil {
            env["CLAUDE_CODE_DISABLE_TERMINAL_TITLE"] = "1"
        }
        settings["env"] = env
        return settings
    }

    /// Removes only our entries; drops event arrays that become empty.
    static func stripped(existing: [String: Any]) -> [String: Any] {
        var settings = existing
        guard var hooks = settings["hooks"] as? [String: Any] else { return settings }

        for (event, value) in hooks {
            guard var groups = value as? [[String: Any]] else { continue }
            groups.removeAll { ownsGroup($0) }
            if groups.isEmpty {
                hooks.removeValue(forKey: event)
            } else {
                hooks[event] = groups
            }
        }

        settings["hooks"] = hooks.isEmpty ? nil : hooks
        return settings.compactMapValues { $0 }
    }

    /// Verifies an installed config covers all events on `port`.
    static func installState(
        settings: [String: Any],
        source: String,
        port: UInt16
    ) -> AdapterStatus {
        guard let hooks = settings["hooks"] as? [String: Any] else { return .needsSetup }
        var ownedEvents = 0
        var portMismatch = false
        let expectedURL = "127.0.0.1:\(port)/hook/\(source)"

        for event in subscribedEvents {
            guard let groups = hooks[event] as? [[String: Any]] else { continue }
            let owned = groups.filter { ownsGroup($0) }
            guard !owned.isEmpty else { continue }
            ownedEvents += 1
            let matchesPort = owned.contains { group in
                ((group["hooks"] as? [[String: Any]]) ?? []).contains { descriptor in
                    (descriptor["command"] as? String)?.contains(expectedURL) == true
                }
            }
            if !matchesPort { portMismatch = true }
        }

        if ownedEvents == 0 { return .needsSetup }
        if portMismatch { return .needsRepair("Hook port changed — reinstall") }
        if ownedEvents < subscribedEvents.count {
            return .needsRepair("Missing \(subscribedEvents.count - ownedEvents) hook event(s)")
        }
        return .active
    }
}
