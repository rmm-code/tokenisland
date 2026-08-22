import Foundation

enum AdapterIntegrationMode: Equatable, Sendable {
    /// TokenIsland installs and removes CLI hooks.
    case managedHooks
    /// TokenIsland passively watches artifacts written by the CLI.
    case passiveWatcher
}

/// Install/health state of one CLI integration, rendered on the
/// Integrations settings pane.
enum AdapterStatus: Equatable, Sendable {
    /// CLI not found on this machine.
    case notFound
    /// CLI found, hooks not installed yet.
    case needsSetup
    /// Hooks installed and pointing at the current hook-server port.
    case active
    /// CLI found; session hooks for it aren't implemented yet.
    case detectedOnly
    /// Hooks installed but stale/broken (wrong port, missing events).
    case needsRepair(String)
    /// Install attempted and failed.
    case failed(String)

    var label: String {
        switch self {
        case .notFound: "CLI not found"
        case .needsSetup: "Needs setup"
        case .active: "Active"
        case .detectedOnly: "Detected"
        case .needsRepair: "Needs repair"
        case .failed: "Failed"
        }
    }

    var isActive: Bool {
        if case .active = self { return true }
        return false
    }

    var isDetected: Bool {
        switch self {
        case .notFound: false
        case .needsSetup, .active, .detectedOnly, .needsRepair, .failed: true
        }
    }
}

/// One supported CLI integration. Adapters own everything CLI-specific:
/// detection, hook install/repair/uninstall, and payload dialect.
protocol CLIAdapter: Sendable {
    /// Stable identifier ("claude-code").
    var id: String { get }
    /// Display name ("Claude Code").
    var displayName: String { get }
    var agentKind: AgentKind { get }
    var integrationMode: AdapterIntegrationMode { get }

    /// Whether the CLI is installed on this machine.
    func detect() -> Bool
    /// Current integration status (detect + inspect installed hooks).
    func status(hookPort: UInt16) -> AdapterStatus
    /// Install or refresh hooks so events reach `hookPort`. Idempotent.
    func installHooks(hookPort: UInt16) throws
    /// Remove only our hook entries, leaving user configuration untouched.
    func uninstallHooks() throws
    /// Other apps' approval-answering hooks found in the same config. Only one
    /// app may answer a `PermissionRequest`, so this is worth showing.
    func conflictingApprovalHooks() -> [String]
}

extension CLIAdapter {
    /// Most adapters do not share a config file with anyone.
    func conflictingApprovalHooks() -> [String] { [] }
}

extension CLIAdapter {
    var integrationMode: AdapterIntegrationMode { .managedHooks }
}
