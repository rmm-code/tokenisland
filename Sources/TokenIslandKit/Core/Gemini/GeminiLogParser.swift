import Foundation

/// Role of one recorded Gemini CLI message.
enum GeminiMessageRole: Equatable, Sendable {
    case user
    case model
    /// Info/error/system entries — kept for ordering, never emitted.
    case other
}

/// One tool invocation recorded on a model message.
struct GeminiToolCall: Equatable, Sendable {
    var name: String
    var detail: String?
    /// Whether the call has finished (success/error/cancelled). Calls without
    /// a status were recorded after completion and count as terminal.
    var isTerminal: Bool
}

struct GeminiMessage: Equatable, Sendable {
    var role: GeminiMessageRole
    var text: String?
    var timestamp: Date?
    var model: String? = nil
    var toolCalls: [GeminiToolCall] = []
}

/// A parsed chats-file document (`~/.gemini/tmp/<hash>/chats/*.json`):
/// either a ChatRecordingService conversation record or a `/chat save`
/// checkpoint (a bare Gemini API history array).
struct GeminiSessionRecord: Equatable, Sendable {
    var sessionID: String?
    /// Gemini CLI keys project dirs by sha256(cwd) and does not store the
    /// path itself; this is only set if a future CLI version adds one.
    var cwd: String?
    var lastUpdated: Date?
    var messages: [GeminiMessage]
}

/// One user-prompt entry of a per-project `logs.json` array.
struct GeminiPromptEntry: Equatable, Sendable {
    var sessionID: String
    var text: String
    var timestamp: Date?
}

/// Parses Gemini CLI on-disk session artifacts. Shapes move between CLI
/// versions — parsing is defensive and unknown data yields nil/empty
/// (same posture as `CodexRolloutParser`).
enum GeminiLogParser {
    /// Non-terminal tool-call statuses seen in Gemini CLI's scheduler.
    private static let openToolStatuses: Set<String> = [
        "executing", "awaiting_approval", "scheduled", "validating", "pending", "confirming"
    ]

    // MARK: - chats/*.json

    static func sessionRecord(fromChatData data: Data) -> GeminiSessionRecord? {
        guard let object = try? JSONSerialization.jsonObject(with: data) else { return nil }

        if let dict = object as? [String: Any] {
            guard let rawMessages = dict["messages"] as? [[String: Any]] else { return nil }
            return GeminiSessionRecord(
                sessionID: dict["sessionId"] as? String,
                cwd: firstString(
                    in: dict,
                    keys: ["cwd", "projectRoot", "projectPath", "workspaceDir", "workingDirectory"]
                ),
                lastUpdated: date(from: dict["lastUpdated"]),
                messages: rawMessages.compactMap(recordedMessage(from:))
            )
        }
        // `/chat save` checkpoints are a bare Gemini API history array.
        if let history = object as? [[String: Any]] {
            let messages = history.compactMap(historyMessage(from:))
            return messages.isEmpty
                ? nil
                : GeminiSessionRecord(sessionID: nil, cwd: nil, lastUpdated: nil, messages: messages)
        }
        return nil
    }

    /// ChatRecordingService message: {id, timestamp, type: "user"|"gemini",
    /// content, model?, tokens?, toolCalls?}.
    private static func recordedMessage(from dict: [String: Any]) -> GeminiMessage? {
        let type = (dict["type"] as? String)?.lowercased() ?? ""
        let role: GeminiMessageRole = switch type {
        case "user": .user
        case "gemini", "model", "assistant": .model
        default: .other
        }
        let toolCalls = (dict["toolCalls"] as? [[String: Any]] ?? []).map(toolCall(from:))
        return GeminiMessage(
            role: role,
            text: contentText(dict["content"]),
            timestamp: date(from: dict["timestamp"]),
            model: firstString(in: dict, keys: ["model", "modelId", "modelName"]),
            toolCalls: toolCalls
        )
    }

