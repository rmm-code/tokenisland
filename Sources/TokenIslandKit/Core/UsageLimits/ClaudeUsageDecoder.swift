import Foundation
import CoreFoundation

/// Pure decoding of the account usage response. No IO or credentials.
enum ClaudeUsageDecoder {
    /// `fiveHour` and `five_hour` are the same window.
    nonisolated static func normalizedKey(_ key: String) -> String {
        var result = ""
        for character in key {
            if character.isUppercase {
                result.append("_")
                result.append(Character(character.lowercased()))
            } else {
                result.append(character)
            }
        }
        return result
    }

    /// Per-model caps sometimes arrive under an internal codename rather than
    /// the model's public name — the endpoint ships `nimbus_quill` for the
    /// Fable cap, and title-casing it verbatim puts "Nimbus Quill" in the pill.
    /// Add a row here when a new codename shows up in the "usage endpoint
    /// reported keys" log line above.
    nonisolated static let windowCodenames: [String: String] = [
        "nimbus_quill": "Fable 5"
    ]

    /// "seven_day_fable" → "7d Fable", "nimbus_quill" → "Fable 5". Unknown
    /// windows still get a readable label rather than being dropped.
    nonisolated static func windowLabel(forKey key: String) -> String {
        let normalized = normalizedKey(key)
        var remainder = normalized
        var prefix: String?
        for (candidate, short) in [("five_hour", "5h"), ("seven_day", "7d"), ("thirty_day", "30d")]
        where normalized == candidate || normalized.hasPrefix(candidate + "_") {
            prefix = short
            remainder = String(normalized.dropFirst(candidate.count))
        }

        let trimmed = remainder.trimmingCharacters(in: CharacterSet(charactersIn: "_"))
        if prefix == nil, windowCodenames[trimmed] == nil { return "Additional limit" }
        let suffix: String
        if let known = windowCodenames[trimmed] {
            suffix = known
        } else {
            suffix = trimmed
                .split(separator: "_")
                .filter { !$0.isEmpty }
                .map { $0.prefix(1).uppercased() + $0.dropFirst() }
                .joined(separator: " ")
        }
        return [prefix, suffix.isEmpty ? nil : suffix]
            .compactMap { $0 }
            .joined(separator: " ")
    }

    /// Session window first, then the plan's weekly cap, then per-model caps.
    nonisolated static func windowOrder(_ key: String) -> Int {
        if key == "five_hour" { return 0 }
        if key == "seven_day" { return 1 }
        if key.hasPrefix("five_hour") { return 2 }
        if key.hasPrefix("seven_day") { return 3 }
        return 4
    }

    /// Pure decode of the usage endpoint's body. Kept internal so the real
    /// response shape is covered by tests without network or Keychain access.
    nonisolated static func snapshot(
        fromUsageJSON object: [String: Any],
        fetchedAt: Date
    ) -> UsageLimitsSnapshot? {
        var snapshot = UsageLimitsSnapshot(fetchedAt: fetchedAt)

        // Accepts both {"five_hour": {...}} and nested/renamed variants. A
        // window can be JSON null (`seven_day_opus` often is), which fails the
        // dictionary cast and correctly reads as "no data".
        func percent(from window: [String: Any]?) -> Double? {
            guard let window else { return nil }
            for key in ["utilization", "used_percentage", "usage_percent", "percent_used"] {
                // `utilization` is already 0–100 (a real response carries 33.0
                // for 33%). Rescaling anything <= 1 turned a genuine 1% into a
                // red 100% pill.
                if let number = window[key] as? NSNumber,
                   CFGetTypeID(number) != CFBooleanGetTypeID() {
                    let value = number.doubleValue
                    if value.isFinite, (0...100).contains(value) { return value }
                }
            }
            return nil
        }
        func reset(from window: [String: Any]?) -> Date? {
            guard let window else { return nil }
            for key in ["resets_at", "reset_at", "resetsAt"] {
                if let number = window[key] as? NSNumber,
                   CFGetTypeID(number) != CFBooleanGetTypeID(),
                   case let timestamp = number.doubleValue,
                   timestamp.isFinite, abs(timestamp) < 100_000_000_000 {
                    return Date(timeIntervalSince1970: timestamp)
                }
                if let text = window[key] as? String,
                   let date = parseTimestamp(text) {
                    return date
                }
            }
            if let number = window["resets_in_seconds"] as? NSNumber,
               CFGetTypeID(number) != CFBooleanGetTypeID(),
               case let seconds = number.doubleValue,
               seconds.isFinite, abs(seconds) < 100_000_000_000 {
                return fetchedAt.addingTimeInterval(seconds)
            }
            return nil
        }

        // Every window the plan reports, in the order the pill should read
        // them: session first, then the weekly cap, then per-model caps
        // (Fable, Opus) — which appear, disappear and get renamed with the
        // plan, so they are discovered rather than hardcoded.
        var found: [String: UsageLimitsWindow] = [:]
        // Prefer canonical snake_case if aliases occur in the same payload.
        for key in object.keys.sorted(by: { lhs, rhs in
            let leftCanonical = normalizedKey(lhs) == lhs
            let rightCanonical = normalizedKey(rhs) == rhs
            return leftCanonical == rightCanonical ? lhs < rhs : leftCanonical
        }) {
            let normalized = normalizedKey(key)
            guard found[normalized] == nil,
                  let body = object[key] as? [String: Any],
                  let used = percent(from: body)
            else {
                continue
            }
            found[normalized] =
                UsageLimitsWindow(
                    key: normalized,
                    label: windowLabel(forKey: key),
                    usedPercent: used,
                    resetsAt: reset(from: body)
                )
        }
        snapshot.windows = found.values.sorted { lhs, rhs in
            let order = windowOrder(lhs.key) == windowOrder(rhs.key)
            return order ? lhs.key < rhs.key : windowOrder(lhs.key) < windowOrder(rhs.key)
        }

        guard snapshot.headerText != nil else { return nil }
        return snapshot
    }

    /// Parses the endpoint's reset timestamps. The real response sends
    /// microsecond precision with an offset — `"2026-04-11T07:00:00.528743+00:00"` —
    /// and `ISO8601DateFormatter` parses no fractional seconds by default and
    /// only three digits even with `.withFractionalSeconds`. Plain
    /// `ISO8601DateFormatter().date(from:)` therefore returned nil for every
    /// window, which is why the pill only ever showed percentages.
    /// Kept internal so the shapes can be verified without network access.
    nonisolated static func parseTimestamp(_ text: String) -> Date? {
        let attempts: [ISO8601DateFormatter.Options] = [
            [.withInternetDateTime, .withFractionalSeconds],
            [.withInternetDateTime]
        ]
        for options in attempts {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = options
            if let date = formatter.date(from: text) { return date }
        }
        // Drop an over-long fractional part and retry: sub-second precision is
        // meaningless for a countdown measured in minutes.
        guard let dot = text.firstIndex(of: ".") else { return nil }
        let afterDot = text[text.index(after: dot)...]
        guard let fractionEnd = afterDot.firstIndex(where: { !$0.isNumber }) else { return nil }
        let stripped = String(text[text.startIndex..<dot]) + String(afterDot[fractionEnd...])
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: stripped)
    }

}
