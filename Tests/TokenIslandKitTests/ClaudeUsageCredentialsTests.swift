import XCTest
@testable import TokenIslandKit

final class ClaudeUsageCredentialsTests: XCTestCase {
    private func data(_ token: String) -> Data {
        Data("{\"claudeAiOauth\":{\"accessToken\":\"\(token)\"}}".utf8)
    }

    func testCurrentKeychainLoginWinsOverAnOldCredentialsFile() async throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("usage-old-login-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: file) }
        try data("old-file").write(to: file)
        let current = data("current-keychain")
        let credentials = ClaudeUsageCredentials(fileURL: file, readKeychain: { _ in .data(current) })
        let credential = try await credentials.load(allowsInteraction: false)
        XCTAssertEqual(credential.accessToken, "current-keychain")
    }

    func testInaccessibleKeychainDoesNotSilentlySelectAnotherAccountFromAFile() async throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("usage-inaccessible-login-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: file) }
        try data("different-account").write(to: file)
        let credentials = ClaudeUsageCredentials(fileURL: file, readKeychain: { _ in .failed(.accessRequired) })
        do { _ = try await credentials.load(allowsInteraction: false); XCTFail("Expected access error") }
        catch { XCTAssertEqual(error as? ClaudeUsageIssue, .accessRequired) }
    }

    func testCredentialsFileFallbackWorksWhenKeychainHasNoLogin() async throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("usage-file-login-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: file) }
        try data("file-login").write(to: file)
        let credentials = ClaudeUsageCredentials(fileURL: file, readKeychain: { _ in .notFound })
        let credential = try await credentials.load(allowsInteraction: false)
        XCTAssertEqual(credential.accessToken, "file-login")
    }

    func testRetryAfterLongIntervalsAndHTTPDatesAreNotShortened() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        XCTAssertEqual(ClaudeUsageClient.retryDate(header: "7200", now: now), now.addingTimeInterval(7200))
        XCTAssertEqual(ClaudeUsageClient.retryDate(header: "Fri, 15 Jan 2027 10:00:00 GMT", now: now), now.addingTimeInterval(7200))
        XCTAssertEqual(ClaudeUsageClient.retryDate(header: "invalid", now: now), now.addingTimeInterval(60))
    }

    func testCredentialExpirySupportsSecondsAndMilliseconds() throws {
        for timestamp in [1_800_000_000.0, 1_800_000_000_000.0] {
            let bytes = try JSONSerialization.data(withJSONObject: [
                "claudeAiOauth": ["accessToken": "fixture", "expiresAt": timestamp]
            ])
            let decoded = try ClaudeUsageCredentials.decode(bytes)
            XCTAssertEqual(decoded.expiresAt, Date(timeIntervalSince1970: 1_800_000_000))
        }
    }
}