    /// Checkpoint history entry: {role: "user"|"model", parts: [{text} |
    /// {functionCall} | {functionResponse}]}. Tool responses ride user-role
    /// entries in the Gemini API — those are not real prompts.
    private static func historyMessage(from dict: [String: Any]) -> GeminiMessage? {
        guard let role = dict["role"] as? String else { return nil }
        let parts = dict["parts"] as? [[String: Any]] ?? []
        let text = parts.compactMap { $0["text"] as? String }.joined(separator: "\n")
        let toolCalls = parts.compactMap { part -> GeminiToolCall? in
            guard let call = part["functionCall"] as? [String: Any] else { return nil }
            return GeminiToolCall(
                name: call["name"] as? String ?? "tool",
                detail: detail(fromArgs: call["args"]),
                isTerminal: true
            )
        }
        var mapped: GeminiMessageRole = switch role {
        case "user": .user
        case "model": .model
        default: .other
        }
        if mapped == .user, text.isEmpty { mapped = .other } // functionResponse carrier
        return GeminiMessage(role: mapped, text: text.isEmpty ? nil : text, timestamp: nil, toolCalls: toolCalls)
    }

    private static func toolCall(from dict: [String: Any]) -> GeminiToolCall {
        let status = (dict["status"] as? String)?.lowercased()
        return GeminiToolCall(
            name: dict["name"] as? String ?? dict["toolName"] as? String ?? "tool",
            detail: detail(fromArgs: dict["args"]),
            isTerminal: status.map { !openToolStatuses.contains($0) } ?? true
        )
    }

    // MARK: - logs.json

    /// Per-project prompt history: a JSON array of {sessionId, messageId,
    /// type: "user", message, timestamp}. User side only — no responses.
    static func promptEntries(fromLogsData data: Data) -> [GeminiPromptEntry] {
        guard let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return []
        }
        return array.compactMap { entry in
            guard let sessionID = entry["sessionId"] as? String, !sessionID.isEmpty,
                  (entry["type"] as? String ?? "user").lowercased() == "user",
                  let message = entry["message"] as? String
            else { return nil }
            let text = message.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            return GeminiPromptEntry(sessionID: sessionID, text: text, timestamp: date(from: entry["timestamp"]))
        }
    }

    // MARK: - Shared helpers

    /// Content is a plain string or an array of {text} blocks.
    private static func contentText(_ value: Any?) -> String? {
        if let string = value as? String {
            return string.isEmpty ? nil : string
        }
        guard let items = value as? [[String: Any]] else { return nil }
        let joined = items.compactMap { $0["text"] as? String }.joined(separator: "\n")
        return joined.isEmpty ? nil : joined
    }

    /// Short human-readable summary of a tool call's arguments.
    private static func detail(fromArgs value: Any?) -> String? {
        guard let args = value as? [String: Any] else { return nil }
        let preferredKeys = [
            "command", "file_path", "absolute_path", "path", "prompt",
            "query", "url", "pattern", "description"
        ]
        for key in preferredKeys {
            if let string = args[key] as? String, !string.isEmpty {
                return String(string.prefix(120))
            }
        }
        return nil
    }

    private static func firstString(in dict: [String: Any], keys: [String]) -> String? {
        for key in keys {
            if let value = dict[key] as? String, !value.isEmpty { return value }
        }
        return nil
    }

    private static func date(from value: Any?) -> Date? {
        if let string = value as? String {
            return fractionalTimestampFormatter.date(from: string)
                ?? plainTimestampFormatter.date(from: string)
        }
        if let number = value as? Double {
            // Epoch milliseconds vs seconds.
            return Date(timeIntervalSince1970: number > 1e12 ? number / 1000 : number)
        }
        return nil
    }

    // ISO8601DateFormatter is documented thread-safe.
    private nonisolated(unsafe) static let fractionalTimestampFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
    private nonisolated(unsafe) static let plainTimestampFormatter = ISO8601DateFormatter()
}
