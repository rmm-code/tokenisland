import Foundation

/// Decodes raw CLI hook payloads (JSON on the request body) into normalized
/// `SessionEvent`s. Claude Code is the reference dialect; other CLIs land
/// here later via their own paths.
enum HookRouter {
    enum DecodeError: Error {
        case notJSON
        case missingSessionID
        case unknownEvent(String)
    }

    /// Terminal hints are forwarded by the hook command as HTTP headers so
    /// the JSON body stays exactly what the CLI emitted.
    static func terminalHint(fromHeaders headers: [String: String]) -> TerminalHint? {
        func header(_ name: String) -> String? {
            for (key, value) in headers where key.caseInsensitiveCompare(name) == .orderedSame {
                let trimmed = value.trimmingCharacters(in: .whitespaces)
                return trimmed.isEmpty ? nil : trimmed
            }
            return nil
        }
        let program = header("X-TI-Term")
        let termSession = header("X-TI-Term-Session")
        let tty = header("X-TI-TTY")
        if program == nil, termSession == nil, tty == nil { return nil }
        return TerminalHint(termProgram: program, termSessionID: termSession, ttyPath: tty)
    }

    static func decodeClaudeEvent(
        body: Data,
        headers: [String: String],
        timestamp: Date = Date()
    ) throws -> SessionEvent {
        guard let object = try? JSONSerialization.jsonObject(with: body),
              let json = object as? [String: Any] else {
            throw DecodeError.notJSON
        }
        guard let sessionID = json["session_id"] as? String, !sessionID.isEmpty else {
            throw DecodeError.missingSessionID
        }
        let eventName = (json["hook_event_name"] as? String) ?? ""

        let context = SessionEventContext(
            sessionID: sessionID,
            agent: .claude,
            cwd: json["cwd"] as? String,
            transcriptPath: json["transcript_path"] as? String,
            terminalHint: terminalHint(fromHeaders: headers),
            permissionMode: json["permission_mode"] as? String,
            timestamp: timestamp
        )

        let kind: SessionEventKind
        switch eventName {
        case "SessionStart":
            kind = .sessionStart(source: json["source"] as? String)
        case "UserPromptSubmit":
            kind = .userPrompt(prompt: json["prompt"] as? String)
        case "PreToolUse":
            let toolName = (json["tool_name"] as? String) ?? "Tool"
            let toolInput = json["tool_input"] as? [String: Any] ?? [:]
            if toolName == "AskUserQuestion", let question = questionKind(toolInput: toolInput) {
                kind = question
            } else {
                kind = .preTool(
                    toolName: toolName,
                    detail: activityDetail(toolName: toolName, toolInput: toolInput, cwd: context.cwd),
                    toolUseID: json["tool_use_id"] as? String,
                    subagentLabel: subagentLabel(toolName: toolName, toolInput: toolInput)
                )
            }
        case "PermissionRequest":
            let toolName = (json["tool_name"] as? String) ?? "Tool"
            let toolInput = json["tool_input"] as? [String: Any] ?? [:]
            let detail = activityDetail(toolName: toolName, toolInput: toolInput, cwd: context.cwd)
            kind = .permissionRequest(
                toolName: toolName,
                detail: detail,
                toolUseID: json["tool_use_id"] as? String,
                preview: toolPreview(
                    toolName: toolName,
                    toolInput: toolInput,
                    cwd: context.cwd,
                    detail: detail
                )
            )
        case "PostToolUse":
            kind = .postTool(
                toolName: (json["tool_name"] as? String) ?? "Tool",
                toolUseID: json["tool_use_id"] as? String,
                asyncAgentID: asyncAgentID(toolResponse: json["tool_response"])
            )
        case "Notification":
            let message = json["message"] as? String
            kind = .notification(
                message: message,
                category: category(
                    forType: json["notification_type"] as? String,
                    message: message
                )
            )
        case "Stop":
            kind = .stop(lastAssistantMessage: json["last_assistant_message"] as? String)
        case "StopFailure":
            kind = .stopFailure(message: json["error"] as? String ?? json["message"] as? String)
        case "SubagentStop":
            kind = .subagentStop(agentID: json["agent_id"] as? String)
        case "PreCompact":
            kind = .preCompact
        case "SessionEnd":
            kind = .sessionEnd(reason: json["reason"] as? String)
        default:
            throw DecodeError.unknownEvent(eventName)
        }
        return SessionEvent(context: context, kind: kind)
    }

    // MARK: - Detail extraction

    /// Shortens an absolute path against the session cwd (or $HOME).
    static func compactPath(_ raw: String, cwd: String?) -> String {
        var path = raw
        if let cwd, !cwd.isEmpty, path.hasPrefix(cwd + "/") {
            path = String(path.dropFirst(cwd.count + 1))
        } else if let home = ProcessInfo.processInfo.environment["HOME"], path.hasPrefix(home) {
            path = "~" + path.dropFirst(home.count)
        }
        return path
    }

