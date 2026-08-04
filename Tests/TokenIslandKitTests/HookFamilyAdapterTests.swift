import XCTest
@testable import TokenIslandKit

/// Installing into another CLI's configuration is the most destructive thing
/// this app does. These cover the guarantees that make it safe: only our
/// entries change, a backup exists first, and uninstall leaves the file as it
/// was — including a competing agent monitor's hooks in the same file.
final class HookFamilyAdapterTests: XCTestCase {
    private var home: URL!

    override func setUpWithError() throws {
        home = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("hook-family-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: home)
    }

    private var qwen: HookFamilyCLI {
        try! XCTUnwrap(HookFamilyCLI.roster.first { $0.id == "qwen-code" })
    }

    private func write(_ json: [String: Any], to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try JSONSerialization.data(withJSONObject: json).write(to: url)
    }

    private func read(_ url: URL) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    }

    /// The real shape from `~/.qwen/settings.json`: another monitor's bridge
    /// already registered on every event.
    private var foreignSettings: [String: Any] {
        [
            "hooks": [
                "PreToolUse": [
                    ["hooks": [["command": "/Users/dev/.vibe-island/bin/bridge --source qwen", "type": "command"]],
                     "matcher": "*"]
                ],
                "SessionStart": [
                    ["hooks": [["command": "/Users/dev/.vibe-island/bin/bridge --source qwen", "type": "command"]]]
                ]
            ],
            "theme": "dark"
        ]
    }

    func testInstallAddsOurHooksWithoutTouchingAnotherApps() throws {
        let adapter = HookFamilyAdapter(cli: qwen, homeDirectory: home)
        try write(foreignSettings, to: adapter.settingsURL)

        try adapter.installHooks(hookPort: 47791)

        let settings = try read(adapter.settingsURL)
        let hooks = try XCTUnwrap(settings["hooks"] as? [String: Any])
        let preTool = try XCTUnwrap(hooks["PreToolUse"] as? [[String: Any]])
        XCTAssertEqual(preTool.count, 2, "their entry stays, ours is added")
        XCTAssertEqual(preTool.filter { HookConfigBuilder.ownsGroup($0) }.count, 1)
        XCTAssertEqual(settings["theme"] as? String, "dark", "unrelated settings survive")

        let ours = try XCTUnwrap(preTool.first { HookConfigBuilder.ownsGroup($0) })
        let command = try XCTUnwrap(
            ((ours["hooks"] as? [[String: Any]])?.first?["command"] as? String)
        )
        XCTAssertTrue(command.contains("/hook/qwen"), "each CLI posts on its own route")
        XCTAssertEqual(adapter.status(hookPort: 47791), .active)
    }

    func testInstallBacksUpAForeignFileOnce() throws {
        let adapter = HookFamilyAdapter(cli: qwen, homeDirectory: home)
        try write(foreignSettings, to: adapter.settingsURL)
        let backup = adapter.settingsURL
            .deletingLastPathComponent()
            .appendingPathComponent("settings.json.tokenisland-backup")

        try adapter.installHooks(hookPort: 47791)
        let firstBackup = try Data(contentsOf: backup)
        try adapter.installHooks(hookPort: 47791)

        XCTAssertEqual(try Data(contentsOf: backup), firstBackup, "the backup is the pre-install state")
        let restored = try XCTUnwrap(
            JSONSerialization.jsonObject(with: firstBackup) as? [String: Any]
        )
        let hooks = try XCTUnwrap(restored["hooks"] as? [String: Any])
        let preTool = try XCTUnwrap(hooks["PreToolUse"] as? [[String: Any]])
        XCTAssertEqual(preTool.count, 1, "backup predates our entry")
    }

    func testUninstallRestoresTheFileToTheirEntriesOnly() throws {
        let adapter = HookFamilyAdapter(cli: qwen, homeDirectory: home)
        try write(foreignSettings, to: adapter.settingsURL)

        try adapter.installHooks(hookPort: 47791)
        try adapter.uninstallHooks()

        let settings = try read(adapter.settingsURL)
        let hooks = try XCTUnwrap(settings["hooks"] as? [String: Any])
        XCTAssertEqual((hooks["PreToolUse"] as? [[String: Any]])?.count, 1)
        XCTAssertNil(hooks["Stop"], "events we introduced are removed entirely")
        XCTAssertEqual(settings["theme"] as? String, "dark")
        XCTAssertEqual(adapter.status(hookPort: 47791), .needsSetup)
    }

    func testPortChangeIsReportedAsRepairable() throws {
        let adapter = HookFamilyAdapter(cli: qwen, homeDirectory: home)
        try adapter.installHooks(hookPort: 47791)
        guard case .needsRepair = adapter.status(hookPort: 50000) else {
            return XCTFail("a moved hook port must be repairable, got \(adapter.status(hookPort: 50000))")
        }
        try adapter.installHooks(hookPort: 50000)
        XCTAssertEqual(adapter.status(hookPort: 50000), .active)
    }

    /// Copilot reads a directory of hook files, so we own one outright — no
    /// shared file, nothing to merge, and uninstall is a delete.
    func testCopilotOwnsItsOwnFile() throws {
        let copilot = try XCTUnwrap(HookFamilyCLI.roster.first { $0.id == "copilot-cli" })
        let adapter = HookFamilyAdapter(cli: copilot, homeDirectory: home)

        try adapter.installHooks(hookPort: 47791)
        XCTAssertEqual(adapter.settingsURL.lastPathComponent, "tokenisland.json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: adapter.settingsURL.path))

        try adapter.uninstallHooks()
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: adapter.settingsURL.path),
            "our own file goes away completely"
        )
    }

    func testUndetectedCLIReportsNotFound() {
        let adapter = HookFamilyAdapter(cli: qwen, homeDirectory: home)
        XCTAssertEqual(adapter.status(hookPort: 47791), .notFound, "no config dir, no binary")
    }
}
