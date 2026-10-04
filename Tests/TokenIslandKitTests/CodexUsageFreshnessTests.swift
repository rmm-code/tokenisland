import XCTest
@testable import TokenIslandKit

final class CodexUsageFreshnessTests: XCTestCase {
    func testOldRateLimitRecordIsNotMadeFreshByUnrelatedFileWrites() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("usage-codex-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: home) }
        let sessions = home.appendingPathComponent(".codex/sessions")
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        let timestamp = ISO8601DateFormatter().string(from: Date().addingTimeInterval(-3600))
        let record = """
        {"timestamp":"\(timestamp)","type":"event_msg","payload":{"type":"token_count","rate_limits":{"primary":{"used_percent":50,"window_minutes":300,"resets_in_seconds":60}}}}
        {"type":"event_msg","payload":{"type":"unrelated_new_event"}}
        """
        try Data(record.utf8).write(to: sessions.appendingPathComponent("rollout-test.jsonl"))
        XCTAssertTrue(CodexUsageReader.latestWindows(home: home).isEmpty,
                      "A recent file write cannot revive an old usage record or extend its reset date")
    }
}
