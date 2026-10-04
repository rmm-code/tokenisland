import AppKit
import SwiftUI

/// Header row of the expanded panel, reference-style: one provider icon +
/// inline usage segments ("5h 26% 4h13m | 7d 28% 1d12h", percent color-coded).
/// Pressing the icon (or the text) cycles Claude → Codex in place.
struct PanelHeaderView: View {
    /// Fixed so the panel's height is `header + list` without measuring twice.
    /// Comfortably fits the 17pt usage pill inside its 10/4 padding.
    static let height: CGFloat = 34

    @EnvironmentObject private var appState: AppState
    @ObservedObject var usageLimits: UsageLimitsService
    var onCollapse: () -> Void
    var openSettings: () -> Void

    @State private var provider: AIProvider = .claude
    @State private var codexWindows: [UsageWindow] = []

    private static let codexInstalled = FileManager.default.fileExists(
        atPath: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex").path
    )

    private var providers: [AIProvider] {
        Self.codexInstalled ? [.claude, .gpt] : [.claude]
    }

    /// Windows for the selected provider, normalized to (label, used%, reset).
    private var windows: [UsageWindow] {
        switch provider {
        case .claude:
            // Whatever the plan reports — session, weekly, and per-model caps
            // like Fable — rather than a fixed pair.
            return (usageLimits.displayedSnapshot?.windows ?? []).map {
                UsageWindow(label: $0.label, usedPercent: $0.usedPercent, resetsAt: $0.resetsAt, key: $0.key)
            }
        case .gpt:
            return codexWindows.filter { $0.resetsAt.map { $0 > Date() } ?? true }.map { window in
                var normalized = window
                if normalized.label == "Weekly" { normalized.label = "7d" }
                return normalized
            }
        case .gemini:
            return []
        case .unknown:
            return []
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            usagePill

            Button(action: onCollapse) {
                Image(systemName: "xmark")
                    .font(.system(size: 8.5, weight: .bold))
                    .foregroundStyle(TITheme.tertiaryText)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Collapse panel")

            Spacer()

            Button {
                appState.updateSettings { $0.soundEnabled.toggle() }
            } label: {
                Image(systemName: appState.settings.soundEnabled ? "speaker.wave.2.fill" : "speaker.slash.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.white.opacity(0.75))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Toggle sounds")

            Button(action: openSettings) {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 12.5))
                    .foregroundStyle(Color.white.opacity(0.75))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open settings")
        }
        .padding(.horizontal, 14)
        .padding(.top, 10)
        .padding(.bottom, 4)
        .frame(height: Self.height)
        .task(id: "\(appState.settings.showUsageLimitsHeader)-\(provider.rawValue)") {
            guard appState.settings.showUsageLimitsHeader else { return }
            while !Task.isCancelled {
                if provider == .claude { await usageLimits.refreshIfStale() }
                else { await refreshCodexWindows() }
                do { try await Task.sleep(for: .seconds(15)) }
                catch { return }
            }
        }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didWakeNotification)) { _ in
            guard appState.settings.showUsageLimitsHeader else { return }
            Task {
                if provider == .claude { await usageLimits.refreshIfStale() }
                else { await refreshCodexWindows() }
            }
        }
    }

    /// The reference-style usage pill: [icon] 5h 26% 4h13m | 7d 28% 1d12h.
    @ViewBuilder
    private var usagePill: some View {
        if appState.settings.showUsageLimitsHeader {
            TimelineView(.periodic(from: .now, by: 15)) { _ in
                HStack(spacing: 6) {
                    Button(action: cycleProvider) {
                        HStack(spacing: 7) {
                            ProviderIconView(provider: provider, size: 13, whiteTemplate: true)
                                .frame(width: 17, height: 17)
                                .background(
                                    RoundedRectangle(cornerRadius: 4.5, style: .continuous)
                                        .fill(provider == .claude
                                              ? Color(red: 0.85, green: 0.35, blue: 0.13)
                                              : Color.white.opacity(0.14))
                                )

                            if provider == .claude, usageLimits.isRefreshing, windows.isEmpty {
                                Text("Loading usage")
                                    .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                                    .foregroundStyle(TITheme.tertiaryText)
                            } else if windows.isEmpty {
                                Text(emptyUsageText)
                                    .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                                    .foregroundStyle(TITheme.tertiaryText)
                            } else {
                                ForEach(Array(windows.enumerated()), id: \.element.id) { index, window in
                                    if index > 0 {
                                        Text("|")
                                            .font(.system(size: 10.5, design: .monospaced))
                                            .foregroundStyle(Color.white.opacity(0.25))
                                    }
                                    usageSegment(window)
                                }
                                Text(appState.settings.usageDisplayValueRemaining ? "left" : "used")
                                    .font(.system(size: 8.5, weight: .medium))
                                    .foregroundStyle(Color.white.opacity(0.45))
                            }
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(usageAccessibilityLabel)
                    .help(usageHelp)

                    Button {
                        Task {
                            if provider == .claude { await usageLimits.refreshFromUserAction() }
                            else { await refreshCodexWindows() }
                        }
                    } label: {
                        if provider == .claude, usageLimits.issue == .accessRequired || usageLimits.issue == .accessDenied {
                            Text("Connect").font(.system(size: 10.5, weight: .semibold))
                        } else {
                            Image(systemName: "arrow.clockwise").font(.system(size: 10.5, weight: .semibold))
                        }
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
                    .disabled(provider == .claude && !usageLimits.canRefresh)
                    .accessibilityLabel(provider == .claude ? "Refresh or connect Claude usage" : "Refresh Codex usage")
                    .help(usageHelp)
                }
            }
        }
    }

    private var emptyUsageText: String {
        guard provider == .claude else { return "No recent Codex usage" }
        return usageLimits.issue?.title ?? "Usage unavailable"
    }

    private var usageAccessibilityLabel: String {
        if provider == .claude, usageLimits.displayedSnapshot == nil {
            if usageLimits.isRefreshing {
                return "Claude usage loading"
            }
            return "\(emptyUsageText). Use the refresh button to retry or connect."
        }
        let mode = appState.settings.usageDisplayValueRemaining ? "remaining" : "used"
        let values = windows.map {
            let value = appState.settings.usageDisplayValueRemaining ? 100 - $0.usedPercent : $0.usedPercent
            return "\($0.label) \(Int(value.rounded())) percent \(mode)"
        }.joined(separator: ", ")
        return "\(usageProviderName) usage. \(values)" + (providers.count > 1 ? ". Tap to switch provider." : "")
    }

    private var usageProviderName: String {
        provider == .gpt ? "Codex" : provider.displayName
    }

    private func usageSegment(_ window: UsageWindow) -> some View {
        let used = min(max(window.usedPercent, 0), 100)
        let shown = appState.settings.usageDisplayValueRemaining ? 100 - used : used
        let percentColor: Color = used > 85
            ? TITheme.danger
            : (used > 60 ? TITheme.warning : PetPalette.tint(for: .ready))

        return HStack(spacing: 4) {
            Text(window.label)
                .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                .foregroundStyle(Color.white.opacity(0.85))
            Text("\(Int(shown.rounded()))%")
                .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                .foregroundStyle(percentColor)
            if let resets = window.resetsAt {
                // Minute granularity, so it has to re-render on its own or the
                // countdown freezes for as long as the panel stays open.
                TimelineView(.periodic(from: .now, by: 60)) { _ in
                    // The glyph is what makes "5h 58% ↻2h14m" read as a reset
                    // countdown rather than a second, unexplained duration.
                    Text("↻\(Self.countdown(to: resets))")
                        .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                        .foregroundStyle(Color.white.opacity(0.45))
                }
                .help("Resets \(Self.resetDescription(for: resets))")
            }
        }
    }

    private var usageHelp: String {
        guard provider == .claude else { return "Usage reported by local Codex sessions. Click refresh to update." }
        if let issue = usageLimits.issue { return issue.detail }
        if let snapshot = usageLimits.displayedSnapshot {
            let mode = appState.settings.usageDisplayValueRemaining ? "remaining" : "used"
            return "Claude Code account limits, \(mode). Updated \(snapshot.fetchedAt.formatted(date: .omitted, time: .shortened)). Refreshes every minute while visible."
        }
        return "Read Claude Code account limits. Connect explicitly if Keychain access is needed."
    }

    private func cycleProvider() {
        guard let index = providers.firstIndex(of: provider) else { return }
        provider = providers[(index + 1) % providers.count]
        // Switching provider is navigation, not permission to open Keychain.
        // The task above restarts for this provider using silent refresh only.
    }

    private func refreshCodexWindows() async {
        guard Self.codexInstalled else { return }
        let result = await Task.detached(priority: .utility) { CodexUsageReader.latestWindows() }.value
        guard !Task.isCancelled else { return }
        codexWindows = result
    }

    /// "4h13m", "1d12h", "38m" — the reference's reset countdown format.
    /// Tooltip text: the countdown says how long, this says when.
    static func resetDescription(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = Calendar.current.isDateInToday(date) ? .none : .medium
        formatter.timeStyle = .short
        return Calendar.current.isDateInToday(date)
            ? "at \(formatter.string(from: date))"
            : "on \(formatter.string(from: date))"
    }

    static func countdown(to date: Date) -> String {
        let interval = date.timeIntervalSinceNow
        guard interval > 0 else { return "updating" }
        let minutes = Int(interval / 60)
        if minutes < 60 { return "\(minutes)m" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours)h\(minutes % 60)m" }
        return "\(hours / 24)d\(hours % 24)h"
    }
}
