import Foundation

/// Codex CLI integration. Codex has no hook mechanism — sessions are read
/// from its rollout files by `CodexSessionWatcher`, so there is nothing to
/// install: detected means covered, and hook install/uninstall are no-ops.
struct CodexAdapter: CLIAdapter {
    let id = "codex"
    let displayName = "Codex"
    let agentKind = AgentKind.codex
    let integrationMode = AdapterIntegrationMode.passiveWatcher

    func detect() -> Bool {
        let fileManager = FileManager.default
        let home = fileManager.homeDirectoryForCurrentUser
        if fileManager.fileExists(atPath: home.appendingPathComponent(".codex").path) {
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
            fileManager.isExecutableFile(atPath: "\($0)/codex")
        }
    }

    func status(hookPort: UInt16) -> AdapterStatus {
        detect() ? .active : .notFound
    }

    func installHooks(hookPort: UInt16) throws {
        // Push-free integration: the rollout watcher covers Codex.
    }

    func uninstallHooks() throws {}
}
