import Foundation
import LocalAuthentication
import Security

/// One usage window as the endpoint reports it. Plans carry a rolling session
/// window and a weekly one, plus per-model weekly caps (Fable, Opus) that come
/// and go with the plan — so windows are discovered, never hardcoded.
struct UsageLimitsWindow: Codable, Equatable, Sendable, Identifiable {
    /// The endpoint's own key, e.g. "five_hour", "seven_day_fable".
    var key: String
    /// What the pill shows: "5h", "7d", "7d Fable".
    var label: String
    var usedPercent: Double
    var resetsAt: Date?

    var id: String { key }
}

/// Subscription usage-limit windows shown in the panel header
/// ("5h 11% · 7d 2% · 7d Fable 40%"), like the reference app.
struct UsageLimitsSnapshot: Codable, Equatable, Sendable {
    var windows: [UsageLimitsWindow] = []
    var fetchedAt: Date

    var headerText: String? {
        guard !windows.isEmpty else { return nil }
        return windows
            .map { "\($0.label) \(Int($0.usedPercent.rounded()))%" }
            .joined(separator: " · ")
    }

    private func window(_ key: String) -> UsageLimitsWindow? {
        windows.first { $0.key == key }
    }

    var fiveHourUsedPercent: Double? { window("five_hour")?.usedPercent }
    var fiveHourResetsAt: Date? { window("five_hour")?.resetsAt }
    var sevenDayUsedPercent: Double? { window("seven_day")?.usedPercent }
    var sevenDayResetsAt: Date? { window("seven_day")?.resetsAt }
}

/// Reads the local Claude Code OAuth credentials and asks the usage endpoint
/// for the 5-hour / 7-day windows. Automatic refreshes permit only a
/// noninteractive Keychain query, so panel presentation can use an existing
/// grant but can never display a macOS authentication prompt.
@MainActor
final class UsageLimitsService: ObservableObject {
    @Published private(set) var snapshot: UsageLimitsSnapshot?
    @Published private(set) var isRefreshing = false
    @Published private(set) var didAttemptUserRefresh = false

    private enum CredentialAccess: Hashable {
        case automaticNoninteractiveKeychain
        case userInitiatedKeychainFallback
    }

