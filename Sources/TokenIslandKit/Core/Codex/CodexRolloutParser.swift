import Foundation

/// One recognized line of a Codex rollout file, reduced to what the
/// session watcher needs.
/// What a rollout file *is*. Codex writes one file per thread, and most of
/// them are not user conversations: a fan-out subagent gets its own rollout
/// (`source.subagent.thread_spawn`), and so does every internal safety worker
/// (`source.subagent.other = "guardian"`) — on this machine 104 of 197 files.
struct CodexThreadInfo: Equatable, Sendable {
    var isSubagent: Bool
    /// A guardian or other machinery thread — never a card, never a row.
    var isInternalWorker: Bool
    var parentThreadID: String?
    /// "Linnaeus" or the last component of `/root/backend_logic_audit`.
    var label: String?
}

enum CodexRolloutEvent: Equatable, Sendable {
    case sessionMeta(id: String?, cwd: String?, thread: CodexThreadInfo? = nil)
    case turnContext(cwd: String?, model: String?)
    case userMessage(text: String)
    case agentMessage(text: String)
    case taskStarted
    case taskComplete(lastAgentMessage: String?)
    /// Periodic usage heartbeat the CLI appends while a turn runs.
    case tokenCount
}

/// A parsed rollout line: the event plus the line's own timestamp
/// (rollouts are replayed at launch, so wall-clock "now" would be wrong).
struct CodexRolloutRecord: Equatable, Sendable {
    var timestamp: Date?
    var event: CodexRolloutEvent
}

/// Parses Codex CLI rollout JSONL (`~/.codex/sessions/**/rollout-*.jsonl`).
/// Line shapes move between Codex versions — parsing is defensive and
/// unknown lines yield nil (same posture as `CodexUsageReader`).
enum CodexRolloutParser {
    /// Parses a chunk of newline-delimited rollout data.
    static func records(fromLines data: Data) -> [CodexRolloutRecord] {
        data.split(separator: UInt8(ascii: "\n")).compactMap { record(fromLine: Data($0)) }
    }

    static func record(fromLine data: Data) -> CodexRolloutRecord? {
        guard data.count > 2,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let event = event(from: object)
        else { return nil }
        return CodexRolloutRecord(timestamp: date(from: object["timestamp"]), event: event)
    }

    /// Reads the thread's provenance out of `session_meta`. `source.subagent`
    /// discriminates a real fan-out (`thread_spawn`) from internal machinery
    /// (`other`); the spawn block is authoritative for the label and parent,
    /// with the top-level copies as fallback (absent in a third of the files).
    static func threadInfo(from meta: [String: Any]) -> CodexThreadInfo? {
        let subagentSource = (meta["source"] as? [String: Any])?["subagent"] as? [String: Any]
        let spawn = subagentSource?["thread_spawn"] as? [String: Any]
        let isInternal = subagentSource != nil && spawn == nil
        let isSubagent = (meta["thread_source"] as? String) == "subagent" || subagentSource != nil
        guard isSubagent else { return nil }

        let nickname = (spawn?["agent_nickname"] as? String) ?? (meta["agent_nickname"] as? String)
        let path = (spawn?["agent_path"] as? String) ?? (meta["agent_path"] as? String)
        let label = [nickname, path.map { URL(fileURLWithPath: $0).lastPathComponent }]
            .compactMap { $0 }
            .first { !$0.isEmpty }

        return CodexThreadInfo(
            isSubagent: true,
            isInternalWorker: isInternal,
            parentThreadID: (spawn?["parent_thread_id"] as? String)
                ?? (meta["parent_thread_id"] as? String),
            label: label
        )
    }

    // MARK: - Line dissection

    private static func event(from object: [String: Any]) -> CodexRolloutEvent? {
        let lineType = object["type"] as? String
        let payload = object["payload"] as? [String: Any] ?? object
        let payloadType = payload["type"] as? String ?? lineType

        switch payloadType {
        case "session_meta":
            // Meta fields sit in the payload directly, or one level deeper
            // ("session_meta"/"payload") on some versions.
            let meta = payload["session_meta"] as? [String: Any]
                ?? payload["payload"] as? [String: Any]
                ?? payload
            return .sessionMeta(
                id: meta["id"] as? String,
                cwd: meta["cwd"] as? String,
                thread: threadInfo(from: meta)
            )

        case "turn_context":
            let context = payload["turn_context"] as? [String: Any]
                ?? payload["payload"] as? [String: Any]
                ?? payload
            return .turnContext(
                cwd: context["cwd"] as? String,
                model: context["model"] as? String
            )

        case "user_message":
            guard let text = messageText(in: payload) else { return nil }
            return .userMessage(text: cleanedUserText(text))

        case "agent_message", "assistant":
            guard let text = messageText(in: payload) else { return nil }
            return .agentMessage(text: text)

        case "message":
            return responseItemMessage(payload)

        case "token_count":
            return .tokenCount

        case "task_started":
            return .taskStarted

        case "task_complete":
            return .taskComplete(lastAgentMessage: payload["last_agent_message"] as? String)

        default:
            // Very old rollouts write the meta object bare on the first line.
            if lineType == nil, let id = payload["id"] as? String, payload["cwd"] != nil {
                return .sessionMeta(id: id, cwd: payload["cwd"] as? String)
            }
            return nil
        }
    }

    /// `response_item` lines of type "message" carry role + content blocks.
    private static func responseItemMessage(_ payload: [String: Any]) -> CodexRolloutEvent? {
        guard let role = payload["role"] as? String,
              let text = contentText(payload["content"]),
              !text.isEmpty
        else { return nil }
        switch role {
        case "user":
            // Codex injects <user_instructions>/<environment_context> blocks
            // as user-role items — tag-wrapped payloads aren't real prompts.
            guard !text.hasPrefix("<") else { return nil }
            return .userMessage(text: cleanedUserText(text))
        case "assistant":
            return .agentMessage(text: text)
        default:
            return nil
        }
    }

    private static func messageText(in payload: [String: Any]) -> String? {
        if let message = payload["message"] as? String, !message.isEmpty { return message }
        if let text = payload["text"] as? String, !text.isEmpty { return text }
        return contentText(payload["content"])
    }

    /// Content is a plain string or an array of typed text blocks.
    private static func contentText(_ value: Any?) -> String? {
        if let string = value as? String { return string }
        guard let items = value as? [[String: Any]] else { return nil }
        let parts = items.compactMap { item -> String? in
            guard let type = item["type"] as? String else { return item["text"] as? String }
            guard type == "input_text" || type == "output_text" || type == "text" else { return nil }
            return item["text"] as? String
        }
        let joined = parts.joined(separator: "\n")
        return joined.isEmpty ? nil : joined
    }

    /// IDE-originated prompts wrap the actual request in setup context
    /// ("# Context from my IDE setup … ## My request for Codex: …").
    private static func cleanedUserText(_ text: String) -> String {
        if let range = text.range(of: "## My request for Codex:") {
            let request = text[range.upperBound...]
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !request.isEmpty { return request }
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func date(from value: Any?) -> Date? {
        guard let string = value as? String else { return nil }
        return fractionalTimestampFormatter.date(from: string)
            ?? plainTimestampFormatter.date(from: string)
    }

    // ISO8601DateFormatter is documented thread-safe.
    private nonisolated(unsafe) static let fractionalTimestampFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
    private nonisolated(unsafe) static let plainTimestampFormatter = ISO8601DateFormatter()
}
