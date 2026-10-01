import Foundation

/// Shared safe file handling for hook integrations. The descriptor chooses
/// configuration paths and the dialect profile chooses the installed schema.
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
    private var settingsFile: HookSettingsFile { HookSettingsFile(url: settingsURL) }

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
        do {
            return HookConfigBuilder.installState(settings: try settingsFile.read(), source: cli.source, port: hookPort)
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    func installHooks(hookPort: UInt16) throws {
        let existing = try settingsFile.read()
        if case .sharedFile = cli.configStyle { try settingsFile.backupIfNeeded() }
        let merged = HookConfigBuilder.merged(
            existing: existing,
            source: cli.source,
            port: hookPort,
            disablesTerminalTitle: cli.disablesTerminalTitle
        )
        try settingsFile.write(merged)
        AppLog.telemetry.info("\(displayName) hooks installed (port \(hookPort))")
    }

    func uninstallHooks() throws {
        guard fileManager.fileExists(atPath: settingsURL.path) else { return }
        let stripped = HookConfigBuilder.stripped(existing: try settingsFile.read())
        switch cli.configStyle {
        case .ownFile:
            if stripped.isEmpty {
                try fileManager.removeItem(at: settingsURL)
            } else {
                try settingsFile.write(stripped)
            }
        case .sharedFile:
            try settingsFile.write(stripped)
        }
    }

    // MARK: - Files

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
        return HookConfigBuilder.foreignApprovalHooks(settings: settings, source: cli.source)
    }

}
