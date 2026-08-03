import Foundation

/// Custom Jump Rules (Settings → Integrations → Developer): third-party
/// terminals register a URL template per bundle identifier in
/// `~/Library/Application Support/TokenIsland/jump-rules.json`:
///
///     { "com.example.term": "exampleterm://focus?title={title}" }
///
/// `{title}` is replaced with the session's marker title. Consulted by
/// JumpService before the AX scan; mtime-cached.
enum JumpRules {
    private struct Cache {
        var rules: [String: String]
        var modificationDate: Date
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var cache: Cache?

    static var fileURL: URL {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first!
            .appendingPathComponent("TokenIsland/jump-rules.json")
    }

    /// URL template for a terminal, or nil when no rule exists.
    static func template(forBundleID bundleID: String) -> String? {
        loadIfNeeded()[bundleID]
    }

    /// Builds the final URL from a template and marker title.
    static func url(fromTemplate template: String, markerTitle: String) -> URL? {
        let encoded = markerTitle.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? markerTitle
        return URL(string: template.replacingOccurrences(of: "{title}", with: encoded))
    }

    private static func loadIfNeeded() -> [String: String] {
        lock.lock()
        defer { lock.unlock() }

        let url = fileURL
        let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
            .contentModificationDate ?? .distantPast
        if let cache, cache.modificationDate == modified {
            return cache.rules
        }
        guard let data = try? Data(contentsOf: url),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: String]
        else {
            cache = Cache(rules: [:], modificationDate: modified)
            return [:]
        }
        cache = Cache(rules: object, modificationDate: modified)
        return object
    }
}
