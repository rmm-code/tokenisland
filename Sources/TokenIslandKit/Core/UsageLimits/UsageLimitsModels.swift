import Foundation

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

    func currentWindows(at now: Date, maximumAge: TimeInterval = 90) -> [UsageLimitsWindow] {
        let age = now.timeIntervalSince(fetchedAt)
        guard age >= 0, age < maximumAge else { return [] }
        return windows.compactMap { window in
            guard window.usedPercent.isFinite, (0...100).contains(window.usedPercent) else { return nil }
            guard let reset = window.resetsAt, reset <= now else { return window }
            // A freshly reported zero is valid even when an inactive optional
            // model window retains its old reset date. Never claim "soon".
            guard window.usedPercent == 0 else { return nil }
            var inactive = window
            inactive.resetsAt = nil
            return inactive
        }
    }

    func isCurrent(at now: Date, maximumAge: TimeInterval = 90) -> Bool {
        !currentWindows(at: now, maximumAge: maximumAge).isEmpty
    }

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

enum ClaudeUsageIssue: Error, Equatable, Sendable {
    case accessRequired
    case signInRequired
    case accessDenied
    case keychainUnavailable
    case forbidden
    case networkUnavailable
    case rateLimited(retryAt: Date)
    case serverUnavailable
    case invalidResponse
    case awaitingReset

    var needsConnection: Bool {
        self == .accessRequired || self == .accessDenied || self == .signInRequired || self == .forbidden
    }

    var title: String {
        switch self {
        case .accessRequired, .accessDenied: "Claude access needed"
        case .keychainUnavailable: "Claude login unavailable"
        case .signInRequired: "Claude login needed"
        case .forbidden: "Claude usage access denied"
        case .networkUnavailable: "Usage offline"
        case .rateLimited: "Usage rate limited"
        case .serverUnavailable: "Claude usage unavailable"
        case .invalidResponse: "Usage response unavailable"
        case .awaitingReset: "Updating usage"
        }
    }

    var detail: String {
        switch self {
        case .accessRequired: "Connect to allow TokenIsland to read Claude Code's saved login. Automatic checks never open a Keychain prompt."
        case .accessDenied: "Keychain access wasn't granted. Click Connect to try again."
        case .keychainUnavailable: "Couldn't read Claude Code's saved login. Retry, or check its sign-in status."
        case .signInRequired: "Open Claude Code and sign in or refresh its login, then click Refresh."
        case .forbidden: "Claude refused usage access for this login. Check Claude Code's account and sign in again."
        case .networkUnavailable: "Couldn't reach Claude. Check your connection and retry. Old percentages are hidden."
        case .rateLimited(let retryAt): "Claude requested fewer checks. Automatic refresh resumes after \(retryAt.formatted(date: .omitted, time: .shortened))."
        case .serverUnavailable: "Claude's usage service is unavailable. TokenIsland will retry automatically."
        case .invalidResponse: "Claude's response could not be read safely. TokenIsland will retry; no usage values were guessed."
        case .awaitingReset: "The previous usage window ended. Waiting for Claude's updated limits."
        }
    }
}
