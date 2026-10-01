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
    @Published private(set) var disabledAdapterIDs: Set<String>
    var onIntegrationsChanged: (() -> Void)?

    private let hookPort: UInt16
    private let defaults: UserDefaults
    private static let disabledAdaptersKey = "TokenIsland.DisabledHookAdapters.v1"

    init(
        hookPort: UInt16 = AppConstants.defaultHookPort,
        adapters: [any CLIAdapter]? = nil,
        defaults: UserDefaults = .standard
    ) {
        self.hookPort = hookPort
        self.defaults = defaults
        self.disabledAdapterIDs = Set(defaults.stringArray(forKey: Self.disabledAdaptersKey) ?? [])
        self.entries = (adapters ?? Self.roster()).map { Entry(adapter: $0, status: .notFound) }
    }

    private static func roster() -> [any CLIAdapter] {
        // Claude first (the reference integration), then every Claude-family
        // CLI from the descriptor roster, then the file-watch adapters.
        var adapters: [any CLIAdapter] = [ClaudeCodeAdapter()]
        adapters.append(contentsOf: HookFamilyCLI.roster.map { HookFamilyAdapter(cli: $0) })
        adapters.append(CodexAdapter())
        
        return adapters
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
        onIntegrationsChanged?()
    }

    func isEnabled(adapterID: String) -> Bool { !disabledAdapterIDs.contains(adapterID) }

    func isEnabled(agent: AgentKind) -> Bool {
        entries.first(where: { $0.adapter.agentKind == agent }).map { isEnabled(adapterID: $0.id) } ?? true
    }

    func hasActiveHooks(for agent: AgentKind) -> Bool {
        isEnabled(agent: agent) && entries.contains {
            $0.adapter.agentKind == agent && $0.adapter.integrationMode == .managedHooks && $0.status.isActive
        }
    }

    func setEnabled(_ enabled: Bool, adapterID: String) {
        if enabled { install(adapterID: adapterID) } else { uninstall(adapterID: adapterID) }
    }

    /// Installs or repairs hooks where supported. Safe to call on every
    /// launch: adapters are idempotent and only touch their own entries.
    func autoConfigure() {
        refreshStatuses()
        for index in entries.indices {
            guard isEnabled(adapterID: entries[index].id),
                  entries[index].adapter.integrationMode == .managedHooks
            else { continue }
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
            disabledAdapterIDs.insert(adapterID)
            savePreferences()
            entries[index].status = entries[index].adapter.status(hookPort: hookPort)
            lastError = nil
            onIntegrationsChanged?()
        } catch {
            lastError = "\(entries[index].adapter.displayName): \(error.localizedDescription)"
        }
    }

    private func install(at index: Int) {
        let adapter = entries[index].adapter
        do {
            try adapter.installHooks(hookPort: hookPort)
            disabledAdapterIDs.remove(adapter.id)
            savePreferences()
            entries[index].status = adapter.status(hookPort: hookPort)
            lastError = nil
            onIntegrationsChanged?()
        } catch {
            let message = error.localizedDescription
            entries[index].status = .failed(message)
            lastError = "\(adapter.displayName): \(message)"
            AppLog.telemetry.error("Hook install failed for \(adapter.id): \(message)")
        }
    }

    private func savePreferences() {
        defaults.set(disabledAdapterIDs.sorted(), forKey: Self.disabledAdaptersKey)
    }
}
