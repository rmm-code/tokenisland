import Foundation

/// Decodes Gemini CLI's hook payloads. Same base fields as Claude Code
/// (`session_id`, `cwd`, `transcript_path`), but tool and turn events are
/// named `BeforeTool`/`AfterTool`/`BeforeAgent`/`AfterAgent`, and approvals
/// are answered with `decision` rather than `hookSpecificOutput`.
/// Field names follow Gemini CLI's published hooks reference.
enum GeminiHookRouter {
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
        guard let sessionID = json["session_id"] as? String, !sessionID.isEmpty else {
            throw HookRouter.DecodeError.missingSessionID
        }

        let context = SessionEventContext(
            sessionID: sessionID,
            agent: .gemini,
            cwd: json["cwd"] as? String,
            transcriptPath: json["transcript_path"] as? String,
            terminalHint: HookRouter.terminalHint(fromHeaders: headers),
            timestamp: timestamp
        )
        return SessionEvent(context: context, kind: kind(from: json))
    }

    private static func kind(from json: [String: Any]) -> SessionEventKind {
        let event = (json["hook_event_name"] as? String) ?? ""
        let toolName = json["tool_name"] as? String
        let toolInput = json["tool_input"] as? [String: Any] ?? [:]

        switch event {
        case "SessionStart":
            return .sessionStart(source: json["source"] as? String)

        case "SessionEnd":
            return .sessionEnd(reason: json["reason"] as? String)

        case "BeforeAgent":
            return .userPrompt(prompt: json["prompt"] as? String)

        case "AfterAgent":
            // The turn's final text — Gemini names it `prompt_response`.
            return .stop(lastAssistantMessage: json["prompt_response"] as? String)

        case "BeforeTool":
            // Gemini's only approval gate: answering `decision: "deny"` blocks
            // the call, so this doubles as the permission channel.
            return .permissionRequest(
                toolName: displayToolName(toolName),
                detail: HookRouter.activityDetail(toolName: toolName ?? "Tool", toolInput: toolInput, cwd: nil),
                toolUseID: json["tool_call_id"] as? String,
                preview: preview(toolName: toolName, toolInput: toolInput)
            )

        case "AfterTool":
            return .postTool(
                toolName: displayToolName(toolName),
                toolUseID: json["tool_call_id"] as? String
            )

        case "Notification":
            let message = json["message"] as? String
            return .notification(
                message: message,
                category: HookRouter.category(
                    forType: json["notification_type"] as? String,
                    message: message
                )
            )

        case "PreCompress", "PreCompact":
            return .preCompact

        default:
            return .notification(message: nil, category: .other)
        }
    }

    /// Gemini's tool names are snake_case (`run_shell_command`, `read_file`);
    /// the cards read better in the same shape as every other agent's.
    static func displayToolName(_ raw: String?) -> String {
        guard let raw, !raw.isEmpty else { return "Tool" }
        switch raw {
        case "run_shell_command": return "Bash"
        case "read_file", "read_many_files": return "Read"
        case "write_file": return "Write"
        case "replace", "edit": return "Edit"
        case "glob": return "Glob"
        case "search_file_content", "grep": return "Grep"
        case "google_web_search", "web_fetch": return "WebFetch"
        default:
            return raw
                .split(separator: "_")
                .map { $0.prefix(1).uppercased() + $0.dropFirst() }
                .joined()
        }
    }

    private static func preview(toolName: String?, toolInput: [String: Any]) -> ToolCallPreview? {
        if toolName == "run_shell_command", let command = toolInput["command"] as? String {
            return ToolCallPreview(kind: .bashCommand(command))
        }
        if toolName == "write_file",
           let path = toolInput["file_path"] as? String,
           let content = toolInput["content"] as? String {
            return ToolCallPreview(kind: .writeFile(path: path, content: content))
        }
        if toolName == "replace",
           let path = toolInput["file_path"] as? String,
           let old = toolInput["old_string"] as? String,
           let new = toolInput["new_string"] as? String {
            return ToolCallPreview(kind: .editDiff(path: path, old: old, new: new))
        }
        return nil
    }

    /// Gemini expects `{"decision": "allow"|"deny", "reason": …}` on stdout.
    static func permissionResponse(_ decision: ApprovalDecision, reason: String) -> String? {
        switch decision {
        case .passthrough:
            return nil
        case .allow, .deny:
            let payload: [String: Any] = ["decision": decision.rawValue, "reason": reason]
            guard let data = try? JSONSerialization.data(withJSONObject: payload) else { return nil }
            return String(data: data, encoding: .utf8)
        }
    }
}
