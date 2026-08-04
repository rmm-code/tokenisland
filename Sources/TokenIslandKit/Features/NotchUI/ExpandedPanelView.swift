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
            return (usageLimits.snapshot?.windows ?? []).map {
                UsageWindow(label: $0.label, usedPercent: $0.usedPercent, resetsAt: $0.resetsAt)
            }
        case .gpt:
            return codexWindows.map { window in
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
    }

    /// The reference-style usage pill: [icon] 5h 26% 4h13m | 7d 28% 1d12h.
    @ViewBuilder
    private var usagePill: some View {
        if appState.settings.showUsageLimitsHeader {
            Button(action: handleUsagePillTap) {
                HStack(spacing: 7) {
                    ProviderIconView(provider: provider, size: 13, whiteTemplate: true)
                        .frame(width: 17, height: 17)
                        .background(
                            RoundedRectangle(cornerRadius: 4.5, style: .continuous)
                                .fill(provider == .claude
                                      ? Color(red: 0.85, green: 0.35, blue: 0.13)
                                      : Color.white.opacity(0.14))
                        )

                    if provider == .claude, usageLimits.isRefreshing {
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
                    }
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(usageAccessibilityLabel)
        }
    }

    private var emptyUsageText: String {
        guard provider == .claude else { return "No recent Codex usage" }
        return "Usage unavailable"
    }

    private var usageAccessibilityLabel: String {
        if provider == .claude, usageLimits.snapshot == nil {
            if usageLimits.isRefreshing {
                return "Claude usage loading"
            }
            return "Claude usage unavailable, activate to retry or switch provider"
        }
        return "\(usageProviderName) usage, tap to switch provider"
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

    private func handleUsagePillTap() {
        if provider == .claude, usageLimits.snapshot == nil {
            guard !usageLimits.isRefreshing else { return }
            if !usageLimits.didAttemptUserRefresh {
                usageLimits.refreshFromUserAction()
                return
            }
        }
        cycleProvider()
    }

    private func cycleProvider() {
        guard let index = providers.firstIndex(of: provider) else { return }
        provider = providers[(index + 1) % providers.count]
        if provider == .gpt {
            refreshCodexWindows()
        } else {
            usageLimits.refreshFromUserAction()
        }
    }

    private func refreshCodexWindows() {
        guard Self.codexInstalled else { return }
        Task.detached(priority: .utility) {
            let windows = CodexUsageReader.latestWindows()
            await MainActor.run { codexWindows = windows }
        }
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
        guard interval > 0 else { return "soon" }
        let minutes = Int(interval / 60)
        if minutes < 60 { return "\(minutes)m" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours)h\(minutes % 60)m" }
        return "\(hours / 24)d\(hours % 24)h"
    }
}

/// The full session panel: header + session cards (+ inline completion and
/// approval cards), with a focused view and a remaining-session disclosure.
struct ExpandedPanelView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var sessionStore: SessionStore
    @ObservedObject var usageLimits: UsageLimitsService
    var onCollapse: () -> Void
    var openSettings: () -> Void
    var onJump: (AgentSession) -> Void

    /// Room for the pet, the headline and the two-line setup hint.
    static let emptyStateHeight: CGFloat = 150

    @State private var showAll = false

    private var orderedSessions: [AgentSession] {
        SessionPanelPresentation.orderedSessions(
            sessionStore.sessions,
            focusedSessionID: sessionStore.focusedSessionID
        )
    }

    private var visibleSessions: [AgentSession] {
        SessionPanelPresentation.visibleSessions(
            from: orderedSessions,
            showAll: showAll
        )
    }

    private var hiddenCount: Int {
        SessionPanelPresentation.hiddenCount(
            totalCount: orderedSessions.count,
            visibleCount: visibleSessions.count
        )
    }

    private var completionDetailSessionID: String? {
        SessionPanelPresentation.completionDetailSessionID(
            in: orderedSessions,
            focusedSessionID: sessionStore.focusedSessionID
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            PanelHeaderView(
                usageLimits: usageLimits,
                onCollapse: onCollapse,
                openSettings: openSettings
            )

            if sessionStore.sessions.isEmpty {
                emptyState
                    // The empty state stretches (it is Spacer-padded), so it
                    // reports a constant instead of its stretched frame.
                    .preference(
                        key: PanelContentHeightKey.self,
                        value: PanelHeaderView.height + Self.emptyStateHeight
                    )
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 6) {
                        ForEach(visibleSessions) { session in
                            sessionBlock(session)
                        }
                        if hiddenCount > 0 {
                            Button {
                                showAll = true
                            } label: {
                                Text(SessionPanelPresentation.showMoreLabel(hiddenCount: hiddenCount))
                                    .font(.system(size: 10.5, weight: .medium))
                                    .foregroundStyle(TITheme.secondaryText)
                                    .padding(.vertical, 5)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.bottom, 12)
                    // Inside a ScrollView the list keeps its natural height, so
                    // this measures the sessions, not the frame they sit in —
                    // no feedback between the panel size and this value.
                    .background(
                        GeometryReader { proxy in
                            Color.clear.preference(
                                key: PanelContentHeightKey.self,
                                value: PanelHeaderView.height + proxy.size.height
                            )
                        }
                    )
                }
            }
        }
        .task {
            // Nothing to refresh for a header the user has turned off.
            guard appState.settings.showUsageLimitsHeader else { return }
            usageLimits.refreshIfStale()
        }
    }

    @ViewBuilder
    private func sessionBlock(_ session: AgentSession) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            SessionCardView(
                session: session,
                isFocused: session.id == sessionStore.focusedSessionID,
                onJump: onJump
            )

            if session.phase == .question {
                QuestionCardView(session: session, onJump: onJump)
                    .padding(.horizontal, 8)
            } else if session.phase == .waitingApproval {
                ApprovalCardView(session: session, onJump: onJump)
                    .padding(.horizontal, 8)
            } else if session.phase == .ready,
                      session.completionText != nil,
                      session.id == completionDetailSessionID {
                CompletionCardView(
                    session: session,
                    initiallyExpanded: SessionPanelPresentation.fullPanelCompletionInitiallyExpanded
                )
                    .padding(.horizontal, 8)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Spacer()
            HStack(spacing: 8) {
                PetFrameView(species: .crab, frameIndex: 0, phase: .ready, pixelSize: 2.4, glow: true)
            }
            Text("No active agent sessions")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(TITheme.primaryText)
            Text(setupHint)
                .font(.system(size: 10.5))
                .foregroundStyle(TITheme.tertiaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 30)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var setupHint: String {
        if appState.adapterRegistry.activeCount == 0 {
            return "Open Settings → Integrations to connect your AI CLIs, then start a new claude session in any terminal."
        }
        return "Start a claude session in any terminal — it will land here. Sessions started before hooks were installed won't report."
    }

}
