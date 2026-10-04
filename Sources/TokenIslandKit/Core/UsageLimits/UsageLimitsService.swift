import Foundation

/// Account usage is live data, never a persisted source of truth. This service
/// owns refresh cadence and presentation validity; credentials/networking are
/// isolated in ClaudeUsageClient so failures can be tested without real login.
@MainActor
final class UsageLimitsService: ObservableObject {
    @Published private(set) var snapshot: UsageLimitsSnapshot?
    @Published private(set) var issue: ClaudeUsageIssue?
    @Published private(set) var isRefreshing = false
    @Published private(set) var lastAttemptAt: Date?
    @Published private(set) var lastSuccessAt: Date?
    @Published private(set) var retryAt: Date?

    private let client: any ClaudeUsageFetching
    private let now: () -> Date
    private var nextAutomaticAttempt: Date?
    static let refreshInterval: TimeInterval = 60

    init(
        defaults: UserDefaults = .standard,
        client: any ClaudeUsageFetching = ClaudeUsageClient(),
        now: @escaping () -> Date = { Date() }
    ) {
        self.client = client
        self.now = now
        // Migrate the old unbounded, account-independent cache. A recently
        // saved cache is also unsafe after switching the Claude Code login.
        defaults.removeObject(forKey: "claudeUsageLimitsSnapshot")
    }

    var displayedSnapshot: UsageLimitsSnapshot? {
        guard issue == nil, let snapshot, snapshot.isCurrent(at: now()) else { return nil }
        var current = snapshot
        current.windows = snapshot.currentWindows(at: now())
        return current
    }

    var canRefresh: Bool { !isRefreshing && (retryAt.map { $0 <= now() } ?? true) }

    /// Safe for panel appearance, timers, and wake: never opens authentication.
    func refreshIfStale() async {
        await refresh(allowsInteraction: false, force: false)
    }

    /// Explicit Refresh/Connect bypasses the normal timer, but never a server
    /// Retry-After interval. Interactive access remains limited to this action.
    func refreshFromUserAction() async {
        await refresh(allowsInteraction: true, force: true)
    }

    private func refresh(allowsInteraction: Bool, force: Bool) async {
        guard !isRefreshing else { return }
        let date = now()
        if let snapshot, snapshot.windows.contains(where: {
            $0.resetsAt.map { $0 > snapshot.fetchedAt && $0 <= date } ?? false
        }) {
            nextAutomaticAttempt = date
            var current = snapshot
            current.windows = snapshot.currentWindows(at: date)
            self.snapshot = current
        }
        if let snapshot, !snapshot.isCurrent(at: date) {
            self.snapshot = nil
            issue = .awaitingReset
            if snapshot.windows.contains(where: { $0.resetsAt.map { $0 <= date } ?? false }) {
                nextAutomaticAttempt = date
            }
        }
        guard retryAt.map({ $0 <= date }) ?? true else { return }
        guard force || nextAutomaticAttempt.map({ $0 <= date }) ?? true else { return }
        isRefreshing = true
        lastAttemptAt = date
        nextAutomaticAttempt = date.addingTimeInterval(Self.refreshInterval)
        defer { isRefreshing = false }
        do {
            let fetched = try await client.fetch(allowsInteraction: allowsInteraction)
            guard fetched.isCurrent(at: now()) else { throw ClaudeUsageIssue.awaitingReset }
            var current = fetched
            current.windows = fetched.currentWindows(at: now())
            snapshot = current
            if fetched.windows.contains(where: {
                ["five_hour", "seven_day"].contains($0.key)
                    && $0.usedPercent > 0 && ($0.resetsAt.map { $0 <= now() } ?? false)
            }) {
                nextAutomaticAttempt = now().addingTimeInterval(15)
            }
            issue = nil
            retryAt = nil
            lastSuccessAt = fetched.fetchedAt
        } catch is CancellationError {
            // Closing the transient panel cancels its task. It must not
            // manufacture an offline error or impose a minute-long delay
            // before the user can reopen and load usage.
            nextAutomaticAttempt = nil
            issue = nil
        } catch {
            snapshot = nil
            let failure = error as? ClaudeUsageIssue ?? .networkUnavailable
            issue = failure
            if case .rateLimited(let deadline) = failure {
                retryAt = deadline
                nextAutomaticAttempt = deadline
            } else {
                retryAt = nil
                // The API can briefly report the previous reset window.
                if failure == .awaitingReset { nextAutomaticAttempt = now().addingTimeInterval(15) }
            }
            // Error category only, never raw HTTP/Keychain errors or tokens.
            AppLog.app.notice("Claude usage refresh: \(failure.title, privacy: .public)")
        }
    }
}
