import XCTest
@testable import TokenIslandKit

/// The release script writes the appcast the app reads. Nothing else connects
/// them, so a change to either side silently breaks update delivery — these
/// round-trip the real script output through the real parser.
final class ReleasePipelineTests: XCTestCase {
    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func script(_ name: String) throws -> String {
        try String(
            contentsOf: repositoryRoot.appendingPathComponent("Scripts/\(name)"),
            encoding: .utf8
        )
    }

    /// Pulls the appcast heredoc out of release.sh and fills in the shell
    /// variables the way a real run would.
    private func generatedAppcast(version: String) throws -> Data {
        let source = try script("release.sh")
        let start = try XCTUnwrap(source.range(of: "<?xml version=\"1.0\" standalone=\"yes\"?>"))
        let end = try XCTUnwrap(source.range(of: "</rss>"))
        var xml = String(source[start.lowerBound..<end.upperBound])

        for (variable, value) in [
            ("$VERSION", version),
            ("$PUB_DATE", "Sat, 26 Jul 2026 10:00:00 +0000"),
            ("$LENGTH", "8421504"),
            ("$MIN_OS", "14.0"),
            // sign_update emits the signature AND the length together; a
            // template that also wrote its own `length` produced a duplicate
            // attribute, which is invalid XML and silently emptied the feed.
            ("$ENCLOSURE_ATTRS", #"sparkle:edSignature="dGVzdHNpZ25hdHVyZQ==" length="8421504""#),
            ("$FEED_BASE", "https://github.com/rmm-code/tokenisland/releases/download/v\(version)")
        ] {
            xml = xml.replacingOccurrences(of: variable, with: value)
        }
        return Data(xml.utf8)
    }

    func testGeneratedAppcastIsReadableByTheApp() throws {
        let feed = try generatedAppcast(version: "0.2.0")
        let update = try XCTUnwrap(
            UpdateChecker.newestUpdate(inAppcast: feed, currentVersion: "0.1.0"),
            "the app must understand the feed its own release script writes"
        )

        XCTAssertEqual(update.version, "0.2.0")
        XCTAssertEqual(
            update.downloadURL.absoluteString,
            "https://github.com/rmm-code/tokenisland/releases/download/v0.2.0/TokenIsland-0.2.0.zip"
        )
        XCTAssertEqual(
            update.releaseNotesURL?.absoluteString,
            "https://github.com/rmm-code/tokenisland/releases/tag/v0.2.0"
        )
        XCTAssertNotNil(update.publishedAt, "pubDate has to parse or Sparkle sorts wrongly later")
    }

    /// The enclosure's attributes come from exactly one source. Two sources
    /// meant two `length=` attributes, and every parser read the feed as empty
    /// — the app said "up to date" while an update sat on the server.
    func testEnclosureHasNoDuplicateAttributes() throws {
        let xml = String(data: try generatedAppcast(version: "0.2.1"), encoding: .utf8) ?? ""
        let enclosure = try XCTUnwrap(
            xml.range(of: "<enclosure").map { String(xml[$0.lowerBound...].prefix(while: { $0 != ">" })) }
        )
        for attribute in ["length=", "url=", "type=", "sparkle:edSignature="] {
            XCTAssertEqual(
                enclosure.components(separatedBy: attribute).count - 1,
                1,
                "\(attribute) appears more than once — invalid XML"
            )
        }
    }

    func testTheSameFeedOffersNothingToACurrentBuild() throws {
        let feed = try generatedAppcast(version: "0.2.0")
        XCTAssertNil(UpdateChecker.newestUpdate(inAppcast: feed, currentVersion: "0.2.0"))
    }

    /// The feed the app reads and the URL the script publishes to have to be
    /// the same place, or the app checks a page that never updates.
    func testFeedURLMatchesWhereTheScriptPublishes() throws {
        let build = try script("build_app_bundle.sh")
        XCTAssertTrue(
            build.contains("releases/latest/download/appcast.xml"),
            "SUFeedURL must point at the latest release's asset"
        )
        let release = try script("release.sh")
        XCTAssertTrue(
            release.contains("gh release create"),
            "…and the script must publish appcast.xml as an asset of that release"
        )
        XCTAssertTrue(release.contains("'$APPCAST_PATH'"))
    }

    /// Distribution requirements that are easy to lose in a refactor and only
    /// fail once a user's Mac refuses to open the app.
    func testDistributionRequirementsStayInTheBuild() throws {
        let build = try script("build_app_bundle.sh")
        XCTAssertTrue(build.contains("--options runtime"), "notarization requires the hardened runtime")
        XCTAssertTrue(build.contains("--entitlements"), "…which blocks Apple Events without the entitlement")
        XCTAssertTrue(build.contains("--timestamp\""), "…and a secure timestamp for Developer ID builds")

        let entitlements = try String(
            contentsOf: repositoryRoot.appendingPathComponent("Scripts/TokenIsland.entitlements"),
            encoding: .utf8
        )
        XCTAssertTrue(
            entitlements.contains("com.apple.security.automation.apple-events"),
            "click-to-jump drives Terminal through Apple Events"
        )

        let release = try script("release.sh")
        XCTAssertTrue(release.contains("Developer ID Application"), "an Apple Development cert cannot ship")
        XCTAssertTrue(release.contains("notarytool submit"))
        XCTAssertTrue(release.contains("stapler staple"), "the staple must survive being re-zipped")
        XCTAssertTrue(
            release.contains("sign_update"),
            "Sparkle refuses an archive whose EdDSA signature is missing"
        )
        XCTAssertTrue(build.contains("SUPublicEDKey"), "…and verifies it against the key in the bundle")
    }

    /// Two artifacts, two jobs: Sparkle installs the zip, humans download the
    /// DMG (a zip launched from Downloads is App-Translocated, which breaks
    /// in-place updates). The DMG needs its own notarization ticket, and the
    /// site's link only survives new releases if one asset keeps a fixed name.
    func testReleaseShipsBothADiskImageAndAZip() throws {
        let release = try script("release.sh")
        XCTAssertTrue(release.contains("hdiutil create"), "the download artifact is a disk image")
        XCTAssertTrue(release.contains("ln -s /Applications"), "…with a drag target")
        XCTAssertTrue(
            release.contains("notarytool submit \"$DMG_PATH\""),
            "the image needs its own ticket — the app's does not cover it"
        )
        XCTAssertTrue(release.contains("stapler staple \"$DMG_PATH\""))
        XCTAssertTrue(
            release.contains("TokenIsland.dmg"),
            "a fixed-name copy keeps /releases/latest/download working across versions"
        )
        XCTAssertTrue(
            release.contains("TokenIsland-$VERSION.zip"),
            "Sparkle still installs the zip"
        )
    }

    /// Sparkle has to be inside the bundle and signed from the inside out, or
    /// the app either fails to launch or fails notarization.
    func testSparkleIsEmbeddedAndSignedIndependently() throws {
        let build = try script("build_app_bundle.sh")
        XCTAssertTrue(build.contains("CONTENTS_DIR/Frameworks"), "the framework must ship inside the app")
        XCTAssertTrue(build.contains("Sparkle.framework"))
        XCTAssertTrue(
            build.contains("*.xpc"),
            "Sparkle's XPC services need their own signatures — --deep is not enough"
        )
        XCTAssertFalse(
            build.contains("--deep --sign \"$IDENTITY\""),
            "--deep would re-sign nested code with the app's identifier"
        )
    }
}