    /// Builds the card activity line ("Read src/db/queries.ts").
    static func activityDetail(
        toolName: String,
        toolInput: [String: Any],
        cwd: String?
    ) -> String? {
        switch toolName {
        case "Read", "Edit", "Write", "NotebookEdit":
            if let path = toolInput["file_path"] as? String { return compactPath(path, cwd: cwd) }
        case "Bash":
            if let command = toolInput["command"] as? String {
                return SessionReducer.condense(command, limit: 70)
            }
        case "Glob", "Grep":
            if let pattern = toolInput["pattern"] as? String { return pattern }
        case "WebFetch":
            if let url = toolInput["url"] as? String { return url }
        case "WebSearch":
            if let query = toolInput["query"] as? String { return query }
        case "Task":
            if let description = toolInput["description"] as? String { return description }
        default:
            break
        }
        return nil
    }

    /// Builds the structured tool preview shown inside an approval card:
    /// full Bash command, Edit/MultiEdit diff, or Write content. Falls back
    /// to `.generic(detail)` for other tools so the card always has context.
    static func toolPreview(
        toolName: String,
        toolInput: [String: Any],
        cwd: String?,
        detail: String?
    ) -> ToolCallPreview? {
        func cap(_ text: String, _ limit: Int) -> String {
            guard text.count > limit else { return text }
            return String(text.prefix(limit)) + "…"
        }
        func editDiff(path: String, edit: [String: Any]) -> ToolCallPreview {
            ToolCallPreview(kind: .editDiff(
                path: compactPath(path, cwd: cwd),
                old: cap(edit["old_string"] as? String ?? "", 400),
                new: cap(edit["new_string"] as? String ?? "", 400)
            ))
        }

        switch toolName {
        case "Bash":
            if let command = toolInput["command"] as? String, !command.isEmpty {
                return ToolCallPreview(kind: .bashCommand(cap(command, 600)))
            }
        case "Edit":
            if let path = toolInput["file_path"] as? String {
                return editDiff(path: path, edit: toolInput)
            }
        case "MultiEdit":
            if let path = toolInput["file_path"] as? String,
               let first = (toolInput["edits"] as? [[String: Any]])?.first {
                return editDiff(path: path, edit: first)
            }
        case "Write":
            if let path = toolInput["file_path"] as? String {
                return ToolCallPreview(kind: .writeFile(
                    path: compactPath(path, cwd: cwd),
                    content: cap(toolInput["content"] as? String ?? "", 400)
                ))
            }
        default:
            break
        }
        if let detail, !detail.isEmpty {
            return ToolCallPreview(kind: .generic(detail))
        }
        return nil
    }

    /// Extracts the first question + option labels (cap 9 for ⌃1–9) from an
    /// `AskUserQuestion` tool_input. Defensive: any missing field returns nil
    /// so the event falls back to a plain `.preTool`.
    static func questionKind(toolInput: [String: Any]) -> SessionEventKind? {
        guard let questions = toolInput["questions"] as? [[String: Any]],
              let first = questions.first,
              let text = first["question"] as? String,
              !text.isEmpty
        else { return nil }
        let options = ((first["options"] as? [[String: Any]]) ?? [])
            .compactMap { $0["label"] as? String }
            .filter { !$0.isEmpty }
        return .question(text: text, options: Array(options.prefix(9)))
    }

    /// A background subagent spawn returns from its tool call the moment it is
    /// launched (`status: "async_launched"`), carrying the agent's own id. Read
    /// naively that reads as "the agent finished" a second after it started.
    private static func asyncAgentID(toolResponse: Any?) -> String? {
        guard let response = toolResponse as? [String: Any],
              let agentID = response["agentId"] as? String ?? response["agent_id"] as? String
        else {
            return nil
        }
        let isAsync = (response["isAsync"] as? Bool) == true
            || (response["status"] as? String) == "async_launched"
        return isAsync ? agentID : nil
    }

    /// Claude Code's fan-out tool is `Agent` on current builds and `Task` on
    /// older ones (and in forks) — keyed to only one of them, no subagent ever
    /// registered.
    private static func subagentLabel(toolName: String, toolInput: [String: Any]) -> String? {
        guard toolName == "Agent" || toolName == "Task" else { return nil }
        let description = (toolInput["description"] as? String) ?? "Subagent"
        if let type = toolInput["subagent_type"] as? String, !type.isEmpty {
            return "\(type.capitalized) (\(description))"
        }
        return description
    }

    /// Prefers the typed `notification_type` field (current Claude Code);
    /// falls back to message heuristics for older payloads.
    static func category(forType type: String?, message: String?) -> SessionNotificationCategory {
        switch type {
        case "permission_prompt":
            return .permission
        case "idle_prompt":
            return .idle
        case "agent_needs_input", "elicitation_dialog":
            return .other
        case "auth_success", "elicitation_complete", "elicitation_response", "agent_completed":
            return .idle
        default:
            break
        }
        guard let message = message?.lowercased() else { return .other }
        if message.contains("permission") || message.contains("approval") {
            return .permission
        }
        if message.contains("waiting for your input") || message.contains("idle") {
            return .idle
        }
        return .other
    }
}
