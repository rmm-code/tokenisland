import Foundation

/// Builds the shell command installed into Claude Code hook entries and the
/// JSON structures for `~/.claude/settings.json`. Kept separate from the
/// adapter so the exact command syntax is unit-testable.
enum ClaudeHookCommand {
    /// Marker embedded in every command we install; identifies our entries
    /// for idempotent re-install and clean uninstall.
    static let ownershipMarker = "#tokenisland-hook"

    /// Hook events we subscribe to. PermissionRequest is the approval
    /// channel (fires only when Claude Code would actually prompt, and may
    /// block on our verdict); everything else is fire-and-forget fast.
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

    /// The forwarding command. Reads the hook JSON from stdin, resolves the
    /// controlling terminal, POSTs everything to the hook server, and echoes
    /// the server's reply (lets the server return `terminalSequence` title
    /// markers and PreToolUse permission decisions). `|| true` keeps hooks
    /// fail-open when the app is not running. `curlTimeout` must exceed the
    /// approval hold for PreToolUse and stay tiny for everything else.
    static func command(port: UInt16, curlTimeout: Int) -> String {
        let url = "http://127.0.0.1:\(port)/hook/claude"
        return #"""
        TI_TTY=$(ps -o tty= -p $$ 2>/dev/null | tr -d ' '); curl -s -m \#(curlTimeout) --connect-timeout 1 -X POST "\#(url)" -H "Content-Type: application/json" -H "X-TI-Term: ${TERM_PROGRAM:-}" -H "X-TI-Term-Session: ${TERM_SESSION_ID:-}" -H "X-TI-TTY: ${TI_TTY:+/dev/$TI_TTY}" --data-binary @- 2>/dev/null || true \#(ownershipMarker)
        """#
    }

    /// The matcher group wrapping our descriptor. Tool events get a `"*"`
    /// matcher; lifecycle events omit the matcher entirely. PermissionRequest
    /// gets long timeouts so the notch-approval hold can complete (the
    /// reference app parks it for up to a day); the server answers instantly
    /// whenever no approval hold applies.
    static func matcherGroup(event: String, port: UInt16) -> [String: Any] {
        let isApprovalChannel = event == "PermissionRequest"
        let descriptor: [String: Any] = [
            "type": "command",
            "command": command(port: port, curlTimeout: isApprovalChannel ? 90 : 5),
            "timeout": isApprovalChannel ? 86_400 : 8
        ]
        var group: [String: Any] = ["hooks": [descriptor]]
        if event == "PreToolUse" || event == "PostToolUse" || event == "PermissionRequest" || event == "Notification" {
            group["matcher"] = "*"
        }
        return group
    }

    /// Claude Code environment overrides we own. Disabling the native
    /// terminal title keeps our session marker from being overwritten
    /// (mirrors the reference "Disable Claude Code Native Terminal Title").
    static func mergedEnv(existing: [String: Any], titleMarkersEnabled: Bool) -> [String: Any] {
        var settings = existing
        guard titleMarkersEnabled else { return settings }
        var env = settings["env"] as? [String: Any] ?? [:]
        if env["CLAUDE_CODE_DISABLE_TERMINAL_TITLE"] == nil {
            env["CLAUDE_CODE_DISABLE_TERMINAL_TITLE"] = "1"
        }
        settings["env"] = env
        return settings
    }

    /// True when a hook entry (any shape) belongs to us.
    static func ownsGroup(_ group: [String: Any]) -> Bool {
        guard let hooks = group["hooks"] as? [[String: Any]] else { return false }
        return hooks.contains { descriptor in
            (descriptor["command"] as? String)?.contains(ownershipMarker) == true
        }
    }

    /// Merges our hook entries into an existing settings dictionary,
    /// replacing any previous entries of ours (port changes, upgrades) and
    /// preserving every user-owned entry and unrelated setting.
    static func mergedSettings(existing: [String: Any], port: UInt16) -> [String: Any] {
        var settings = existing
        var hooks = settings["hooks"] as? [String: Any] ?? [:]

        for event in subscribedEvents {
            var groups = (hooks[event] as? [[String: Any]]) ?? []
            groups.removeAll { ownsGroup($0) }
            groups.append(matcherGroup(event: event, port: port))
            hooks[event] = groups
        }

        settings["hooks"] = hooks
        return mergedEnv(existing: settings, titleMarkersEnabled: true)
    }

    /// Removes only our entries; drops event arrays that become empty.
    static func strippedSettings(existing: [String: Any]) -> [String: Any] {
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
        settings = settings.compactMapValues { $0 }
        return settings
    }

    /// Verifies an installed settings dict covers all events on `port`.
    static func installState(settings: [String: Any], port: UInt16) -> AdapterStatus {
        guard let hooks = settings["hooks"] as? [String: Any] else { return .needsSetup }
        var ownedEvents = 0
        var portMismatch = false
        let expectedURL = "127.0.0.1:\(port)/hook/claude"

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
