import AppKit
import SwiftUI

struct AboutSettingsPane: View, SettingsPaneBindingProviding {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SettingsCard(title: "TokenIsland", subtitle: "A Dynamic Island for your AI coding agents — sessions, approvals, and jumps, all from the notch.") {
                HStack(alignment: .center, spacing: 16) {
                    appIcon
                    VStack(alignment: .leading, spacing: 6) {
                        Text("TokenIsland")
                            .font(.title2.weight(.semibold))
                            .foregroundStyle(TITheme.primaryText)
                        Text("Version \(versionText)")
                            .font(.callout)
                            .foregroundStyle(TITheme.secondaryText)
                        Text("Session data stays on your Mac. Usage-limit refreshes contact the configured provider directly.")
                            .font(.callout)
                            .foregroundStyle(TITheme.secondaryText)
                    }
                }
            }

            SettingsCard(title: "Data", subtitle: "Local token-usage history from the legacy counter.") {
                SettingsButtonRow(
                    title: "Export usage data",
                    detail: "Save all stored usage events as JSON.",
                    role: nil,
                    systemImage: "square.and.arrow.up"
                ) {
                    exportUsage()
                }
                SettingsButtonRow(
                    title: "Delete all usage data",
                    detail: "Remove every stored usage event.",
                    role: .destructive,
                    systemImage: "trash"
                ) {
                    Task { await appState.deleteAllUsage() }
                }
            }

            SettingsCard(title: "Links", subtitle: "Project documentation lives in this repo.") {
                VStack(alignment: .leading, spacing: 10) {
                    Button {
                        NSWorkspace.shared.open(projectDocsURL)
                    } label: {
                        Label("Documentation (Docs folder)", systemImage: "book")
                    }
                    .buttonStyle(.link)
                    Button {
                        NSWorkspace.shared.open(projectDocsURL.appendingPathComponent("PRIVACY.md"))
                    } label: {
                        Label("Privacy notes", systemImage: "lock.shield")
                    }
                    .buttonStyle(.link)
                    Link(destination: URL(string: "mailto:\(AppConstants.supportEmail)")!) {
                        Label("Support / Contact", systemImage: "envelope")
                    }
                }
                .font(.callout)
            }

            SettingsCard(title: "Build Info", subtitle: "Runtime identifiers useful for diagnostics.") {
                SettingsRow(title: "Bundle identifier", detail: AppConstants.bundleIdentifier) {
                    Text(AppConstants.bundleIdentifier)
                        .font(.caption.monospaced())
                        .foregroundStyle(TITheme.secondaryText)
                }
                SettingsRow(title: "Minimum macOS", detail: "Supported deployment target.") {
                    Text(AppConstants.minimumOSVersion)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(TITheme.secondaryText)
                }
                SettingsRow(title: "Build", detail: buildText) {
                    Text(buildText)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(TITheme.secondaryText)
                }
            }
        }
    }

    /// Bundled docs in production, with checkout paths for local builds.
    private var projectDocsURL: URL {
        let bundleURL = Bundle.main.bundleURL
        let candidates = [
            Bundle.main.resourceURL?.appendingPathComponent("Docs"),
            bundleURL.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Docs"),
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop/counter/Docs")
        ].compactMap { $0 }
        return candidates.first { FileManager.default.fileExists(atPath: $0.path) } ?? bundleURL
    }

    private func exportUsage() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "tokenisland-usage.json"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            Task { await appState.exportUsageData(to: url) }
        }
    }

    private var appIcon: some View {
        Image(nsImage: AppIconArt.appIcon(size: 74))
            .resizable()
            .interpolation(.none)
        .frame(width: 74, height: 74)
    }

    private var versionText: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0"
    }

    private var buildText: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "local"
    }
}
