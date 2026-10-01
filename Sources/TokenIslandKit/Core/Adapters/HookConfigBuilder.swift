import Foundation

/// Shared command transport, ownership, migration, and health checks. Each
/// CLI's event roster and configuration shape come from its dialect profile.
enum HookConfigBuilder {
    /// Marker embedded in every command we install; identifies our entries for
    /// idempotent re-install and clean uninstall, and keeps us from ever
    /// touching another app's entries in a shared file.
    static let ownershipMarker = "#tokenisland-hook"

    /// Claude-family events. Cursor and Gemini use separate dialect rosters.
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

    /// Reads the hook JSON from stdin, resolves the controlling terminal,
    /// POSTs to the hook server and echoes the reply (so the server can return
    /// title markers and permission decisions). Fail-open output/exit behavior
    /// follows each CLI's contract when the app is not running.
    static func command(source: String, port: UInt16, curlTimeout: Int) -> String {
        let url = "http://127.0.0.1:\(port)/hook/\(source)"
        let transport = #"""
        curl -sf -m \#(curlTimeout) --connect-timeout 1 -X POST "\#(url)" -H "Content-Type: application/json" -H "X-TI-Term: ${TERM_PROGRAM:-}" -H "X-TI-Term-Session: ${TERM_SESSION_ID:-}" -H "X-TI-TTY: ${TI_TTY:+/dev/$TI_TTY}" --data-binary @- 2>/dev/null
        """#
        let tty = "TI_TTY=$(ps -o tty= -p $$ 2>/dev/null | tr -d ' '); "
        // Cursor blocks a successful hook with invalid/partial JSON. A
        // transport failure must exit nonzero (other than 2), not `|| true`.
        if HookFamilyCLI.dialect(forSource: source) == .cursor {
            return tty + "TI_REPLY=$(\(transport)) || exit 3; [ -n \"$TI_REPLY\" ] || exit 3; printf '%s' \"$TI_REPLY\" \(ownershipMarker)"
        }
        return tty + transport + " || true \(ownershipMarker)"
    }

    /// PermissionRequest gets long timeouts so a notch approval can be parked;
    /// everything else stays fast and fire-and-forget.
    static func matcherGroup(event: String, source: String, port: UInt16) -> [String: Any] {
        HookDialectConfiguration.entry(event: event, source: source, port: port)
    }

    static func ownsCommand(_ descriptor: [String: Any]) -> Bool {
        (descriptor["command"] as? String)?.contains(ownershipMarker) == true
    }

    static func ownsGroup(_ group: [String: Any]) -> Bool {
        guard let hooks = group["hooks"] as? [[String: Any]] else { return false }
        return !hooks.isEmpty && hooks.allSatisfy(ownsCommand)
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
        // Strip our commands across ALL events first, including a previous
        // release's wrong dialect names. Preserve foreign entries verbatim.
        var settings = stripped(existing: existing)
        var hooks = settings["hooks"] as? [String: Any] ?? [:]
        let dialect = HookFamilyCLI.dialect(forSource: source) ?? .claude
        for event in HookDialectConfiguration.events(for: dialect) {
            var groups = (hooks[event] as? [[String: Any]]) ?? []
            groups.append(matcherGroup(event: event, source: source, port: port))
            hooks[event] = groups
        }
        settings["hooks"] = hooks
        if dialect == .cursor, settings["version"] == nil { settings["version"] = 1 }

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
            guard let entries = value as? [[String: Any]] else { continue }
            let groups = entries.compactMap { entry -> [String: Any]? in
                if ownsCommand(entry) { return nil } // Cursor's flat entries
                guard let commands = entry["hooks"] as? [[String: Any]],
                      commands.contains(where: ownsCommand)
                else { return entry }
                let remaining = commands.filter { !ownsCommand($0) }
                guard !remaining.isEmpty else { return nil }
                var preserved = entry
                preserved["hooks"] = remaining
                return preserved
            }
            if groups.isEmpty {
                hooks.removeValue(forKey: event)
            } else {
                hooks[event] = groups
            }
        }

        settings["hooks"] = hooks.isEmpty ? nil : hooks
        return settings
    }

    /// Verifies an installed config covers all events on `port`.
    /// Approval-answering hooks in this config that are not ours.
    ///
    /// Only one app may answer a `PermissionRequest`: whoever replies first
    /// decides, and a second monitor either races us or (if it exits without
    /// output) makes the event look unanswered. Silent, and it presents as
    /// "I pressed Allow and nothing happened", so it is worth surfacing rather
    /// than leaving people to find it in a config file.
    ///
    /// Returns a short identifier per foreign hook — the command's first path-
    /// looking token, or a trimmed prefix — never the whole command line.
    static func foreignApprovalHooks(settings: [String: Any], source: String = "claude") -> [String] {
        guard let hooks = settings["hooks"] as? [String: Any] else { return [] }
        let dialect = HookFamilyCLI.dialect(forSource: source) ?? .claude
        return HookDialectConfiguration.events(for: dialect)
            .filter { HookDialectConfiguration.holdsApproval(event: $0, dialect: dialect) }
            .flatMap { hooks[$0] as? [[String: Any]] ?? [] }
            .flatMap { ($0["hooks"] as? [[String: Any]]) ?? [$0] }
            .filter { !ownsCommand($0) }
            .compactMap { $0["command"] as? String }
            .map(summarize(command:))
    }

    /// Shell wrappers a hook is usually invoked through. Naming these instead
    /// of the tool they launch ("sh" rather than "vibe-island-bridge") tells
    /// the user nothing about which app to go turn off.
    private static let wrapperBinaries: Set<String> = [
        "sh", "bash", "zsh", "env", "sudo", "nohup", "exec", "node", "python",
        "python3", "npx", "caffeinate"
    ]

    /// Best-effort short name for a foreign hook command.
    private static func summarize(command: String) -> String {
        let names = command
            .split(whereSeparator: { " \t\n\"'".contains($0) })
            .map(String.init)
            .filter { $0.contains("/") }
            .map { ($0 as NSString).lastPathComponent }
            .filter { !$0.isEmpty }

        if let meaningful = names.first(where: { !wrapperBinaries.contains($0) }) {
            return meaningful
        }
        return names.first ?? String(command.prefix(40))
    }

    static func installState(
        settings: [String: Any],
        source: String,
        port: UInt16
    ) -> AdapterStatus {
        guard let hooks = settings["hooks"] as? [String: Any] else { return .needsSetup }
        var ownedEvents = 0
        var portMismatch = false
        let expectedURL = "127.0.0.1:\(port)/hook/\(source)"

        let dialect = HookFamilyCLI.dialect(forSource: source) ?? .claude
        let events = HookDialectConfiguration.events(for: dialect)
        for event in events {
            guard let groups = hooks[event] as? [[String: Any]] else { continue }
            let descriptors = groups.flatMap { ($0["hooks"] as? [[String: Any]]) ?? [$0] }
            let owned = descriptors.filter(ownsCommand)
            guard !owned.isEmpty else { continue }
            ownedEvents += 1
            let matchesPort = owned.contains { ($0["command"] as? String)?.contains(expectedURL) == true }
            if !matchesPort { portMismatch = true }
        }

        if ownedEvents == 0 { return .needsSetup }
        if portMismatch { return .needsRepair("Hook port changed — reinstall") }
        if ownedEvents < events.count {
            return .needsRepair("Missing \(events.count - ownedEvents) hook event(s)")
        }
        // Commands/timeouts/schema change on upgrades even when the port and
        // event roster stay the same. Compare our descriptor with today's one.
        for event in events {
            let expected = matcherGroup(event: event, source: source, port: port)
            let installed = hooks[event] as? [[String: Any]] ?? []
            let hasCurrent = installed.contains { entry in
                if dialect == .cursor { return NSDictionary(dictionary: entry).isEqual(to: expected) }
                guard let commands = entry["hooks"] as? [[String: Any]],
                      let expectedCommands = expected["hooks"] as? [[String: Any]],
                      commands.contains(where: { NSDictionary(dictionary: $0).isEqual(to: expectedCommands[0]) })
                else { return false }
                return (entry["matcher"] as? String) == (expected["matcher"] as? String)
            }
            if !hasCurrent { return .needsRepair("Hook configuration needs an update") }
        }
        return .active
    }
}
