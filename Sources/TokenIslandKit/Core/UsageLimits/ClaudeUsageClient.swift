import Foundation

protocol ClaudeUsageFetching: Sendable {
    func fetch(allowsInteraction: Bool) async throws -> UsageLimitsSnapshot
}

/// Typed failures, bounded retry on token rotation, and provider-directed
/// rate-limit handling. No request bodies, credentials, or raw errors logged.
actor ClaudeUsageClient: ClaudeUsageFetching {
    private let credentials: any ClaudeUsageCredentialProviding
    private let session: URLSession
    private let now: @Sendable () -> Date

    init(
        credentials: any ClaudeUsageCredentialProviding = ClaudeUsageCredentials(),
        session: URLSession = .shared,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.credentials = credentials
        self.session = session
        self.now = now
    }

    func fetch(allowsInteraction: Bool) async throws -> UsageLimitsSnapshot {
        let credential: ClaudeUsageCredential
        do {
            credential = try await credentials.load(allowsInteraction: false)
        } catch ClaudeUsageIssue.accessRequired where allowsInteraction {
            // Only an explicit Connect action may invoke Keychain interaction.
            credential = try await credentials.load(allowsInteraction: true)
        }
        if credential.expiresAt.map({ $0 <= now() }) ?? false {
            // Expiry metadata is a hint; only the provider can decide whether
            // this token is accepted. Do not invent a login failure without
            // trying the read-only usage request.
            AppLog.app.info("Claude usage credential has past expiry metadata; checking provider")
        }
        var reply = try await request(token: credential.accessToken)
        AppLog.app.info("Claude usage response status: \(reply.response.statusCode, privacy: .public)")
        if reply.response.statusCode == 401 {
            // The CLI may have rotated its token during the first request.
            // Re-read once, without opening another prompt, and retry only
            // when a different usable token actually appeared.
            let renewed = try await credentials.load(allowsInteraction: false)
            guard renewed.accessToken != credential.accessToken
            else { throw ClaudeUsageIssue.signInRequired }
            reply = try await request(token: renewed.accessToken)
        }
        switch reply.response.statusCode {
        case 200:
            let fetchedAt = now()
            guard let object = try? JSONSerialization.jsonObject(with: reply.data) as? [String: Any],
                  let snapshot = ClaudeUsageDecoder.snapshot(fromUsageJSON: object, fetchedAt: fetchedAt)
            else { throw ClaudeUsageIssue.invalidResponse }
            return snapshot
        case 401: throw ClaudeUsageIssue.signInRequired
        case 403: throw ClaudeUsageIssue.forbidden
        case 429:
            throw ClaudeUsageIssue.rateLimited(retryAt: Self.retryDate(
                header: reply.response.value(forHTTPHeaderField: "Retry-After"), now: now()
            ))
        default: throw ClaudeUsageIssue.serverUnavailable
        }
    }

    private func request(token: String) async throws -> (data: Data, response: HTTPURLResponse) {
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/api/oauth/usage")!)
        request.httpMethod = "GET"
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.timeoutInterval = 10
        do {
            let (data, response) = try await session.data(for: request)
            guard let response = response as? HTTPURLResponse else { throw ClaudeUsageIssue.invalidResponse }
            return (data, response)
        } catch let issue as ClaudeUsageIssue {
            throw issue
        } catch {
            if Task.isCancelled || (error as? URLError)?.code == .cancelled { throw CancellationError() }
            throw ClaudeUsageIssue.networkUnavailable
        }
    }

    static func retryDate(header: String?, now: Date) -> Date {
        if let header, let seconds = Double(header), seconds.isFinite, seconds >= 0 {
            return now.addingTimeInterval(min(max(seconds, 1), Date.distantFuture.timeIntervalSince(now)))
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        if let header, let date = formatter.date(from: header) {
            return max(date, now.addingTimeInterval(1))
        }
        return now.addingTimeInterval(60)
    }
}
