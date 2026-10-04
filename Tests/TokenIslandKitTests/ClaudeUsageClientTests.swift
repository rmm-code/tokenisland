import XCTest
@testable import TokenIslandKit

private final class UsageHTTPFixture: @unchecked Sendable {
    struct Reply: Sendable {
        var status = 200
        var data = Data(#"{"five_hour":{"utilization":23},"seven_day":{"utilization":12}}"#.utf8)
        var headers: [String: String] = [:]
        var failure: URLError.Code?
    }
    private let lock = NSLock()
    private var responses: [Reply]
    private var requests: [URLRequest] = []
    init(_ replies: [Reply]) { responses = replies }
    func take(_ request: URLRequest) -> Reply {
        lock.withLock {
            requests.append(request)
            guard !responses.isEmpty else { return Reply(failure: .badServerResponse) }
            return responses.removeFirst()
        }
    }
    var captured: [URLRequest] { lock.withLock { requests } }
}

private final class UsageURLProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var fixtures: [String: UsageHTTPFixture] = [:]
    static func register(_ fixture: UsageHTTPFixture, id: String) { lock.withLock { fixtures[id] = fixture } }
    static func remove(_ id: String) { _ = lock.withLock { fixtures.removeValue(forKey: id) } }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let fixture = Self.lock.withLock { Self.fixtures[request.value(forHTTPHeaderField: "X-Usage-Fixture") ?? ""] }
        guard let fixture else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        let reply = fixture.take(request)
        if let code = reply.failure {
            client?.urlProtocol(self, didFailWithError: URLError(code))
            return
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: reply.status,
                                       httpVersion: "HTTP/1.1", headerFields: reply.headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: reply.data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

final class ClaudeUsageClientTests: XCTestCase {
    private actor Credentials: ClaudeUsageCredentialProviding {
        var values: [Result<ClaudeUsageCredential, ClaudeUsageIssue>]
        var flags: [Bool] = []
        init(_ values: [Result<ClaudeUsageCredential, ClaudeUsageIssue>]) { self.values = values }
        func load(allowsInteraction: Bool) async throws -> ClaudeUsageCredential {
            flags.append(allowsInteraction)
            guard !values.isEmpty else { throw ClaudeUsageIssue.signInRequired }
            return try values.removeFirst().get()
        }
    }

    private let date = Date(timeIntervalSince1970: 1_800_000_000)
    private func credential(_ token: String) -> Result<ClaudeUsageCredential, ClaudeUsageIssue> {
        .success(ClaudeUsageCredential(accessToken: token, expiresAt: nil))
    }

    private func session(_ replies: [UsageHTTPFixture.Reply]) -> (URLSession, UsageHTTPFixture) {
        let id = UUID().uuidString
        let fixture = UsageHTTPFixture(replies)
        UsageURLProtocol.register(fixture, id: id)
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [UsageURLProtocol.self]
        config.httpAdditionalHeaders = ["X-Usage-Fixture": id]
        let session = URLSession(configuration: config)
        addTeardownBlock { session.invalidateAndCancel(); UsageURLProtocol.remove(id) }
        return (session, fixture)
    }

    func testCurrentNumbersComeFromAnUncachedAuthenticatedRequest() async throws {
        let (session, fixture) = session([.init()])
        let credentials = Credentials([credential("fixture-token")])
        let fetched = date
        let client = ClaudeUsageClient(credentials: credentials, session: session, now: { fetched })
        let result = try await client.fetch(allowsInteraction: false)
        XCTAssertEqual(result.fiveHourUsedPercent, 23)
        XCTAssertEqual(result.sevenDayUsedPercent, 12)
        XCTAssertEqual(result.fetchedAt, fetched)
        let request = try XCTUnwrap(fixture.captured.first)
        XCTAssertEqual(request.url?.host, "api.anthropic.com")
        XCTAssertEqual(request.cachePolicy, .reloadIgnoringLocalCacheData)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Cache-Control"), "no-cache")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer fixture-token")
    }

    func testTokenRotationIsReReadAndRetriedOnlyOnceWithoutInteraction() async throws {
        let (session, fixture) = session([.init(status: 401), .init()])
        let credentials = Credentials([credential("old"), credential("renewed")])
        let client = ClaudeUsageClient(credentials: credentials, session: session)
        _ = try await client.fetch(allowsInteraction: false)
        XCTAssertEqual(fixture.captured.map { $0.value(forHTTPHeaderField: "Authorization") }, ["Bearer old", "Bearer renewed"])
        let flags = await credentials.flags
        XCTAssertEqual(flags, [false, false])
    }

    func testRepeated401DoesNotRetryOrHideTheAuthenticationFailure() async throws {
        let (session, fixture) = session([.init(status: 401)])
        let credentials = Credentials([credential("unchanged"), credential("unchanged")])
        let client = ClaudeUsageClient(credentials: credentials, session: session)
        do { _ = try await client.fetch(allowsInteraction: false); XCTFail("Expected login error") }
        catch { XCTAssertEqual(error as? ClaudeUsageIssue, .signInRequired) }
        XCTAssertEqual(fixture.captured.count, 1)
    }

    func testExplicitConnectMayPromptButAutomaticChecksNeverDo() async throws {
        let (session, fixture) = session([.init()])
        let credentials = Credentials([.failure(.accessRequired), .failure(.accessRequired), credential("allowed")])
        let client = ClaudeUsageClient(credentials: credentials, session: session)
        do { _ = try await client.fetch(allowsInteraction: false); XCTFail("Expected access error") }
        catch { XCTAssertEqual(error as? ClaudeUsageIssue, .accessRequired) }
        XCTAssertTrue(fixture.captured.isEmpty)
        _ = try await client.fetch(allowsInteraction: true)
        let flags = await credentials.flags
        XCTAssertEqual(flags, [false, false, true])
    }

    func testEveryFetchReadsTheCurrentLoginInsteadOfReusingAProcessToken() async throws {
        let (session, fixture) = session([.init(), .init()])
        let credentials = Credentials([credential("first-account"), credential("second-account")])
        let client = ClaudeUsageClient(credentials: credentials, session: session)
        _ = try await client.fetch(allowsInteraction: false)
        _ = try await client.fetch(allowsInteraction: false)
        XCTAssertEqual(fixture.captured.map { $0.value(forHTTPHeaderField: "Authorization") }, ["Bearer first-account", "Bearer second-account"])
    }

    func testForbiddenRateLimitBadPayloadAndOfflineFailuresAreDistinct() async throws {
        let retryDate = date.addingTimeInterval(120)
        let cases: [(UsageHTTPFixture.Reply, ClaudeUsageIssue)] = [
            (.init(status: 403), .forbidden),
            (.init(status: 429, headers: ["Retry-After": "120"]), .rateLimited(retryAt: retryDate)),
            (.init(status: 503), .serverUnavailable),
            (.init(data: Data("not-json".utf8)), .invalidResponse),
            (.init(failure: .notConnectedToInternet), .networkUnavailable)
        ]
        for (reply, expected) in cases {
            let (session, _) = session([reply])
            let credentials = Credentials([credential("fixture")])
            let current = date
            let client = ClaudeUsageClient(credentials: credentials, session: session, now: { current })
            do { _ = try await client.fetch(allowsInteraction: false); XCTFail("Expected \(expected)") }
            catch { XCTAssertEqual(error as? ClaudeUsageIssue, expected) }
        }
    }

    func testStaleExpiryMetadataDoesNotRejectATokenAcceptedByTheProvider() async throws {
        let (session, fixture) = session([.init()])
        let credentials = Credentials([.success(ClaudeUsageCredential(accessToken: "expired", expiresAt: date.addingTimeInterval(-1)))])
        let current = date
        let client = ClaudeUsageClient(credentials: credentials, session: session, now: { current })
        let result = try await client.fetch(allowsInteraction: false)
        XCTAssertEqual(result.fiveHourUsedPercent, 23)
        XCTAssertEqual(fixture.captured.count, 1)
    }

    func testCancellationDoesNotInventAnOfflineError() async throws {
        let (session, _) = session([.init(failure: .cancelled)])
        let credentials = Credentials([credential("fixture")])
        let client = ClaudeUsageClient(credentials: credentials, session: session)
        do { _ = try await client.fetch(allowsInteraction: false); XCTFail("Expected cancellation") }
        catch { XCTAssertTrue(error is CancellationError) }
    }
}