    private var lastAttempt: [CredentialAccess: Date] = [:]
    private let minimumRefreshInterval: TimeInterval = 300
    private let defaults: UserDefaults
    private static let cachedSnapshotKey = "claudeUsageLimitsSnapshot"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.cachedSnapshotKey),
           let cached = try? JSONDecoder().decode(UsageLimitsSnapshot.self, from: data) {
            snapshot = cached
        }
    }

    /// Safe for automatic callers: Keychain interaction UI is prohibited.
    func refreshIfStale() {
        refreshIfStale(using: .automaticNoninteractiveKeychain)
    }

    /// May show macOS's Keychain authentication UI and must only be called
    /// directly from a user interaction.
    func refreshFromUserAction() {
        refreshIfStale(using: .userInitiatedKeychainFallback)
    }

    private func refreshIfStale(using credentialAccess: CredentialAccess) {
        let now = Date()
        if let lastAttempt = lastAttempt[credentialAccess],
           now.timeIntervalSince(lastAttempt) < minimumRefreshInterval {
            return
        }
        lastAttempt[credentialAccess] = now
        isRefreshing = true
        Task { [weak self] in
            let result = await Self.fetch(credentialAccess: credentialAccess)
            guard let self else { return }
            if let result {
                snapshot = result
                if let data = try? JSONEncoder().encode(result) {
                    defaults.set(data, forKey: Self.cachedSnapshotKey)
                }
            }
            isRefreshing = false
            if credentialAccess == .userInitiatedKeychainFallback {
                didAttemptUserRefresh = true
            }
        }
    }

    // MARK: - Fetch (off-main)

    private static func fetch(credentialAccess: CredentialAccess) async -> UsageLimitsSnapshot? {
        guard let token = loadAccessToken(credentialAccess: credentialAccess) else { return nil }
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/api/oauth/usage")!)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.timeoutInterval = 10

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse
        else { return nil }
        if http.statusCode == 401 || http.statusCode == 403 {
            // The stored token expired or was rotated — drop it so the next
            // user-initiated refresh may read a fresh one.
            invalidateCachedAccessToken()
            return nil
        }
        guard http.statusCode == 200,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }

        // Key names only — no values, no token. Makes "why is window X missing"
        // answerable from the log instead of by guessing at the plan's shape.
        let reported = object.keys.sorted().joined(separator: ", ")
        AppLog.app.info("usage endpoint reported keys: \(reported, privacy: .public)")

        return snapshot(fromUsageJSON: object, fetchedAt: Date())
    }

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

    /// Claude meters no separate Opus percentage, so an `*_opus` window in the
    /// payload is leftover plumbing rather than something the user can act on.
    /// Delete a key here the day a plan starts tracking it for real.
    nonisolated static let suppressedWindowKeys: Set<String> = [
        "seven_day_opus",
        "five_hour_opus"
    ]

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
        func window(_ keys: [String]) -> [String: Any]? {
            for key in keys {
                if let value = object[key] as? [String: Any] { return value }
            }
            return nil
        }
        func percent(from window: [String: Any]?) -> Double? {
            guard let window else { return nil }
            for key in ["utilization", "used_percentage", "usage_percent", "percent_used"] {
                // `utilization` is already 0–100 (a real response carries 33.0
                // for 33%). Rescaling anything <= 1 turned a genuine 1% into a
                // red 100% pill.
                if let value = window[key] as? Double { return value }
                if let value = window[key] as? Int { return Double(value) }
            }
            return nil
        }
        func reset(from window: [String: Any]?) -> Date? {
            guard let window else { return nil }
            for key in ["resets_at", "reset_at", "resetsAt"] {
                if let timestamp = window[key] as? Double {
                    return Date(timeIntervalSince1970: timestamp)
                }
                if let text = window[key] as? String,
                   let date = parseTimestamp(text) {
                    return date
                }
            }
            if let seconds = window["resets_in_seconds"] as? Double {
                return Date().addingTimeInterval(seconds)
            }
            return nil
        }

        // Every window the plan reports, in the order the pill should read
        // them: session first, then the weekly cap, then per-model caps
        // (Fable, Opus) — which appear, disappear and get renamed with the
        // plan, so they are discovered rather than hardcoded.
        var found: [UsageLimitsWindow] = []
        for (key, value) in object {
            let normalized = normalizedKey(key)
            guard !suppressedWindowKeys.contains(normalized),
                  let body = value as? [String: Any],
                  let used = percent(from: body)
            else {
                continue
            }
            found.append(
                UsageLimitsWindow(
                    key: normalized,
                    label: windowLabel(forKey: key),
                    usedPercent: used,
                    resetsAt: reset(from: body)
                )
            )
        }
        snapshot.windows = found.sorted { lhs, rhs in
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

    /// Reading another app's Keychain item (Claude Code's login) makes macOS
    /// show a password prompt. Once the user cancels/denies, never ask again
    /// this run — the header just hides. (Benign flag race: worst case one
    /// extra attempt.)
    nonisolated(unsafe) private static var keychainDeclinedThisRun = false
    /// One authenticated read per launch. Claude Code keeps its login in the
    /// Keychain (there is no credentials file on a normal install), and every
    /// read of another app's item is a password prompt unless macOS can match
    /// a stored grant — so the token is held for the process lifetime and only
    /// dropped when the server rejects it.
    nonisolated(unsafe) private static var cachedAccessToken: String?

    static func invalidateCachedAccessToken() {
        cachedAccessToken = nil
    }

    private static func loadAccessToken(credentialAccess: CredentialAccess) -> String? {
        if let cachedAccessToken { return cachedAccessToken }
        let fileURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/.credentials.json")
        let token = resolveAccessToken(
            credentialsFileURL: fileURL,
            allowsKeychainFallback: true,
            keychainReader: {
                switch credentialAccess {
                case .automaticNoninteractiveKeychain:
                    return keychainData(
                        service: "Claude Code-credentials",
                        allowsInteraction: false
                    )
                case .userInitiatedKeychainFallback:
                    guard !keychainDeclinedThisRun else { return nil }
                    return keychainData(
                        service: "Claude Code-credentials",
                        allowsInteraction: true
                    )
                }
            }
        )
        cachedAccessToken = token
        return token
    }

    /// Kept internal so the no-prompt policy can be verified without touching
    /// the user's real credentials or Keychain in tests.
    nonisolated static func resolveAccessToken(
        credentialsFileURL: URL,
        allowsKeychainFallback: Bool,
        keychainReader: () -> Data?
    ) -> String? {
        if let data = try? Data(contentsOf: credentialsFileURL),
           let token = accessToken(fromCredentialsData: data) {
            return token
        }
        guard allowsKeychainFallback else { return nil }
        if let data = keychainReader(),
           let token = accessToken(fromCredentialsData: data) {
            return token
        }
        return nil
    }

    private static func keychainData(service: String, allowsInteraction: Bool) -> Data? {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        if !allowsInteraction {
            let context = LAContext()
            context.interactionNotAllowed = true
            query[kSecUseAuthenticationContext as String] = context
        }
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess else {
            // User hit Deny/cancel (or auth failed) — asking again this run
            // would just nag. errSecItemNotFound stays retryable.
            if allowsInteraction,
               status == errSecUserCanceled || status == errSecAuthFailed
                || status == errSecInteractionNotAllowed {
                keychainDeclinedThisRun = true
            }
            return nil
        }
        return item as? Data
    }

    nonisolated private static func accessToken(fromCredentialsData data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        if let oauth = object["claudeAiOauth"] as? [String: Any],
           let token = oauth["accessToken"] as? String, !token.isEmpty {
            // Expired tokens just fail the request; we don't refresh them.
            return token
        }
        return nil
    }
}
