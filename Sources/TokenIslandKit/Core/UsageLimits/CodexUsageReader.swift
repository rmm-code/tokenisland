import Foundation

/// One rate-limit window rendered as a bar in the usage view.
struct UsageWindow: Identifiable, Equatable, Sendable {
    var label: String
    var usedPercent: Double
    var resetsAt: Date?

    var id: String { label }
}

/// Reads Codex CLI usage from its local session rollouts
/// (`~/.codex/sessions/**/rollout-*.jsonl`): the CLI appends `token_count`
/// events carrying `rate_limits` (primary/secondary windows with
/// `used_percent`). Read-only, defensive, nil when anything is off.
enum CodexUsageReader {
    static func latestWindows(
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> [UsageWindow] {
        let sessionsDir = home.appendingPathComponent(".codex/sessions", isDirectory: true)
        guard let newest = newestRolloutFile(in: sessionsDir) else { return [] }
        guard let tail = readTail(of: newest, maxBytes: 131_072) else { return [] }

        // Scan lines from the end for the freshest rate_limits payload.
        for line in tail.split(separator: UInt8(ascii: "\n")).reversed() {
            guard line.count > 2,
                  let object = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
                  let rateLimits = findRateLimits(in: object)
            else { continue }
            let windows = parse(rateLimits: rateLimits)
            if !windows.isEmpty { return windows }
        }
        return []
    }

    // MARK: - Internals

    private static func newestRolloutFile(in directory: URL) -> URL? {
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return nil }

        var newest: (url: URL, date: Date)?
        for case let url as URL in enumerator where url.pathExtension == "jsonl" {
            let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate ?? .distantPast
            if newest == nil || date > newest!.date {
                newest = (url, date)
            }
        }
        // Stale sessions say nothing about current limits.
        if let newest, Date().timeIntervalSince(newest.date) < 7 * 86_400 {
            return newest.url
        }
        return nil
    }

    private static func readTail(of url: URL, maxBytes: Int) -> Data? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let size = try? handle.seekToEnd(), size > 0 else { return nil }
        let start = size > UInt64(maxBytes) ? size - UInt64(maxBytes) : 0
        try? handle.seek(toOffset: start)
        return try? handle.readToEnd()
    }

    /// The payload shape moves between Codex versions — search for the
    /// `rate_limits` key anywhere in the object (bounded depth).
    private static func findRateLimits(in object: [String: Any], depth: Int = 0) -> [String: Any]? {
        guard depth < 5 else { return nil }
        if let rateLimits = object["rate_limits"] as? [String: Any] { return rateLimits }
        for value in object.values {
            if let nested = value as? [String: Any],
               let found = findRateLimits(in: nested, depth: depth + 1) {
                return found
            }
        }
        return nil
    }

    private static func parse(rateLimits: [String: Any]) -> [UsageWindow] {
        var windows: [UsageWindow] = []
        for key in ["primary", "secondary"] {
            guard let window = rateLimits[key] as? [String: Any] else { continue }
            guard let used = doubleValue(window["used_percent"] ?? window["used_percentage"]) else { continue }

            let minutes = doubleValue(window["window_minutes"] ?? window["window_duration_minutes"])
            let label = windowLabel(minutes: minutes, fallback: key == "primary" ? "5h" : "Weekly")

            var resetsAt: Date?
            if let seconds = doubleValue(window["resets_in_seconds"]) {
                resetsAt = Date().addingTimeInterval(seconds)
            } else if let timestamp = doubleValue(window["resets_at"]) {
                resetsAt = Date(timeIntervalSince1970: timestamp)
            }

            windows.append(UsageWindow(label: label, usedPercent: used, resetsAt: resetsAt))
        }
        return windows
    }

    private static func windowLabel(minutes: Double?, fallback: String) -> String {
        guard let minutes, minutes > 0 else { return fallback }
        if minutes >= 10_000 { return "Weekly" }
        let hours = Int((minutes / 60).rounded())
        return hours >= 1 ? "\(hours)h" : "\(Int(minutes))m"
    }

    private static func doubleValue(_ value: Any?) -> Double? {
        if let double = value as? Double { return double }
        if let int = value as? Int { return Double(int) }
        return nil
    }
}
