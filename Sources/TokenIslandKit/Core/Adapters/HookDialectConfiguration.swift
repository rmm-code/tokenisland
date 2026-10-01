import Foundation

/// CLI configuration contracts. Transport and ownership are shared; event
/// names, entry nesting, matching, and timeout units belong to each dialect.
enum HookDialectConfiguration {
    static func events(for dialect: HookFamilyCLI.Dialect) -> [String] {
        switch dialect {
        case .claude:
            return HookConfigBuilder.subscribedEvents
        case .cursor:
            return [
                "sessionStart", "sessionEnd", "beforeSubmitPrompt", "preToolUse",
                "postToolUse", "postToolUseFailure", "beforeShellExecution",
                "beforeMCPExecution", "beforeReadFile", "subagentStart",
                "subagentStop", "afterAgentResponse", "stop", "preCompact"
            ]
        case .gemini:
            return ["SessionStart", "SessionEnd", "BeforeAgent", "AfterAgent",
                    "BeforeTool", "AfterTool", "Notification", "PreCompress"]
        }
    }

    static func holdsApproval(event: String, dialect: HookFamilyCLI.Dialect) -> Bool {
        switch dialect {
        case .claude: event == "PermissionRequest"
        // These are ordinary tool gates, not native permission-request
        // notifications. Monitoring must never park every Read/Shell call.
        case .cursor, .gemini: false
        }
    }

    static func entry(event: String, source: String, port: UInt16) -> [String: Any] {
        let dialect = HookFamilyCLI.dialect(forSource: source) ?? .claude
        let holding = holdsApproval(event: event, dialect: dialect)
        let timeoutSeconds = holding ? 95 : 8
        let descriptor: [String: Any] = [
            "type": "command",
            "command": HookConfigBuilder.command(source: source, port: port, curlTimeout: holding ? 90 : 5),
            "timeout": dialect == .gemini ? timeoutSeconds * 1000 : timeoutSeconds
        ]
        if dialect == .cursor { return descriptor }
        var group: [String: Any] = ["hooks": [descriptor]]
        if dialect == .gemini {
            if ["BeforeTool", "AfterTool", "Notification"].contains(event) { group["matcher"] = ".*" }
        } else if ["PreToolUse", "PostToolUse", "PermissionRequest", "Notification"].contains(event) {
            group["matcher"] = "*"
        }
        return group
    }
}
