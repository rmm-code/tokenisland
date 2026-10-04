import Foundation
import CoreFoundation

/// One rate-limit window rendered as a bar in the usage view.
struct UsageWindow: Identifiable, Equatable, Sendable {
    var label: String
    var usedPercent: Double
    var resetsAt: Date?
    var key: String? = nil

    var id: String { key ?? label }
}

/// Reads Codex CLI usage from its local session rollouts
/// (`~/.codex/sessions/**/rollout-*.jsonl`): the CLI appends `token_count`
/// events carrying `rate_limits` (primary/secondary windows with
/// `used_percent`). Read-only, defensive, nil when anything is off.
enum CodexUsageReader {
    static func latestWindows(
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        now: Date = Date()
    ) -> [UsageWindow] {
        let sessionsDir = home.appendingPathComponent(".codex/sessions", isDirectory: true)
        guard let newest = newestRolloutFile(in: sessionsDir, now: now) else { return [] }
        guard let tail = readTail(of: newest, maxBytes: 131_072) else { return [] }

        // Scan lines from the end for the freshest rate_limits payload.
        for line in tail.split(separator: UInt8(ascii: "\n")).reversed() {
            guard line.count > 2,
                  let object = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
                  let rateLimits = findRateLimits(in: object)
            else { continue }
            guard let recordedAt = (object["timestamp"] as? String).flatMap(ClaudeUsageDecoder.parseTimestamp)
            else { continue }
            // File liveness does not make an old usage record fresh. Relative
            // resets belong to the record's timestamp, not the time we read it.
            let age = now.timeIntervalSince(recordedAt)
            guard age >= 0, age < 90 else { continue }
            let windows = parse(rateLimits: rateLimits, recordedAt: recordedAt)
                .filter { $0.resetsAt.map { $0 > now } ?? true }
            if !windows.isEmpty { return windows }
        }
        return []
    }

    // MARK: - Internals

    private static func newestRolloutFile(in directory: URL, now: Date) -> URL? {
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
        if let newest, now.timeIntervalSince(newest.date) < 7 * 86_400 {
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

    private static func parse(rateLimits: [String: Any], recordedAt: Date) -> [UsageWindow] {
        var windows: [UsageWindow] = []
        for key in ["primary", "secondary"] {
            guard let window = rateLimits[key] as? [String: Any] else { continue }
            guard let used = doubleValue(window["used_percent"] ?? window["used_percentage"]),
                  used.isFinite, (0...100).contains(used) else { continue }

            let minutes = doubleValue(window["window_minutes"] ?? window["window_duration_minutes"])
            let label = windowLabel(minutes: minutes, fallback: key == "primary" ? "5h" : "Weekly")

            var resetsAt: Date?
            if let timestamp = doubleValue(window["resets_at"]), timestamp.isFinite, abs(timestamp) < 100_000_000_000 {
                resetsAt = Date(timeIntervalSince1970: timestamp)
            } else if let seconds = doubleValue(window["resets_in_seconds"]), seconds.isFinite, abs(seconds) < 100_000_000_000 {
                resetsAt = recordedAt.addingTimeInterval(seconds)
            }

            windows.append(UsageWindow(label: label, usedPercent: used, resetsAt: resetsAt, key: key))
        }
        return windows
    }

    private static func windowLabel(minutes: Double?, fallback: String) -> String {
        guard let minutes, minutes.isFinite, minutes > 0, minutes < 1_000_000 else { return fallback }
        if minutes >= 10_000 { return "Weekly" }
        let hours = Int((minutes / 60).rounded())
        return hours >= 1 ? "\(hours)h" : "\(Int(minutes))m"
    }

    private static func doubleValue(_ value: Any?) -> Double? {
        if let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(), number.doubleValue.isFinite {
            return number.doubleValue
        }
        return nil
    }
}
