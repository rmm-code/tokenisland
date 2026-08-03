import SwiftUI

/// Lightweight markdown rendering for card excerpts: headings become bold
/// lines, bullet lines get "•", inline **bold** / *italic* / `code` spans
/// render via `AttributedString(markdown:)`. No external dependencies —
/// unknown syntax falls back to plain text.
struct LiteMarkdownText: View {
    var text: String
    var size: CGFloat = 11

    var body: some View {
        Text(attributed)
    }

    private var attributed: AttributedString {
        var result = AttributedString()
        var first = true
        for line in text.components(separatedBy: "\n") {
            // Drop code-fence markers; fenced content renders as plain lines.
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("```") { continue }
            if !first { result += AttributedString("\n") }
            first = false
            result += Self.renderLine(line, size: size)
        }
        return result
    }

    // MARK: - Line rendering

    static func renderLine(_ line: String, size: CGFloat) -> AttributedString {
        let trimmed = line.trimmingCharacters(in: .whitespaces)

        if trimmed.hasPrefix("#") {
            let stripped = trimmed
                .drop(while: { $0 == "#" })
                .trimmingCharacters(in: .whitespaces)
            return inline(stripped, size: size, baseWeight: .bold)
        }

        if let bullet = bulletContent(of: trimmed) {
            var marker = AttributedString("•  ")
            marker.font = .system(size: size, weight: .semibold)
            return marker + inline(bullet, size: size)
        }

        // Numbered lists render fine as-is ("1. …").
        return inline(String(line), size: size)
    }

    /// "- item" / "* item" → "item"; nil when the line isn't a bullet.
    private static func bulletContent(of line: String) -> String? {
        for prefix in ["- ", "* "] where line.hasPrefix(prefix) {
            return String(line.dropFirst(prefix.count))
        }
        return nil
    }

    /// Parses inline markdown spans and applies fonts: monospaced for
    /// `code`, bold/italic per emphasis, `baseWeight` everywhere else.
    private static func inline(
        _ text: String,
        size: CGFloat,
        baseWeight: Font.Weight = .regular
    ) -> AttributedString {
        var parsed = (try? AttributedString(
            markdown: text,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(text)

        // Snapshot run ranges before mutating — writing attributes while
        // iterating `runs` directly can invalidate the run view.
        let spans = parsed.runs.map { ($0.range, $0.inlinePresentationIntent ?? []) }
        for (range, intent) in spans {
            let isCode = intent.contains(.code)
            let weight: Font.Weight = intent.contains(.stronglyEmphasized) ? .bold : baseWeight
            var font: Font = isCode
                ? .system(size: size - 0.5, weight: weight, design: .monospaced)
                : .system(size: size, weight: weight)
            if intent.contains(.emphasized) {
                font = font.italic()
            }
            parsed[range].font = font
            if isCode {
                parsed[range].backgroundColor = Color.white.opacity(0.09)
            }
        }
        return parsed
    }
}
