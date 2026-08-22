import Foundation

/// One adapter for every Claude-family CLI, driven by a `HookFamilyCLI`
/// descriptor. Detection, install, repair and uninstall are identical across
/// them; only paths and the hook-server route differ.
struct HookFamilyAdapter: CLIAdapter {
    let cli: HookFamilyCLI
    private let homeDirectory: URL

    init(cli: HookFamilyCLI, homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.cli = cli
        self.homeDirectory = homeDirectory
    }

    private var fileManager: FileManager { .default }

    var id: String { cli.id }
    var displayName: String { cli.displayName }
    var agentKind: AgentKind { cli.agentKind }

    var settingsURL: URL { cli.settingsURL(homeDirectory: homeDirectory) }

    // MARK: - CLIAdapter

    func detect() -> Bool {
        let home = cli.homeDirectory.reduce(homeDirectory) {
            $0.appendingPathComponent($1, isDirectory: true)
        }
        if fileManager.fileExists(atPath: home.path) { return true }
        return binaryExists()
    }

    func status(hookPort: UInt16) -> AdapterStatus {
        guard detect() else { return .notFound }
        guard let settings = try? readSettings() else { return .needsSetup }
        return HookConfigBuilder.installState(
            settings: settings,
            source: cli.source,
            port: hookPort
        )
    }

    func installHooks(hookPort: UInt16) throws {
        let existing = (try? readSettings()) ?? [:]
        try backupIfNeeded()
        let merged = HookConfigBuilder.merged(
            existing: existing,
            source: cli.source,
            port: hookPort,
            disablesTerminalTitle: cli.disablesTerminalTitle
        )
        try writeSettings(merged)
        AppLog.telemetry.info("\(displayName) hooks installed (port \(hookPort))")
    }

    func uninstallHooks() throws {
        switch cli.configStyle {
        case .ownFile:
            // The whole file is ours; removing it leaves nothing behind.
            try? fileManager.removeItem(at: settingsURL)
        case .sharedFile:
            guard let existing = try? readSettings() else { return }
            try writeSettings(HookConfigBuilder.stripped(existing: existing))
        }
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
        try fileManager.createDirectory(
            at: settingsURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try JSONSerialization.data(
            withJSONObject: settings,
            options: [.prettyPrinted, .sortedKeys]
        )
        try data.write(to: settingsURL, options: .atomic)
    }

    /// One-time safety copy before we ever touch a file we did not create.
    private func backupIfNeeded() throws {
        guard case .sharedFile = cli.configStyle else { return }
        let backupURL = settingsURL
            .deletingLastPathComponent()
            .appendingPathComponent(settingsURL.lastPathComponent + ".tokenisland-backup")
        guard fileManager.fileExists(atPath: settingsURL.path),
              !fileManager.fileExists(atPath: backupURL.path)
        else {
            return
        }
        try fileManager.copyItem(at: settingsURL, to: backupURL)
    }

    private func binaryExists() -> Bool {
        let roots = [
            "/usr/local/bin",
            "/opt/homebrew/bin",
            (homeDirectory.path as NSString).appendingPathComponent(".local/bin")
        ]
        for root in roots {
            for name in cli.binaryNames
            where fileManager.isExecutableFile(atPath: (root as NSString).appendingPathComponent(name)) {
                return true
            }
        }
        return false
    }

    func conflictingApprovalHooks() -> [String] {
        guard let data = try? Data(contentsOf: settingsURL),
              let settings = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        else { return [] }
        return HookConfigBuilder.foreignApprovalHooks(settings: settings)
    }

}
