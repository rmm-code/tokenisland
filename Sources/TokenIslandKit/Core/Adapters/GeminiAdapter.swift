import Foundation

/// Gemini CLI integration. Sessions are read passively from its per-project
/// artifacts (`~/.gemini/tmp/<hash>/chats/*.json`, `logs.json`) by
/// `GeminiSessionWatcher`, so there is nothing to install: detected means
/// covered, and hook install/uninstall are no-ops.
struct GeminiAdapter: CLIAdapter {
    let id = "gemini-cli"
    let displayName = "Gemini CLI"
    let agentKind = AgentKind.gemini
    let integrationMode = AdapterIntegrationMode.passiveWatcher

    func detect() -> Bool {
        let fileManager = FileManager.default
        let home = fileManager.homeDirectoryForCurrentUser
        if fileManager.fileExists(atPath: home.appendingPathComponent(".gemini").path) {
            return true
        }
        let binDirectories = [
            "/usr/local/bin", "/opt/homebrew/bin", "/usr/bin",
            home.appendingPathComponent(".local/bin").path,
            home.appendingPathComponent("bin").path,
            home.appendingPathComponent(".bun/bin").path,
            home.appendingPathComponent(".npm-global/bin").path
        ]
        return binDirectories.contains {
            fileManager.isExecutableFile(atPath: "\($0)/gemini")
        }
    }

    func status(hookPort: UInt16) -> AdapterStatus {
        detect() ? .active : .notFound
    }

    func installHooks(hookPort: UInt16) throws {
        // Push-free integration: the session watcher covers Gemini.
    }

    func uninstallHooks() throws {}
}
