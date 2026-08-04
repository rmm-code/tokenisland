import AppKit
import Combine
import Foundation

/// A release newer than the running build.
struct AvailableUpdate: Equatable, Sendable {
    var version: String
    var downloadURL: URL
    var releaseNotesURL: URL?
    var publishedAt: Date?
}

/// Checks a Sparkle-format appcast for a newer build and publishes the result,
/// so the menu bar and About can show "Update available".
///
/// The feed format is Sparkle's on purpose: the day this app ships with a
/// Developer ID and notarization, dropping in Sparkle's installer needs no
/// change on the server side. Until then this reports the update and hands the
/// user the download — an unsigned build cannot safely replace itself.
@MainActor
final class UpdateChecker: ObservableObject {
    @Published private(set) var available: AvailableUpdate?
    @Published private(set) var isChecking = false
    @Published private(set) var lastCheckedAt: Date?
    @Published private(set) var lastError: String?

    /// Set by the executable when Sparkle is available: installs the update in
    /// place instead of opening the download page. Left nil in tests and in any
    /// build without the framework, where the fallback is still correct.
    var installHandler: (() -> Void)?

    var canInstallInPlace: Bool { installHandler != nil }

    /// Absent when the build has no `SUFeedURL` — a local build has nowhere to
    /// check, which is reported as "not configured" rather than as an error.
    let feedURL: URL?
    private let currentVersion: String
    private let session: URLSession
    private let minimumInterval: TimeInterval = 6 * 3600

    init(
        bundle: Bundle = .main,
        session: URLSession = .shared
    ) {
        self.feedURL = (bundle.infoDictionary?["SUFeedURL"] as? String).flatMap(URL.init(string:))
        self.currentVersion = (bundle.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "0"
        self.session = session
    }

    var isConfigured: Bool { feedURL != nil }

    /// Launch and periodic path: quiet, rate-limited, never surfaces an error
    /// the user did not ask for.
    func checkIfDue(enabled: Bool) {
        guard enabled, isConfigured else { return }
        if let lastCheckedAt, Date().timeIntervalSince(lastCheckedAt) < minimumInterval { return }
        check(userInitiated: false)
    }

    func checkNow() {
        check(userInitiated: true)
    }

    /// What the "Update available" banner does. Sparkle downloads, verifies its
    /// signature and relaunches; without it the user gets the release page,
    /// which is the only safe thing an app that cannot verify a download can do.
    func installOrOpenDownload() {
        if let installHandler {
            installHandler()
            return
        }
        guard let update = available else { return }
        NSWorkspace.shared.open(update.releaseNotesURL ?? update.downloadURL)
    }

    private func check(userInitiated: Bool) {
        guard let feedURL, !isChecking else { return }
        isChecking = true
        if userInitiated { lastError = nil }

        Task { [weak self] in
            guard let self else { return }
            defer { isChecking = false }
            do {
                var request = URLRequest(url: feedURL)
                request.timeoutInterval = 15
                request.cachePolicy = .reloadIgnoringLocalCacheData
                let (data, response) = try await session.data(for: request)
                guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                    throw UpdateError.badResponse
                }
                lastCheckedAt = Date()
                available = Self.newestUpdate(inAppcast: data, currentVersion: currentVersion)
                lastError = nil
            } catch {
                lastCheckedAt = Date()
                if userInitiated {
                    lastError = "Couldn't reach the update feed."
                }
            }
        }
    }

    enum UpdateError: Error { case badResponse }

    // MARK: - Feed parsing (pure)

    /// Picks the highest-versioned appcast item newer than `currentVersion`.
    nonisolated static func newestUpdate(
        inAppcast data: Data,
        currentVersion: String
    ) -> AvailableUpdate? {
        AppcastParser.items(in: data)
            .filter { isVersion($0.version, newerThan: currentVersion) }
            // `max(by:)` wants "is ordered before", i.e. true when $0 is older.
            .max { isVersion($1.version, newerThan: $0.version) }
            .map {
                AvailableUpdate(
                    version: $0.version,
                    downloadURL: $0.downloadURL,
                    releaseNotesURL: $0.releaseNotesURL,
                    publishedAt: $0.publishedAt
                )
            }
    }

    /// Numeric, component-wise: 0.10.0 is newer than 0.9.9, and a longer
    /// version only wins when its extra components are non-zero.
    nonisolated static func isVersion(_ candidate: String, newerThan current: String) -> Bool {
        let lhs = components(candidate)
        let rhs = components(current)
        for index in 0..<max(lhs.count, rhs.count) {
            let left = index < lhs.count ? lhs[index] : 0
            let right = index < rhs.count ? rhs[index] : 0
            if left != right { return left > right }
        }
        return false
    }

    private nonisolated static func components(_ version: String) -> [Int] {
        version
            .split(whereSeparator: { !$0.isNumber })
            .compactMap { Int($0) }
    }
}
