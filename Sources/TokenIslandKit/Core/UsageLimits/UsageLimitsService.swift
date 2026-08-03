import Foundation
import LocalAuthentication
import Security

/// Subscription usage-limit windows shown in the panel header
/// ("5h 11% · 7d 2%"), like the reference app.
struct UsageLimitsSnapshot: Codable, Equatable, Sendable {
    var fiveHourUsedPercent: Double?
    var fiveHourResetsAt: Date?
    var sevenDayUsedPercent: Double?
    var sevenDayResetsAt: Date?
    var fetchedAt: Date

    var headerText: String? {
        var parts: [String] = []
        if let fiveHourUsedPercent {
            parts.append("5h \(Int(fiveHourUsedPercent.rounded()))%")
        }
        if let sevenDayUsedPercent {
            parts.append("7d \(Int(sevenDayUsedPercent.rounded()))%")
        }
        guard !parts.isEmpty else { return nil }
        return parts.joined(separator: " · ")
    }
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

        return snapshot(fromUsageJSON: object, fetchedAt: Date())
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

        let fiveHour = window(["five_hour", "fiveHour"])
        let sevenDay = window(["seven_day", "sevenDay"])
        snapshot.fiveHourUsedPercent = percent(from: fiveHour)
        snapshot.fiveHourResetsAt = reset(from: fiveHour)
        snapshot.sevenDayUsedPercent = percent(from: sevenDay)
        snapshot.sevenDayResetsAt = reset(from: sevenDay)

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
