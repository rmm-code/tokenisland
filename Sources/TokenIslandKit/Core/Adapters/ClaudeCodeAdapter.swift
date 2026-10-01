import Foundation

/// Reference adapter: Claude Code. Installs marker-tagged hook entries into
/// `~/.claude/settings.json` (user scope) so every session on this machine
/// reports in, regardless of project.
struct ClaudeCodeAdapter: CLIAdapter {
    let id = "claude-code"
    let displayName = "Claude Code"
    let agentKind: AgentKind = .claude

    private let claudeDirectory: URL

    /// FileManager is used via `.default` inline; only the home directory is
    /// injectable (tests point it at a temp dir).
    private var fileManager: FileManager { .default }

    init(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.claudeDirectory = homeDirectory.appendingPathComponent(".claude", isDirectory: true)
    }

    var settingsURL: URL {
        claudeDirectory.appendingPathComponent("settings.json")
    }

    private var settingsFile: HookSettingsFile { HookSettingsFile(url: settingsURL) }

    // MARK: - CLIAdapter

    func detect() -> Bool {
        if fileManager.fileExists(atPath: claudeDirectory.path) { return true }
        return binaryExists()
    }

    func status(hookPort: UInt16) -> AdapterStatus {
        guard detect() else { return .notFound }
        do {
            return ClaudeHookCommand.installState(settings: try settingsFile.read(), port: hookPort)
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    func installHooks(hookPort: UInt16) throws {
        let existing = try settingsFile.read()
        try settingsFile.backupIfNeeded()
        let merged = ClaudeHookCommand.mergedSettings(existing: existing, port: hookPort)
        try settingsFile.write(merged)
        AppLog.telemetry.info("Claude Code hooks installed (port \(hookPort))")
    }

    func uninstallHooks() throws {
        guard fileManager.fileExists(atPath: settingsURL.path) else { return }
        let existing = try settingsFile.read()
        let stripped = ClaudeHookCommand.strippedSettings(existing: existing)
        try settingsFile.write(stripped)
    }

    // MARK: - Files

    private func binaryExists() -> Bool {
        let searchPaths = [
            "/usr/local/bin/claude",
            "/opt/homebrew/bin/claude",
            (fileManager.homeDirectoryForCurrentUser.path as NSString)
                .appendingPathComponent(".local/bin/claude")
        ]
        return searchPaths.contains { fileManager.isExecutableFile(atPath: $0) }
    }

    func conflictingApprovalHooks() -> [String] {
        guard let data = try? Data(contentsOf: settingsURL),
              let settings = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        else { return [] }
        return HookConfigBuilder.foreignApprovalHooks(settings: settings)
    }
}
