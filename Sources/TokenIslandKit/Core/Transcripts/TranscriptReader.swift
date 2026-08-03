import Foundation

/// Fields recoverable from a session transcript.
struct TranscriptDigest: Equatable, Sendable {
    var title: String?
    var lastUserPrompt: String?
    var lastAssistantText: String?
    var model: String?
}

/// Fallback reader for Claude Code transcript JSONL files. The format is
/// explicitly internal and version-dependent, so this parser is defensive:
/// it only extracts fields it can positively identify and returns nil-heavy
/// digests rather than guessing. Primary data (completion text) arrives via
/// the Stop hook's `last_assistant_message`; this reader fills gaps only.
enum TranscriptReader {
    /// Reads at most the trailing `maxBytes` of the file to stay cheap on
    /// long sessions.
    static func digest(atPath path: String, maxBytes: Int = 262_144) -> TranscriptDigest? {
        guard let handle = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? handle.close() }

        guard let size = try? handle.seekToEnd(), size > 0 else { return nil }
        let start = size > UInt64(maxBytes) ? size - UInt64(maxBytes) : 0
        try? handle.seek(toOffset: start)
        guard let data = try? handle.readToEnd(), !data.isEmpty else { return nil }

        var digest = TranscriptDigest()
        let lines = data.split(separator: UInt8(ascii: "\n"))

        for line in lines {
            guard let object = try? JSONSerialization.jsonObject(with: Data(line)),
                  let json = object as? [String: Any] else { continue }

            let type = json["type"] as? String

            // Current Claude Code writes small sidecar records once per turn.
            // They are the only reliable title source on a long session: the
            // conversation records in the tail are tool results, and a single
            // record can be larger than the whole read window.
            if type == "custom-title", let title = json["customTitle"] as? String, !title.isEmpty {
                digest.title = SessionReducer.condense(title, limit: 60)
                continue
            }

            if type == "last-prompt", let prompt = json["lastPrompt"] as? String {
                if let cleaned = SessionText.sanitizedPrompt(prompt, limit: 160) {
                    digest.lastUserPrompt = cleaned
                }
                continue
            }

            // Older CLI versions summarized instead.
            if type == "summary", let summary = json["summary"] as? String, !summary.isEmpty {
                digest.title = SessionReducer.condense(summary, limit: 60)
                continue
            }

            guard let message = json["message"] as? [String: Any] else { continue }
            let role = (message["role"] as? String) ?? type

            if let model = message["model"] as? String, !model.isEmpty {
                digest.model = model
            }

            guard let text = extractText(from: message["content"]) else { continue }

            if role == "user" {
                // Tool results and system-injected blocks are not the prompt;
                // a turn that is only injected content is skipped entirely.
                guard let prompt = SessionText.sanitizedPrompt(text, limit: 160) else { continue }
                digest.lastUserPrompt = prompt
                if digest.title == nil {
                    digest.title = SessionText.sanitizedPrompt(text, limit: 60)
                }
            } else if role == "assistant", !text.isEmpty {
                digest.lastAssistantText = String(text.prefix(2000))
            }
        }

        if digest.title == nil, digest.lastUserPrompt == nil,
           digest.lastAssistantText == nil, digest.model == nil {
            return nil
        }
        return digest
    }

    /// Content is either a plain string or an array of typed blocks.
    private static func extractText(from content: Any?) -> String? {
        if let text = content as? String {
            return text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard let blocks = content as? [[String: Any]] else { return nil }
        let texts = blocks.compactMap { block -> String? in
            guard (block["type"] as? String) == "text" else { return nil }
            return block["text"] as? String
        }
        guard !texts.isEmpty else { return nil }
        return texts.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
