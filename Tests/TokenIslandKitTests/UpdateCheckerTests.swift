import XCTest
@testable import TokenIslandKit

/// Update checking against a Sparkle-format appcast. Feed shapes below are
/// what Sparkle actually publishes, so the same server works unchanged the day
/// the app ships with a Developer ID and Sparkle's installer.
final class UpdateCheckerTests: XCTestCase {
    private func appcast(_ items: String) -> Data {
        Data("""
        <?xml version="1.0" standalone="yes"?>
        <rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
          <channel>
            <title>TokenIsland</title>
            \(items)
          </channel>
        </rss>
        """.utf8)
    }

    private func item(version: String, build: String = "1") -> String {
        """
        <item>
          <title>Version \(version)</title>
          <pubDate>Sat, 26 Jul 2026 10:00:00 +0000</pubDate>
          <sparkle:shortVersionString>\(version)</sparkle:shortVersionString>
          <sparkle:releaseNotesLink>https://tokenisland.app/notes/\(version).html</sparkle:releaseNotesLink>
          <enclosure url="https://tokenisland.app/TokenIsland-\(version).zip"
                     sparkle:version="\(build)" length="1" type="application/octet-stream"/>
        </item>
        """
    }

    // MARK: - Version comparison

    func testVersionComparisonIsNumericNotLexical() {
        XCTAssertTrue(UpdateChecker.isVersion("0.10.0", newerThan: "0.9.9"), "10 > 9, not '1' < '9'")
        XCTAssertTrue(UpdateChecker.isVersion("1.0.0", newerThan: "0.99.99"))
        XCTAssertTrue(UpdateChecker.isVersion("0.2.1", newerThan: "0.2"))
        XCTAssertFalse(UpdateChecker.isVersion("0.2.0", newerThan: "0.2"), "trailing zeros are equal")
        XCTAssertFalse(UpdateChecker.isVersion("0.1.0", newerThan: "0.2.0"))
        XCTAssertFalse(UpdateChecker.isVersion("0.2.0", newerThan: "0.2.0"))
    }

    func testMalformedVersionsDoNotOfferAnUpdate() {
        XCTAssertFalse(UpdateChecker.isVersion("", newerThan: "0.1.0"))
        XCTAssertFalse(UpdateChecker.isVersion("nightly", newerThan: "0.1.0"))
    }

    // MARK: - Feed parsing

    func testPicksTheNewestItemAboveTheRunningVersion() throws {
        let feed = appcast(item(version: "0.1.0") + item(version: "0.3.0") + item(version: "0.2.0"))
        let update = try XCTUnwrap(
            UpdateChecker.newestUpdate(inAppcast: feed, currentVersion: "0.1.0")
        )
        XCTAssertEqual(update.version, "0.3.0", "highest wins regardless of feed order")
        XCTAssertEqual(update.downloadURL.absoluteString, "https://tokenisland.app/TokenIsland-0.3.0.zip")
        XCTAssertEqual(update.releaseNotesURL?.lastPathComponent, "0.3.0.html")
        XCTAssertNotNil(update.publishedAt)
    }

    func testCurrentVersionMeansNoUpdate() {
        let feed = appcast(item(version: "0.1.0") + item(version: "0.2.0"))
        XCTAssertNil(UpdateChecker.newestUpdate(inAppcast: feed, currentVersion: "0.2.0"))
        XCTAssertNil(UpdateChecker.newestUpdate(inAppcast: feed, currentVersion: "0.5.0"), "a dev build is ahead")
    }

    func testItemWithoutADownloadIsSkippedRatherThanCrashing() {
        let broken = appcast("""
        <item><title>Version 9.9.9</title><sparkle:shortVersionString>9.9.9</sparkle:shortVersionString></item>
        """ + item(version: "0.2.0"))
        let update = UpdateChecker.newestUpdate(inAppcast: broken, currentVersion: "0.1.0")
        XCTAssertEqual(update?.version, "0.2.0", "an item with no enclosure cannot be offered")
    }

    func testGarbageFeedIsIgnored() {
        XCTAssertNil(UpdateChecker.newestUpdate(inAppcast: Data("not xml".utf8), currentVersion: "0.1.0"))
        XCTAssertNil(UpdateChecker.newestUpdate(inAppcast: Data(), currentVersion: "0.1.0"))
    }

    func testVersionFallsBackToTheItemTitle() throws {
        let feed = appcast("""
        <item>
          <title>Version 0.4.0</title>
          <enclosure url="https://tokenisland.app/TokenIsland-0.4.0.zip" length="1" type="application/octet-stream"/>
        </item>
        """)
        let update = try XCTUnwrap(
            UpdateChecker.newestUpdate(inAppcast: feed, currentVersion: "0.1.0")
        )
        XCTAssertEqual(update.version, "0.4.0")
    }

    // MARK: - Configuration

    /// A locally built app has no feed. That is reported as unconfigured, not
    /// as "up to date" and not as an error.
    @MainActor
    func testBuildWithoutAFeedIsNotConfigured() {
        let checker = UpdateChecker(bundle: Bundle(for: UpdateCheckerTests.self))
        XCTAssertFalse(checker.isConfigured)
        XCTAssertNil(checker.available)
        XCTAssertNil(checker.lastError)

        checker.checkIfDue(enabled: true)
        XCTAssertFalse(checker.isChecking, "nothing to check, so nothing starts")
    }
}
