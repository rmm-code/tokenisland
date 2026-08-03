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

    // MARK: - CLIAdapter

    func detect() -> Bool {
        if fileManager.fileExists(atPath: claudeDirectory.path) { return true }
        return binaryExists()
    }

    func status(hookPort: UInt16) -> AdapterStatus {
        guard detect() else { return .notFound }
        guard let settings = try? readSettings() else { return .needsSetup }
        return ClaudeHookCommand.installState(settings: settings, port: hookPort)
    }

    func installHooks(hookPort: UInt16) throws {
        let existing = (try? readSettings()) ?? [:]
        try backupIfNeeded()
        let merged = ClaudeHookCommand.mergedSettings(existing: existing, port: hookPort)
        try writeSettings(merged)
        AppLog.telemetry.info("Claude Code hooks installed (port \(hookPort))")
    }

    func uninstallHooks() throws {
        guard let existing = try? readSettings() else { return }
        let stripped = ClaudeHookCommand.strippedSettings(existing: existing)
        try writeSettings(stripped)
    }

    // MARK: - Files

    private func readSettings() throws -> [String: Any] {
        guard fileManager.fileExists(atPath: settingsURL.path) else { return [:] }
        let data = try Data(contentsOf: settingsURL)
        guard !data.isEmpty else { return [:] }
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AdapterFileError.unexpectedFormat(settingsURL.lastPathComponent)
        }
        return object
    }

    private func writeSettings(_ settings: [String: Any]) throws {
        try fileManager.createDirectory(at: claudeDirectory, withIntermediateDirectories: true)
        let data = try JSONSerialization.data(
            withJSONObject: settings,
            options: [.prettyPrinted, .sortedKeys]
        )
        try data.write(to: settingsURL, options: .atomic)
    }

    /// One-time safety copy before we ever touch the user's settings.
    private func backupIfNeeded() throws {
        let backupURL = claudeDirectory.appendingPathComponent("settings.json.tokenisland-backup")
        guard fileManager.fileExists(atPath: settingsURL.path),
              !fileManager.fileExists(atPath: backupURL.path) else { return }
        try fileManager.copyItem(at: settingsURL, to: backupURL)
    }

    private func binaryExists() -> Bool {
        let searchPaths = [
            "/usr/local/bin/claude",
            "/opt/homebrew/bin/claude",
            (fileManager.homeDirectoryForCurrentUser.path as NSString)
                .appendingPathComponent(".local/bin/claude")
        ]
        return searchPaths.contains { fileManager.isExecutableFile(atPath: $0) }
    }
}

enum AdapterFileError: Error, LocalizedError {
    case unexpectedFormat(String)

    var errorDescription: String? {
        switch self {
        case .unexpectedFormat(let file):
            "\(file) is not a JSON object — refusing to modify it."
        }
    }
}
