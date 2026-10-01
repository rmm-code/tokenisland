import SwiftUI

/// Observes the registry directly so install/error/preference changes are
/// visible immediately; observing its parent AppState alone cannot do that.
struct AgentIntegrationControls: View {
    @ObservedObject private var appState: AppState
    @ObservedObject private var registry: AdapterRegistry

    init(appState: AppState) {
        self.appState = appState
        self.registry = appState.adapterRegistry
    }

    var body: some View {
        ForEach(registry.entries) { entry in
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 10) {
                    Text(entry.adapter.displayName)
                        .font(.callout.weight(.medium))
                        .foregroundStyle(TITheme.primaryText)
                    Spacer()
                    if entry.status == .notFound {
                        Text("CLI not found").font(.caption).foregroundStyle(TITheme.tertiaryText)
                    } else if entry.adapter.integrationMode == .passiveWatcher {
                        passiveControl(entry)
                    } else {
                        managedControl(entry)
                    }
                }
                statusDetail(entry)
                if entry.adapter.agentKind == .cursor || entry.adapter.agentKind == .gemini {
                    Text("Sessions are monitored here; answer approvals in \(entry.adapter.displayName).")
                        .font(.caption).foregroundStyle(TITheme.secondaryText)
                }
                conflictWarning(entry)
            }
            .padding(.vertical, 4)
        }
        if let error = registry.lastError {
            Text(error)
                .font(.caption)
                .foregroundStyle(TITheme.danger)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func managedControl(_ entry: AdapterRegistry.Entry) -> some View {
        HStack(spacing: 8) {
            Text(registry.isEnabled(adapterID: entry.id) ? entry.status.label : "Disabled")
                .font(.caption)
                .foregroundStyle(entry.status.isActive ? TITheme.secondaryText : TITheme.tertiaryText)
            if registry.isEnabled(adapterID: entry.id) {
                switch entry.status {
                case .needsSetup:
                    recoveryButton("Connect", entry: entry)
                case .needsRepair:
                    recoveryButton("Repair", entry: entry)
                case .failed:
                    recoveryButton("Retry", entry: entry)
                default:
                    EmptyView()
                }
            }
            Toggle("Enable \(entry.adapter.displayName)", isOn: Binding(
                get: { registry.isEnabled(adapterID: entry.id) },
                set: { registry.setEnabled($0, adapterID: entry.id) }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .accessibilityLabel("Enable \(entry.adapter.displayName)")
        }
    }

    private func recoveryButton(_ title: String, entry: AdapterRegistry.Entry) -> some View {
        Button(title) { registry.install(adapterID: entry.id) }
            .controlSize(.small)
    }

    @ViewBuilder
    private func statusDetail(_ entry: AdapterRegistry.Entry) -> some View {
        if registry.isEnabled(adapterID: entry.id) {
            switch entry.status {
            case .failed(let message), .needsRepair(let message):
                Text(message).font(.caption).foregroundStyle(TITheme.warning)
                    .fixedSize(horizontal: false, vertical: true)
            default:
                EmptyView()
            }
        }
    }

    @ViewBuilder
    private func conflictWarning(_ entry: AdapterRegistry.Entry) -> some View {
        let conflicts = entry.adapter.conflictingApprovalHooks()
        if registry.isEnabled(adapterID: entry.id), !conflicts.isEmpty {
            Label("Also answering approvals: \(Set(conflicts).sorted().joined(separator: ", ")). Verdicts may conflict.",
                  systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(TITheme.warning)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func passiveControl(_ entry: AdapterRegistry.Entry) -> some View {
        let enabled = Binding(
            get: { appState.settings.enableCodexMonitoring },
            set: { value in appState.updateSettings { $0.enableCodexMonitoring = value } }
        )
        return HStack(spacing: 8) {
            Text(enabled.wrappedValue ? "Monitoring" : "Paused")
                .font(.caption).foregroundStyle(TITheme.secondaryText)
            Toggle("Monitor \(entry.adapter.displayName)", isOn: enabled)
                .labelsHidden().toggleStyle(.switch)
                .accessibilityLabel("Monitor \(entry.adapter.displayName)")
        }
    }
}
