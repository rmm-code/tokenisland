import SwiftUI

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
