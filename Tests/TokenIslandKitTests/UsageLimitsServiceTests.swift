import XCTest
@testable import TokenIslandKit

@MainActor
final class UsageLimitsServiceTests: XCTestCase {
    private final class Clock {
        var date = Date(timeIntervalSince1970: 1_800_000_000)
    }

    private actor Client: ClaudeUsageFetching {
        var responses: [Result<UsageLimitsSnapshot, ClaudeUsageIssue>]
        var interactions: [Bool] = []
        init(_ responses: [Result<UsageLimitsSnapshot, ClaudeUsageIssue>]) { self.responses = responses }
        func fetch(allowsInteraction: Bool) async throws -> UsageLimitsSnapshot {
            interactions.append(allowsInteraction)
            guard !responses.isEmpty else { throw ClaudeUsageIssue.networkUnavailable }
            return try responses.removeFirst().get()
        }
    }

    private func snapshot(at date: Date, reset: Date? = nil) -> UsageLimitsSnapshot {
        UsageLimitsSnapshot(windows: [
            UsageLimitsWindow(key: "five_hour", label: "5h", usedPercent: 23, resetsAt: reset),
            UsageLimitsWindow(key: "seven_day", label: "7d", usedPercent: 12, resetsAt: date.addingTimeInterval(86_400))
        ], fetchedAt: date)
    }

    private func defaults() throws -> UserDefaults {
        let suite = "usage-service-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        return defaults
    }

    func testFailedRefreshClearsOldPercentagesAndReportsTheReason() async throws {
        let clock = Clock()
        let client = Client([.success(snapshot(at: clock.date)), .failure(.networkUnavailable)])
        let store = try defaults()
        let service = UsageLimitsService(defaults: store, client: client, now: { clock.date })
        await service.refreshFromUserAction()
        XCTAssertEqual(service.displayedSnapshot?.fiveHourUsedPercent, 23)
        await service.refreshFromUserAction()
        XCTAssertNil(service.snapshot)
        XCTAssertNil(service.displayedSnapshot)
        XCTAssertEqual(service.issue, .networkUnavailable)
        XCTAssertNil(store.data(forKey: "claudeUsageLimitsSnapshot"), "Account usage must not become a permanent persisted truth")
    }

    func testManualRetryBypassesAutomaticCooldownAndCanConnectImmediately() async throws {
        let clock = Clock()
        let client = Client([.failure(.accessRequired), .success(snapshot(at: clock.date))])
        let service = UsageLimitsService(defaults: try defaults(), client: client, now: { clock.date })
        await service.refreshIfStale()
        await service.refreshIfStale()
        await service.refreshFromUserAction()
        let flags = await client.interactions
        XCTAssertEqual(flags, [false, true])
        XCTAssertEqual(service.displayedSnapshot?.sevenDayUsedPercent, 12)
        XCTAssertNil(service.issue)
    }

    func testAgeAndSleepCannotLeaveAVisibleFreshSnapshot() async throws {
        let clock = Clock()
        let client = Client([.success(snapshot(at: clock.date)), .failure(.networkUnavailable)])
        let service = UsageLimitsService(defaults: try defaults(), client: client, now: { clock.date })
        await service.refreshIfStale()
        clock.date.addTimeInterval(91)
        XCTAssertNil(service.displayedSnapshot, "Freshness is checked even before a timer fires after wake")
        await service.refreshIfStale()
        XCTAssertNil(service.snapshot)
        let count = await client.interactions.count
        XCTAssertEqual(count, 2)
    }

    func testCrossingResetRefreshesBeforeTheNormalMinuteInterval() async throws {
        let clock = Clock()
        let first = snapshot(at: clock.date, reset: clock.date.addingTimeInterval(20))
        let next = snapshot(at: clock.date.addingTimeInterval(21), reset: clock.date.addingTimeInterval(3600))
        let client = Client([.success(first), .success(next)])
        let service = UsageLimitsService(defaults: try defaults(), client: client, now: { clock.date })
        await service.refreshIfStale()
        clock.date.addTimeInterval(21)
        XCTAssertNil(service.displayedSnapshot?.fiveHourUsedPercent)
        XCTAssertEqual(service.displayedSnapshot?.sevenDayUsedPercent, 12)
        await service.refreshIfStale()
        let count = await client.interactions.count
        XCTAssertEqual(count, 2)
        XCTAssertEqual(service.displayedSnapshot, next)
    }

    func testProviderRetryAfterAlsoBlocksManualClicksUntilItsDeadline() async throws {
        let clock = Clock()
        let deadline = clock.date.addingTimeInterval(120)
        let client = Client([.failure(.rateLimited(retryAt: deadline)),
                             .success(snapshot(at: deadline))])
        let service = UsageLimitsService(defaults: try defaults(), client: client, now: { clock.date })
        await service.refreshIfStale()
        XCTAssertFalse(service.canRefresh)
        await service.refreshFromUserAction()
        let before = await client.interactions.count
        XCTAssertEqual(before, 1)
        clock.date = deadline
        XCTAssertTrue(service.canRefresh)
        await service.refreshIfStale()
        XCTAssertNotNil(service.displayedSnapshot)
    }

    func testAutomaticChecksResumeAtOneMinuteWithoutReopeningThePanel() async throws {
        let clock = Clock()
        let client = Client([.success(snapshot(at: clock.date)), .success(snapshot(at: clock.date.addingTimeInterval(60)))])
        let service = UsageLimitsService(defaults: try defaults(), client: client, now: { clock.date })
        await service.refreshIfStale()
        clock.date.addTimeInterval(59)
        await service.refreshIfStale()
        clock.date.addTimeInterval(1)
        await service.refreshIfStale()
        let flags = await client.interactions
        XCTAssertEqual(flags, [false, false])
        XCTAssertEqual(service.lastSuccessAt, clock.date)
    }

    private actor HeldClient: ClaudeUsageFetching {
        var requests = 0
        var continuation: CheckedContinuation<UsageLimitsSnapshot, Never>?
        func fetch(allowsInteraction: Bool) async throws -> UsageLimitsSnapshot {
            requests += 1
            return await withCheckedContinuation { continuation = $0 }
        }
        func finish(_ snapshot: UsageLimitsSnapshot) { continuation?.resume(returning: snapshot); continuation = nil }
    }

    func testOverlappingAutomaticAndManualRefreshesUseOneRequest() async throws {
        let clock = Clock()
        let client = HeldClient()
        let service = UsageLimitsService(defaults: try defaults(), client: client, now: { clock.date })
        let first = Task { await service.refreshIfStale() }
        for _ in 0..<100 where !service.isRefreshing { await Task.yield() }
        await service.refreshFromUserAction()
        for _ in 0..<100 where await client.requests == 0 { await Task.yield() }
        let count = await client.requests
        XCTAssertEqual(count, 1)
        await client.finish(snapshot(at: clock.date))
        await first.value
        XCTAssertFalse(service.isRefreshing)
    }
}
