import Foundation

/// What one subagent is doing right now, read from its own transcript.
struct SubagentActivity: Equatable, Sendable {
    /// The spawning tool-use id — how a `SubagentRow` is keyed.
    var toolUseID: String
    /// The CLI's handle for the run; `SubagentStop` reports this, not the
    /// tool-use id.
    var agentID: String
    var label: String?
    /// "Grep: handleRequest" — the agent's current tool call.
    var detail: String?
}

/// Claude Code writes each subagent's transcript next to its parent session:
///
///     ~/.claude/projects/<project>/<session-id>/subagents/
///         agent-<agent-id>.jsonl        ← the agent's own turns
///         agent-<agent-id>.meta.json    ← {agentType, description, toolUseId}
///
/// Hook payloads for a subagent's inner tool calls carry no parent id, so this
/// is the only way to say what a specific agent is working on.
enum SubagentActivityReader {
    /// `sessionTranscriptPath` is the parent session's `.jsonl`.
    static func read(sessionTranscriptPath: String, tailBytes: Int = 65_536) -> [SubagentActivity] {
        let directory = URL(fileURLWithPath: sessionTranscriptPath)
            .deletingPathExtension()
            .appendingPathComponent("subagents", isDirectory: true)
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: directory.path) else {
            return []
        }

        return names
            .filter { $0.hasSuffix(".meta.json") }
            .compactMap { name in
                activity(metaName: name, directory: directory, tailBytes: tailBytes)
            }
    }

    private static func activity(
        metaName: String,
        directory: URL,
        tailBytes: Int
    ) -> SubagentActivity? {
        let metaURL = directory.appendingPathComponent(metaName)
        guard let data = try? Data(contentsOf: metaURL),
              let meta = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let toolUseID = meta["toolUseId"] as? String
        else {
            return nil
        }

        // "agent-<id>.meta.json" → "<id>". Strip the prefix and suffix once,
        // never every occurrence — an id may contain the prefix itself.
        let prefix = "agent-"
        let suffix = ".meta.json"
        guard metaName.hasPrefix(prefix), metaName.hasSuffix(suffix) else { return nil }
        let agentID = String(metaName.dropFirst(prefix.count).dropLast(suffix.count))
        guard !agentID.isEmpty else { return nil }

        let transcript = directory.appendingPathComponent("agent-\(agentID).jsonl")
        return SubagentActivity(
            toolUseID: toolUseID,
            agentID: agentID,
            label: label(from: meta),
            detail: lastToolCall(atPath: transcript.path, tailBytes: tailBytes)
        )
    }

    private static func label(from meta: [String: Any]) -> String? {
        let description = meta["description"] as? String
        guard let type = meta["agentType"] as? String, !type.isEmpty else { return description }
        guard let description, !description.isEmpty else { return type.capitalized }
        return "\(type.capitalized) (\(description))"
    }

    /// The most recent `tool_use` in the agent's transcript, as "Tool: detail".
    private static func lastToolCall(atPath path: String, tailBytes: Int) -> String? {
        guard let handle = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? handle.close() }
        guard let size = try? handle.seekToEnd(), size > 0 else { return nil }
        let start = size > UInt64(tailBytes) ? size - UInt64(tailBytes) : 0
        try? handle.seek(toOffset: start)
        guard let data = try? handle.readToEnd(), !data.isEmpty else { return nil }

        for line in data.split(separator: UInt8(ascii: "\n")).reversed() {
            guard let object = try? JSONSerialization.jsonObject(with: Data(line)),
                  let json = object as? [String: Any],
                  let message = json["message"] as? [String: Any],
                  let content = message["content"] as? [[String: Any]]
            else {
                continue
            }
            for block in content.reversed() where (block["type"] as? String) == "tool_use" {
                guard let name = block["name"] as? String else { continue }
                let input = (block["input"] as? [String: Any]) ?? [:]
                guard let detail = summarize(input) else { return name }
                return "\(name): \(detail)"
            }
        }
        return nil
    }

    /// One short phrase per tool call, in the same spirit as the session's own
    /// activity line: a file name, a command, a pattern.
    private static func summarize(_ input: [String: Any]) -> String? {
        if let path = input["file_path"] as? String ?? input["notebook_path"] as? String {
            return URL(fileURLWithPath: path).lastPathComponent
        }
        for key in ["command", "pattern", "query", "url", "prompt", "description"] {
            if let value = input[key] as? String, !value.isEmpty {
                return SessionReducer.condense(value, limit: 42)
            }
        }
        return nil
    }
}
