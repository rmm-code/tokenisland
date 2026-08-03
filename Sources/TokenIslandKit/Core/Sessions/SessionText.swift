import Foundation

/// Cleans the text a CLI hands us before it becomes a session title or a
/// "You:" line. Agents inject a lot into the user turn — reminder blocks, task
/// notifications, slash-command envelopes, attachment placeholders — and none
/// of it is what the person typed.
enum SessionText {
    /// Blocks the harness wraps around injected content. Anything between the
    /// open and close tag goes, and a stray open tag truncates the rest.
    private static let injectedTags = [
        "system-reminder",
        "task-notification",
        "user-prompt-submit-hook",
        "command-name",
        "command-message",
        "command-args",
        "local-command-stdout",
        "local-command-stderr",
        "function_results",
        "budget:token_budget"
    ]

    /// Placeholders the CLI substitutes for pasted content.
    private static let placeholderPrefixes = [
        "Image",
        "Attachment",
        "Screenshot",
        "Pasted text",
        "Image #"
    ]

    /// Strips injected blocks and placeholders, collapses whitespace, and
    /// truncates. Returns nil when nothing the user actually wrote is left —
    /// callers keep the previous title rather than showing machinery.
    static func sanitizedPrompt(_ raw: String?, limit: Int) -> String? {
        guard let raw, !raw.isEmpty else { return nil }
        var text = raw

        for tag in injectedTags {
            text = removeBlocks(named: tag, from: text)
        }
        text = removePlaceholders(from: text)

        let cleaned = SessionReducer.condense(text, limit: limit)
        return cleaned.isEmpty ? nil : cleaned
    }

    /// Removes `<tag>…</tag>` pairs; an unclosed `<tag>` drops everything after
    /// it, which is what an injected block at the end of a prompt looks like.
    private static func removeBlocks(named tag: String, from text: String) -> String {
        var result = text
        let open = "<\(tag)>"
        let close = "</\(tag)>"
        while let start = result.range(of: open, options: .caseInsensitive) {
            if let end = result.range(of: close, options: .caseInsensitive, range: start.upperBound..<result.endIndex) {
                result.removeSubrange(start.lowerBound..<end.upperBound)
            } else {
                result.removeSubrange(start.lowerBound..<result.endIndex)
            }
        }
        // A closing tag with no opener means the block started before this
        // slice of text; drop everything up to it.
        if let orphan = result.range(of: close, options: .caseInsensitive) {
            result.removeSubrange(result.startIndex..<orphan.upperBound)
        }
        return result
    }

    /// Drops "[Image: original 2556x1580, displayed at …]"-style stand-ins.
    private static func removePlaceholders(from text: String) -> String {
        var result = ""
        var remainder = Substring(text)
        while let open = remainder.firstIndex(of: "[") {
            guard let close = remainder[open...].firstIndex(of: "]") else { break }
            let inner = remainder[remainder.index(after: open)..<close]
            let isPlaceholder = placeholderPrefixes.contains { prefix in
                inner.hasPrefix(prefix) && (inner.count == prefix.count || inner.dropFirst(prefix.count).hasPrefix(":") || inner.dropFirst(prefix.count).hasPrefix(" "))
            }
            result += remainder[remainder.startIndex..<open]
            if !isPlaceholder {
                result += remainder[open...close]
            }
            remainder = remainder[remainder.index(after: close)...]
        }
        result += remainder
        return result
    }
}
