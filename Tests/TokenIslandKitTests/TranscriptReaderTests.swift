import XCTest
@testable import TokenIslandKit

/// Transcript shapes taken from real Claude Code 2.1.x files: no `summary`
/// records at all, multi-hundred-KB tool results, and small per-turn sidecar
/// records that carry the title and the prompt.
final class TranscriptReaderTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("transcript-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func write(_ lines: [String], name: String = "session.jsonl") throws -> String {
        let url = directory.appendingPathComponent(name)
        try lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
        return url.path
    }

    private func toolResultLine(bytes: Int) -> String {
        let blob = String(repeating: "x", count: bytes)
        return #"{"type":"user","message":{"role":"user","content":[{"type":"tool_result","content":"\#(blob)"}]}}"#
    }

    func testReadsTitleAndPromptFromSidecarRecords() throws {
        let path = try write([
            #"{"type":"custom-title","customTitle":"Topside cutoff bugs","sessionId":"s1"}"#,
            #"{"type":"last-prompt","lastPrompt":"Fix them, use subagents if needed","sessionId":"s1"}"#,
            #"{"type":"assistant","message":{"role":"assistant","model":"claude-opus-5","content":[{"type":"text","text":"Done."}]}}"#
        ])

        let digest = try XCTUnwrap(TranscriptReader.digest(atPath: path))
        XCTAssertEqual(digest.title, "Topside cutoff bugs")
        XCTAssertEqual(digest.lastUserPrompt, "Fix them, use subagents if needed")
        XCTAssertEqual(digest.model, "claude-opus-5")
    }

    /// The regression that left live sessions reading "New session": every
    /// conversation record in the read window is a tool result, so the title
    /// has to come from the sidecars.
    func testSurvivesAWindowFullOfOversizedToolResults() throws {
        let path = try write([
            #"{"type":"custom-title","customTitle":"Promo video","sessionId":"s1"}"#,
            #"{"type":"last-prompt","lastPrompt":"continue the promo video.","sessionId":"s1"}"#,
            toolResultLine(bytes: 120_000),
            toolResultLine(bytes: 120_000)
        ])

        let digest = try XCTUnwrap(TranscriptReader.digest(atPath: path))
        XCTAssertEqual(digest.title, "Promo video", "a tail full of tool results must not blank the title")
        XCTAssertEqual(digest.lastUserPrompt, "continue the promo video.")
    }

    func testNewestSidecarWins() throws {
        let path = try write([
            #"{"type":"custom-title","customTitle":"First topic","sessionId":"s1"}"#,
            #"{"type":"last-prompt","lastPrompt":"first ask","sessionId":"s1"}"#,
            #"{"type":"custom-title","customTitle":"Second topic","sessionId":"s1"}"#,
            #"{"type":"last-prompt","lastPrompt":"second ask","sessionId":"s1"}"#
        ])

        let digest = try XCTUnwrap(TranscriptReader.digest(atPath: path))
        XCTAssertEqual(digest.title, "Second topic")
        XCTAssertEqual(digest.lastUserPrompt, "second ask")
    }

    func testSidecarPromptIsSanitized() throws {
        let path = try write([
            #"{"type":"last-prompt","lastPrompt":"[Image: original 3024x1964, displayed at 2000x1299.] what about this one?","sessionId":"s1"}"#
        ])

        let digest = try XCTUnwrap(TranscriptReader.digest(atPath: path))
        XCTAssertEqual(digest.lastUserPrompt, "what about this one?")
    }

    func testOlderSummaryRecordsStillWork() throws {
        let path = try write([
            #"{"type":"summary","summary":"Legacy summary title"}"#,
            #"{"type":"user","message":{"role":"user","content":"hello there"}}"#
        ])

        let digest = try XCTUnwrap(TranscriptReader.digest(atPath: path))
        XCTAssertEqual(digest.title, "Legacy summary title", "older CLI versions must keep working")
        XCTAssertEqual(digest.lastUserPrompt, "hello there")
    }

    func testMissingFileIsNotAnError() {
        XCTAssertNil(TranscriptReader.digest(atPath: directory.appendingPathComponent("nope.jsonl").path))
    }
}
