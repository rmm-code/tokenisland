import Foundation

/// Converts provider model IDs into compact product names for session cards.
/// Known provider wrappers and deployment suffixes are removed; unknown IDs
/// are preserved verbatim so the UI never invents a model name.
enum ModelNameFormatter {
    private static let claudeFamilies = ["fable", "mythos", "opus", "sonnet", "haiku"]
    private static let hiddenValues: Set<String> = ["<synthetic>", "synthetic", "unknown", "default"]

    static func displayName(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let original = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !original.isEmpty else { return nil }

        var slug = original.lowercased()
        guard !hiddenValues.contains(slug) else { return nil }
        slug = unwrapProviderPath(slug)

        if slug == "gpt" { return "GPT" }
        if slug.hasPrefix("gpt-") { return gptDisplayName(slug) }
        if slug == "codex" { return "Codex" }
        if slug.hasPrefix("codex-") { return codexDisplayName(slug) }
        if slug.hasPrefix("gemini-") { return geminiDisplayName(slug) }

        if let claudeSlug = claudeSlug(from: slug) {
            return claudeDisplayName(claudeSlug) ?? original
        }
        return original
    }

    private static func unwrapProviderPath(_ value: String) -> String {
        var slug = value
        if let anthropicRange = slug.range(of: "anthropic.claude-") {
            slug = String(slug[anthropicRange.lowerBound...].dropFirst("anthropic.".count))
        } else if slug.hasPrefix("openai/")
                    || slug.hasPrefix("models/")
                    || slug.contains("/models/") {
            slug = slug.split(separator: "/").last.map(String.init) ?? slug
        }
        for prefix in ["openai.", "anthropic."] where slug.hasPrefix(prefix) {
            slug = String(slug.dropFirst(prefix.count))
        }
        return slug
    }

    private static func claudeSlug(from value: String) -> String? {
        guard value.hasPrefix("claude-") else { return nil }
        var slug = value
        if let at = slug.firstIndex(of: "@") {
            slug = String(slug[..<at])
        }
        if let range = slug.range(of: #"-v\d+:\d+$"#, options: .regularExpression) {
            slug.removeSubrange(range)
        }
        return slug
    }

    private static func claudeDisplayName(_ slug: String) -> String? {
        var parts = slug.split(separator: "-").dropFirst().map(String.init)
        removeNonDisplaySuffixes(from: &parts)
        guard let familyIndex = parts.firstIndex(where: { claudeFamilies.contains($0) }) else {
            return nil
        }

        let family = titleCased(parts[familyIndex])
        let before = parts[..<familyIndex].filter(isVersionPart)
        let after = parts.dropFirst(familyIndex + 1).prefix(while: isVersionPart)
        let versionParts = before.isEmpty ? Array(after) : Array(before)
        return versionParts.isEmpty ? family : "\(family) \(versionParts.joined(separator: "."))"
    }

    private static func gptDisplayName(_ slug: String) -> String {
        var parts = slug.split(separator: "-").dropFirst().map(String.init)
        removeNonDisplaySuffixes(from: &parts)
        guard let version = parts.first else { return "GPT" }
        let qualifiers = parts.dropFirst().map(titleCased).joined(separator: " ")
        return qualifiers.isEmpty ? "GPT-\(version)" : "GPT-\(version) \(qualifiers)"
    }

    private static func codexDisplayName(_ slug: String) -> String {
        var parts = slug.split(separator: "-").dropFirst().map(String.init)
        removeNonDisplaySuffixes(from: &parts)
        let qualifiers = parts.map(titleCased).joined(separator: " ")
        return qualifiers.isEmpty ? "Codex" : "Codex \(qualifiers)"
    }

    private static func geminiDisplayName(_ slug: String) -> String {
        var parts = slug.split(separator: "-").dropFirst().map(String.init)
        removeNonDisplaySuffixes(from: &parts)
        let qualifiers = parts.map { part in
            isVersionPart(part) ? part : titleCased(part)
        }
        return qualifiers.isEmpty ? "Gemini" : "Gemini \(qualifiers.joined(separator: " "))"
    }

    private static func removeNonDisplaySuffixes(from parts: inout [String]) {
        while let last = parts.last,
              last == "latest" || (last.count == 8 && Int(last) != nil) {
            parts.removeLast()
        }
    }

    private static func isVersionPart(_ value: String) -> Bool {
        !value.isEmpty && value.allSatisfy { $0.isNumber || $0 == "." }
    }

    private static func titleCased(_ value: String) -> String {
        value.prefix(1).uppercased() + value.dropFirst()
    }
}
