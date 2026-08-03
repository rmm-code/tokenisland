import XCTest
@testable import TokenIslandKit

/// Session titles and "You:" lines must show what the person typed — not the
/// blocks the CLI injects into the same user turn.
final class SessionTextTests: XCTestCase {
    func testStripsAttachmentPlaceholders() {
        let raw = "[Image: original 2556x1580, displayed at 2000x1236. Multiply coordinates by 1.28.] what about this one?"
        XCTAssertEqual(SessionText.sanitizedPrompt(raw, limit: 160), "what about this one?")
    }

    func testStripsInjectedBlocks() {
        let raw = """
        <task-notification>
        <task-id>a728691b0e0960cd7</task-id>
        <status>completed</status>
        </task-notification>
        Fix the top gap please
        """
        XCTAssertEqual(SessionText.sanitizedPrompt(raw, limit: 160), "Fix the top gap please")
    }

    func testUnclosedBlockDropsTheRemainder() {
        let raw = "Ship the release <system-reminder>never show this to the user"
        XCTAssertEqual(SessionText.sanitizedPrompt(raw, limit: 160), "Ship the release")
    }

    func testTurnMadeOnlyOfInjectedContentIsDropped() {
        let raw = "<system-reminder>background context</system-reminder>\n[Image: 100x100]"
        XCTAssertNil(
            SessionText.sanitizedPrompt(raw, limit: 160),
            "an injected-only turn must not become the session title"
        )
    }

    func testKeepsOrdinaryProseIncludingBrackets() {
        let raw = "Rename [beta] to [stable] in the release notes"
        XCTAssertEqual(
            SessionText.sanitizedPrompt(raw, limit: 160),
            "Rename [beta] to [stable] in the release notes",
            "only attachment placeholders are stripped, not every bracket"
        )
    }

    func testCollapsesWhitespaceAndTruncates() {
        let raw = "add   caching\n\nto the analytics endpoint"
        XCTAssertEqual(SessionText.sanitizedPrompt(raw, limit: 12), "add caching…")
    }
}
