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

            updatesCard

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
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop/tokenisland/Docs")
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

    /// State of the update feed. A locally built app has no feed to check, and
    /// says so instead of pretending it is up to date.
    @ViewBuilder
    private var updatesCard: some View {
        let checker = AppDelegate.environment?.updateChecker
        SettingsCard(title: "Updates", subtitle: updatesSubtitle(checker)) {
            SettingsToggleRow(
                title: "Auto check for updates",
                detail: "Check the release feed on launch and once an hour while running.",
                isOn: boolBinding(\.autoCheckForUpdates, appState: appState)
            )
            if let update = checker?.available {
                SettingsButtonRow(
                    title: (checker?.canInstallInPlace == true ? "Install " : "Download ") + update.version,
                    detail: checker?.canInstallInPlace == true
                        ? "Downloads, verifies and restarts into the new version."
                        : "A newer version is available.",
                    role: nil,
                    systemImage: "arrow.down.circle.fill"
                ) {
                    checker?.installOrOpenDownload()
                }
            }
            SettingsButtonRow(
                title: "Check now",
                detail: "Ask the release feed straight away.",
                role: nil,
                systemImage: "arrow.clockwise"
            ) {
                checker?.checkNow()
            }
        }
    }

    private func updatesSubtitle(_ checker: UpdateChecker?) -> String {
        guard let checker else { return "Update checks are unavailable." }
        guard checker.isConfigured else {
            return "This build has no release feed — updates are checked only in distributed builds."
        }
        if let error = checker.lastError { return error }
        if checker.isChecking { return "Checking…" }
        if let update = checker.available { return "Version \(update.version) is available." }
        if checker.lastCheckedAt != nil { return "TokenIsland is up to date." }
        return "Not checked yet."
    }

    private var versionText: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0"
    }

    private var buildText: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "local"
    }
}
