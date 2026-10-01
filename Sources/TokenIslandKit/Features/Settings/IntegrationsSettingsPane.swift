import AppKit
import SwiftUI

struct IntegrationsSettingsPane: View, SettingsPaneBindingProviding {
    private static let accessibilityPaneURL = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
    )!

    @EnvironmentObject private var appState: AppState
    @State private var accessibilityGranted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SettingsCard(
                title: "Agent integrations",
                subtitle: "Connect your agents here. Agents you turn off stay off after restarting."
            ) {
                AgentIntegrationControls(appState: appState)
                SettingsToggleRow(
                    title: "Automatically connect new agents",
                    detail: "Connect detected agents and repair enabled integrations. Agents you turn off stay off.",
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
                    detail: accessibilityGranted
                        ? "Required to land on the exact terminal window when jumping."
                        // The confusing case: the switch is on, but macOS still
                        // says no because the entry belongs to an older build of
                        // the app. Nothing in the UI hints at that, so say it.
                        : "Not granted. If TokenIsland is already listed and switched on, select it, press −, then add it again — a leftover entry from an earlier build does not match this one."
                ) {
                    if accessibilityGranted {
                        Label("Granted", systemImage: "checkmark.seal.fill")
                            .font(.callout)
                            .foregroundStyle(PetPalette.tint(for: .ready))
                    } else {
                        HStack(spacing: 8) {
                            Button("Grant…") {
                                WindowLocator.requestAccessibilityPermission()
                            }
                            Button("Open Settings") {
                                NSWorkspace.shared.open(Self.accessibilityPaneURL)
                            }
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
        // Granting happens in System Settings, in another window: without a
        // poll this row keeps claiming "not granted" until the pane is reopened.
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in
            let granted = WindowLocator.hasAccessibilityPermission
            if granted != accessibilityGranted { accessibilityGranted = granted }
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
