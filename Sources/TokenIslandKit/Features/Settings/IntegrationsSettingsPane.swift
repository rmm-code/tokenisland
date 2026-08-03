import AppKit
import SwiftUI

struct IntegrationsSettingsPane: View, SettingsPaneBindingProviding {
    @EnvironmentObject private var appState: AppState
    @State private var accessibilityGranted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SettingsCard(
                title: "Agent integrations",
                subtitle: "Claude uses managed hooks. Codex and Gemini are monitored passively from their local session files."
            ) {
                ForEach(appState.adapterRegistry.entries) { entry in
                    adapterRow(entry)
                }
                SettingsToggleRow(
                    title: "Auto-configure Claude hooks",
                    detail: "Install or repair the Claude integration when it is detected.",
                    isOn: boolBinding(\.autoConfigureNewCLIs, appState: appState)
                )
            }

            SettingsCard(title: "Coding Agent") {
                SettingsToggleRow(
                    title: "Own terminal title with session marker",
                    detail: "The tab title becomes “claude — <task-slug>” for precise jumping.",
                    isOn: boolBinding(\.enableTitleMarkers, appState: appState)
                )
            }

            SettingsCard(title: "Developer") {
                SettingsRow(
                    title: "Custom Jump Rules",
                    detail: "Terminal developers can register a URL scheme per bundle id."
                ) {
                    Button("Reveal in Finder", systemImage: "arrow.up.forward.square") {
                        revealJumpRules()
                    }
                    .controlSize(.small)
                }
            }

            SettingsCard(title: "Permissions") {
                SettingsRow(
                    title: "Accessibility",
                    detail: "Required to land on the exact terminal window when jumping."
                ) {
                    if accessibilityGranted {
                        Label("Granted", systemImage: "checkmark.seal.fill")
                            .font(.callout)
                            .foregroundStyle(PetPalette.tint(for: .ready))
                    } else {
                        Button("Grant…") {
                            WindowLocator.requestAccessibilityPermission()
                        }
                    }
                }
                SettingsRow(
                    title: "Hook server",
                    detail: "Local endpoint hooks report to. Health: GET /health."
                ) {
                    Text("127.0.0.1:\(String(AppConstants.defaultHookPort))")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(TITheme.secondaryText)
                }
            }
        }
        .onAppear {
            appState.adapterRegistry.refreshStatuses()
            accessibilityGranted = WindowLocator.hasAccessibilityPermission
        }
    }

    @ViewBuilder
    private func adapterRow(_ entry: AdapterRegistry.Entry) -> some View {
        HStack(spacing: 10) {
            Text(entry.adapter.displayName)
                .font(.callout.weight(.medium))
                .foregroundStyle(TITheme.primaryText)
            Spacer()
            if entry.adapter.integrationMode == .passiveWatcher {
                passiveWatcherControl(entry)
            } else {
                managedHookControl(entry)
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func managedHookControl(_ entry: AdapterRegistry.Entry) -> some View {
        Group {
            switch entry.status {
            case .active:
                Label("Active", systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(PetPalette.tint(for: .ready))
                Button("Remove") {
                    appState.adapterRegistry.uninstall(adapterID: entry.id)
                }
                .controlSize(.small)
            case .needsSetup:
                Button("Install hooks") {
                    appState.adapterRegistry.install(adapterID: entry.id)
                }
                .controlSize(.small)
                .buttonStyle(.borderedProminent)
            case .needsRepair(let reason):
                Text(reason)
                    .font(.caption)
                    .foregroundStyle(TITheme.warning)
                Button("Repair") {
                    appState.adapterRegistry.install(adapterID: entry.id)
                }
                .controlSize(.small)
                .buttonStyle(.borderedProminent)
            case .failed(let message):
                Text(message)
                    .font(.caption)
                    .foregroundStyle(TITheme.danger)
                    .lineLimit(1)
                Button("Retry") {
                    appState.adapterRegistry.install(adapterID: entry.id)
                }
                .controlSize(.small)
            case .detectedOnly:
                Label("Detected", systemImage: "checkmark.circle")
                    .font(.caption)
                    .foregroundStyle(PetPalette.tint(for: .ready).opacity(0.8))
            case .notFound:
                Text("CLI not found")
                    .font(.caption)
                    .foregroundStyle(TITheme.tertiaryText)
            }
        }
    }

    @ViewBuilder
    private func passiveWatcherControl(_ entry: AdapterRegistry.Entry) -> some View {
        if entry.status.isDetected {
            let isEnabled = passiveMonitorBinding(for: entry.id)
            Label(isEnabled.wrappedValue ? "Monitoring" : "Paused", systemImage: "waveform.path.ecg")
                .font(.caption)
                .foregroundStyle(isEnabled.wrappedValue ? PetPalette.tint(for: .working) : TITheme.tertiaryText)
            Toggle("Monitor \(entry.adapter.displayName)", isOn: isEnabled)
                .labelsHidden()
                .accessibilityLabel("Monitor \(entry.adapter.displayName)")
        } else {
            Text("CLI not found")
                .font(.caption)
                .foregroundStyle(TITheme.tertiaryText)
        }
    }

    private func passiveMonitorBinding(for adapterID: String) -> Binding<Bool> {
        switch adapterID {
        case "codex":
            boolBinding(\.enableCodexMonitoring, appState: appState)
        case "gemini-cli":
            boolBinding(\.enableGeminiMonitoring, appState: appState)
        default:
            .constant(false)
        }
    }

    // MARK: - Custom jump rules

    private static var jumpRulesDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "TokenIsland", directoryHint: .isDirectory)
    }

    /// Reveals `jump-rules.json` in Finder, creating it (plus a README
    /// sibling — JSON can't carry comments) on first use.
    private func revealJumpRules() {
        let directory = Self.jumpRulesDirectory
        let rules = directory.appending(path: "jump-rules.json")
        let readme = directory.appending(path: "jump-rules-README.txt")
        let fileManager = FileManager.default
        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            if !fileManager.fileExists(atPath: rules.path) {
                try Data("{}\n".utf8).write(to: rules)
            }
            if !fileManager.fileExists(atPath: readme.path) {
                let text = """
                Custom Jump Rules
                =================

                jump-rules.json maps a terminal app's bundle identifier to a URL
                template TokenIsland opens instead of window matching when jumping
                to a session. {session} expands to the session id.

                Example:
                {
                  "com.example.term": "exampleterm://focus?session={session}"
                }
                """
                try Data((text + "\n").utf8).write(to: readme)
            }
        } catch {
            AppLog.app.error("Failed to prepare jump rules file: \(error.localizedDescription)")
        }
        NSWorkspace.shared.activateFileViewerSelecting([rules])
    }
}
