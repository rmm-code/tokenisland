import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct NotificationsSettingsPane: View, SettingsPaneBindingProviding {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SettingsCard(title: "Agents") {
                SettingsToggleRow(
                    title: "Show subagent completion reveals",
                    detail: "Reveal the main completion while agent-team work is still running.",
                    isOn: subagentRevealBinding
                )
            }

            SettingsCard(
                title: "Blocked Launcher Apps",
                subtitle: "Drop sessions launched by selected apps before they appear."
            ) {
                blockedAppsList
            }

            SettingsCard(
                title: "Quiet scenes",
                subtitle: "Completion reveals and sounds stay quiet while locked. Approvals and questions still appear silently."
            ) {
                SettingsToggleRow(
                    title: "Screen locked or asleep",
                    detail: "Suppress sounds while the screen is locked.",
                    isOn: boolBinding(\.quietWhenScreenLocked, appState: appState)
                )
            }

            SettingsCard(title: "Usage alerts") {
                SettingsToggleRow(
                    title: "Daily threshold notifications",
                    detail: "Notify when tracked token or cost thresholds are crossed.",
                    isOn: boolBinding(\.enableThresholdNotifications, appState: appState)
                )
                SettingsSliderRow(
                    title: "Daily token threshold",
                    detail: "Tokens per day before alerting.",
                    value: tokenThresholdBinding,
                    range: 100_000...5_000_000,
                    step: 100_000,
                    valueText: { "\(Int($0 / 1000))k" }
                )
                SettingsSliderRow(
                    title: "Daily cost threshold",
                    detail: "Estimated spend per day before alerting.",
                    value: costThresholdBinding,
                    range: 1...200,
                    step: 1,
                    valueText: { String(format: "$%.0f", $0) }
                )
            }
        }
    }

    // MARK: - Blocked launcher apps

    @ViewBuilder
    private var blockedAppsList: some View {
        if appState.settings.blockedLauncherApps.isEmpty {
            Text("No blocked apps.")
                .font(.caption)
                .foregroundStyle(TITheme.tertiaryText)
        } else {
            ForEach(appState.settings.blockedLauncherApps, id: \.self) { bundleID in
                blockedAppRow(bundleID)
            }
        }
        HStack {
            Spacer()
            Button("Add App…", systemImage: "plus") {
                addBlockedApp()
            }
            .controlSize(.small)
        }
    }

    private func blockedAppRow(_ bundleID: String) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text(Self.appName(forBundleID: bundleID) ?? bundleID)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(TITheme.primaryText)
                Text(bundleID)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(TITheme.tertiaryText)
            }
            Spacer()
            Button {
                appState.updateSettings { $0.blockedLauncherApps.removeAll { $0 == bundleID } }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(TITheme.secondaryText)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove \(bundleID)")
        }
        .padding(.vertical, 3)
    }

    private func addBlockedApp() {
        let panel = NSOpenPanel()
        panel.title = "Choose an app to block"
        panel.directoryURL = URL(filePath: "/Applications", directoryHint: .isDirectory)
        panel.allowedContentTypes = [.applicationBundle]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK,
              let url = panel.url,
              let bundleID = Bundle(url: url)?.bundleIdentifier
        else { return }
        appState.updateSettings {
            if !$0.blockedLauncherApps.contains(bundleID) {
                $0.blockedLauncherApps.append(bundleID)
            }
        }
    }

    private static func appName(forBundleID bundleID: String) -> String? {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            return nil
        }
        let name = FileManager.default.displayName(atPath: url.path)
        return (name as NSString).deletingPathExtension
    }

    // MARK: - Bindings

    private var subagentRevealBinding: Binding<Bool> {
        Binding(
            get: { appState.settings.subagentNotificationMode != "never" },
            set: { enabled in
                appState.updateSettings {
                    $0.subagentNotificationMode = enabled ? "withMainAgent" : "never"
                }
            }
        )
    }

    private var tokenThresholdBinding: Binding<Double> {
        Binding(
            get: { Double(appState.settings.dailyTokenThreshold) },
            set: { value in appState.updateSettings { $0.dailyTokenThreshold = Int(value) } }
        )
    }

    private var costThresholdBinding: Binding<Double> {
        decimalDoubleBinding(\.dailyCostThresholdUSD, appState: appState, range: 1...200)
    }
}
