import SwiftUI

struct MenuBarPopoverView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(spacing: 16) {
            header
            updateBanner
            connectionStatus
            providerRows
            recent
            actions
            footerActions
        }
        .padding(18)
        .frame(width: 390)
        .background(TITheme.background)
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text("TokenIsland")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(TITheme.primaryText)
                Text("\(AppFormatters.tokens(appState.summary.totalTokensToday)) tokens · \(AppFormatters.currency(appState.summary.estimatedCostTodayUSD))")
                    .font(.callout)
                    .foregroundStyle(TITheme.secondaryText)
            }
            Spacer()
            Button {
                appState.updateSettings { $0.showNotchOverlay.toggle() }
            } label: {
                Image(systemName: appState.settings.showNotchOverlay ? "capsule.fill" : "capsule")
                    .frame(width: 28, height: 28)
            }
            .help(appState.settings.showNotchOverlay ? "Hide notch overlay" : "Show notch overlay")
            .tiButtonStyle()
        }
    }

    private var connectionStatus: some View {
        HStack(spacing: 8) {
            StatusBadge(title: "OTLP", health: appState.ingestionStatus.otlpHealth)
            StatusBadge(title: "Proxy", health: appState.ingestionStatus.proxyHealth)
            Spacer()
            Text(appState.ingestionStatus.lastEventAt.map { "Last: \(AppFormatters.timeFormatter.string(from: $0))" } ?? "No events yet")
                .font(.caption2)
                .foregroundStyle(TITheme.tertiaryText)
        }
    }

    private var providerRows: some View {
        VStack(spacing: 12) {
            ProviderUsageRow(summary: appState.summary.provider(.claude))
            ProviderUsageRow(summary: appState.summary.provider(.gpt))
            ProviderUsageRow(summary: appState.summary.provider(.gemini))
        }
        .padding(14)
        .tiPanel()
    }

    private var recent: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Recent")
                .font(.caption.weight(.semibold))
                .foregroundStyle(TITheme.secondaryText)
            if let event = appState.summary.recentRequests.first {
                RecentRequestRow(event: event)
            } else {
                Text("No requests captured yet")
                    .font(.callout)
                    .foregroundStyle(TITheme.tertiaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 10)
            }
        }
    }

    private var actions: some View {
        HStack(spacing: 10) {
            Button {
                AppDelegate.environment?.windowRouter.openDashboard()
                NSApp.activate(ignoringOtherApps: true)
            } label: {
                Label("Dashboard", systemImage: "chart.xyaxis.line")
                    .frame(maxWidth: .infinity)
            }
            Button {
                AppDelegate.environment?.windowRouter.openSettings()
                NSApp.activate(ignoringOtherApps: true)
            } label: {
                Label("Settings", systemImage: "gearshape")
                    .frame(maxWidth: .infinity)
            }
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.regular)
    }

    /// Only present when there is genuinely something newer — a menu bar app
    /// is checked at a glance, so a permanent "you're up to date" row would be
    /// noise.
    @ViewBuilder
    private var updateBanner: some View {
        if let checker = AppDelegate.environment?.updateChecker, let update = checker.available {
            Button {
                checker.installOrOpenDownload()
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "arrow.down.circle.fill")
                        .foregroundStyle(PetPalette.tint(for: .ready))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Update available — \(update.version)")
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(TITheme.primaryText)
                        Text(checker.canInstallInPlace
                             ? "Click to install and restart."
                             : "Click to download the new version.")
                            .font(.caption)
                            .foregroundStyle(TITheme.secondaryText)
                    }
                    Spacer(minLength: 0)
                }
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(PetPalette.tint(for: .ready).opacity(0.12))
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Update available, version \(update.version)")
        }
    }

    private var footerActions: some View {
        HStack(spacing: 10) {
            Button {
                appState.updateSettings { $0.showNotchOverlay.toggle() }
            } label: {
                Label(appState.settings.showNotchOverlay ? "Hide Island" : "Show Island", systemImage: appState.settings.showNotchOverlay ? "eye.slash" : "eye")
                    .frame(maxWidth: .infinity)
            }
            Button {
                appState.updateSettings { $0.pinExpandedNotch.toggle() }
            } label: {
                Label(appState.settings.pinExpandedNotch ? "Unpin" : "Pin", systemImage: appState.settings.pinExpandedNotch ? "pin.slash" : "pin")
                    .frame(maxWidth: .infinity)
            }
            Button {
                NSApp.terminate(nil)
            } label: {
                Image(systemName: "power")
                    .frame(width: 30, height: 30)
            }
            .help("Quit TokenIsland")
        }
        .buttonStyle(.bordered)
    }
}
