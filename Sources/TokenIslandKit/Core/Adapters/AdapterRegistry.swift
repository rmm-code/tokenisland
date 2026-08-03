import Combine
import Foundation

/// Owns the supported CLI adapters, their integration status, and the
/// auto-configure pass for hook-based integrations.
@MainActor
final class AdapterRegistry: ObservableObject {
    struct Entry: Identifiable {
        let adapter: any CLIAdapter
        var status: AdapterStatus

        var id: String { adapter.id }
    }

    @Published private(set) var entries: [Entry] = []
    @Published private(set) var lastError: String?

    private let hookPort: UInt16

    init(hookPort: UInt16 = AppConstants.defaultHookPort) {
        self.hookPort = hookPort
        self.entries = Self.roster().map { Entry(adapter: $0, status: .notFound) }
    }

    private static func roster() -> [any CLIAdapter] {
        [ClaudeCodeAdapter(), CodexAdapter(), GeminiAdapter()]
    }

    /// Everything present on this machine (for onboarding's "All Set" list).
    var detectedEntries: [Entry] {
        entries.filter { $0.status.isDetected }
    }

    var activeCount: Int {
        entries.count { $0.status.isActive }
    }

    func refreshStatuses() {
        for index in entries.indices {
            entries[index].status = entries[index].adapter.status(hookPort: hookPort)
        }
    }

    /// Installs or repairs hooks where supported. Safe to call on every
    /// launch: adapters are idempotent and only touch their own entries.
    func autoConfigure() {
        refreshStatuses()
        for index in entries.indices {
            switch entries[index].status {
            case .needsSetup, .needsRepair:
                install(at: index)
            case .notFound, .active, .detectedOnly, .failed:
                continue
            }
        }
    }

    func install(adapterID: String) {
        guard let index = entries.firstIndex(where: { $0.id == adapterID }) else { return }
        install(at: index)
    }

    func uninstall(adapterID: String) {
        guard let index = entries.firstIndex(where: { $0.id == adapterID }) else { return }
        do {
            try entries[index].adapter.uninstallHooks()
            entries[index].status = entries[index].adapter.status(hookPort: hookPort)
        } catch {
            lastError = "\(entries[index].adapter.displayName): \(error.localizedDescription)"
        }
    }

    private func install(at index: Int) {
        let adapter = entries[index].adapter
        do {
            try adapter.installHooks(hookPort: hookPort)
            entries[index].status = adapter.status(hookPort: hookPort)
        } catch {
            let message = error.localizedDescription
            entries[index].status = .failed(message)
            lastError = "\(adapter.displayName): \(message)"
            AppLog.telemetry.error("Hook install failed for \(adapter.id): \(message)")
        }
    }
}
