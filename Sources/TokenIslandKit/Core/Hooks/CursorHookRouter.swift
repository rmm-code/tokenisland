import Foundation

/// Decodes Cursor's hook payloads. Cursor splits what Claude Code calls
/// `PreToolUse` across `preToolUse`, `beforeShellExecution` and
/// `beforeMCPExecution`, answers approvals with `permission` rather than
/// `hookSpecificOutput`, and identifies the session with `conversation_id`.
/// Field names follow Cursor's published hooks reference.
enum CursorHookRouter {
    static func decode(
        body: Data,
        headers: [String: String],
        timestamp: Date = Date()
    ) throws -> SessionEvent {
        guard let object = try? JSONSerialization.jsonObject(with: body),
              let json = object as? [String: Any]
        else {
            throw HookRouter.DecodeError.notJSON
        }
        // `session_id` on agent hooks, `conversation_id` on every payload.
        guard let sessionID = (json["session_id"] as? String) ?? (json["conversation_id"] as? String),
              !sessionID.isEmpty
        else {
            throw HookRouter.DecodeError.missingSessionID
        }

        let context = SessionEventContext(
            sessionID: sessionID,
            agent: .cursor,
            cwd: workspace(from: json),
            transcriptPath: json["transcript_path"] as? String,
            terminalHint: HookRouter.terminalHint(fromHeaders: headers),
            timestamp: timestamp
        )
        return SessionEvent(context: context, kind: kind(from: json))
    }

    /// Cursor reports the workspace as an array of roots.
    private static func workspace(from json: [String: Any]) -> String? {
        if let cwd = json["cwd"] as? String, !cwd.isEmpty { return cwd }
        return (json["workspace_roots"] as? [String])?.first
    }

    private static func kind(from json: [String: Any]) -> SessionEventKind {
        let event = (json["hook_event_name"] as? String) ?? ""
        let toolInput = json["tool_input"] as? [String: Any] ?? [:]

        switch event {
        case "sessionStart":
            return .sessionStart(source: json["composer_mode"] as? String)

        case "sessionEnd":
            return .sessionEnd(reason: json["reason"] as? String)

        case "beforeSubmitPrompt":
            return .userPrompt(prompt: json["prompt"] as? String)

        case "preToolUse":
            return .preTool(
                toolName: (json["tool_name"] as? String) ?? "Tool",
                detail: HookRouter.activityDetail(toolName: (json["tool_name"] as? String) ?? "Tool", toolInput: toolInput, cwd: nil),
                toolUseID: json["tool_use_id"] as? String,
                subagentLabel: nil
            )

        case "postToolUse":
            return .postTool(
                toolName: (json["tool_name"] as? String) ?? "Tool",
                toolUseID: json["tool_use_id"] as? String
            )

        case "postToolUseFailure":
            return .stopFailure(message: json["error_message"] as? String)

        // Cursor asks separately for shell and MCP calls; both are approvals.
        case "beforeShellExecution":
            let command = (json["command"] as? String) ?? ""
            return .permissionRequest(
                toolName: "Shell",
                detail: SessionReducer.condense(command, limit: 80),
                toolUseID: json["tool_use_id"] as? String,
                preview: command.isEmpty ? nil : ToolCallPreview(kind: .bashCommand(command))
            )

        case "beforeMCPExecution":
            let name = (json["tool_name"] as? String) ?? "MCP tool"
            return .permissionRequest(
                toolName: name,
                detail: HookRouter.activityDetail(toolName: name, toolInput: toolInput, cwd: nil),
                toolUseID: json["tool_use_id"] as? String,
                preview: nil
            )

        case "beforeReadFile":
            return .permissionRequest(
                toolName: "Read",
                detail: (json["file_path"] as? String).map {
                    URL(fileURLWithPath: $0).lastPathComponent
                },
                toolUseID: nil,
                preview: nil
            )

        case "subagentStart":
            let type = (json["subagent_type"] as? String) ?? "Subagent"
            let task = (json["task"] as? String) ?? (json["description"] as? String)
            let label = task.map { "\(type.capitalized) (\(SessionReducer.condense($0, limit: 48)))" }
            return .preTool(
                toolName: "Agent",
                detail: nil,
                toolUseID: (json["tool_call_id"] as? String) ?? (json["subagent_id"] as? String),
                subagentLabel: label ?? type.capitalized
            )

        case "subagentStop":
            // No id in this payload — the reducer settles it only when a
            // single agent is in flight.
            return .subagentStop(agentID: json["subagent_id"] as? String)

        case "afterAgentResponse":
            return .assistantMessage(text: json["text"] as? String)

        case "stop":
            return .stop(lastAssistantMessage: nil)

        case "preCompact":
            return .preCompact

        default:
            // afterShellExecution, afterMCPExecution, afterFileEdit,
            // afterAgentThought and the Tab hooks carry no session state we
            // render; treat them as a liveness ping.
            return .notification(message: nil, category: .other)
        }
    }

    /// Cursor expects `{"permission": "allow"|"deny"}` on stdout.
    static func permissionResponse(_ decision: ApprovalDecision, reason: String) -> String? {
        switch decision {
        case .passthrough:
            return nil
        case .allow, .deny:
            let payload: [String: Any] = [
                "permission": decision.rawValue,
                "agent_message": reason
            ]
            guard let data = try? JSONSerialization.data(withJSONObject: payload) else { return nil }
            return String(data: data, encoding: .utf8)
        }
    }
}
