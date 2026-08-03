import SwiftUI

/// Auto-reveal content: one compact session row plus either a completion
/// excerpt or approval controls. Clicking the body opens the full panel.
struct RevealCardView: View {
    @EnvironmentObject private var appState: AppState
    var kind: NotchRevealKind
    /// Clearance for the notch band the card grows out of — the first row has
    /// to start below it or the hardware notch slices through the title. The
    /// band isn't padding: it carries the same actions as the panel header,
    /// so the card reads like the panel rather than like a gap.
    var topInset: CGFloat = 6
    var session: AgentSession?
    var onExpand: () -> Void
    var onJump: (AgentSession) -> Void
    var openSettings: () -> Void = {}

    private var bandHeight: CGFloat {
        max(topInset, PanelHeaderView.height)
    }

    var body: some View {
        Group {
            if let session {
                // No gap under the band: the session row starts immediately
                // below the notch, its own row padding is the only breathing
                // room the hardware leaves us.
                VStack(alignment: .leading, spacing: 0) {
                    header

                    VStack(alignment: .leading, spacing: 6) {
                        SessionCardView(
                            session: session,
                            isFocused: true,
                            compactSubagents: true,
                            verticalPadding: 4,
                            onJump: onJump
                        )

                        switch kind {
                        case .completion:
                            if session.completionText != nil || session.completionTLDR != nil {
                                CompletionCardView(session: session, lineLimit: 2)
                                    .padding(.horizontal, 8)
                            }
                        case .attention:
                            if session.phase == .question {
                                QuestionCardView(session: session, onJump: onJump)
                                    .padding(.horizontal, 8)
                            } else {
                                ApprovalCardView(session: session, onJump: onJump)
                                    .padding(.horizontal, 8)
                            }
                        }
                    }
                }
                .padding(.bottom, 10)
                .contentShape(Rectangle())
                .onTapGesture(perform: onExpand)
            } else {
                Color.clear
            }
        }
    }

    /// Sits in the notch band, so the controls flank the hardware the way the
    /// panel header does. Right-aligned: the left of the band is where the
    /// notch itself is widest.
    private var header: some View {
        HStack(spacing: 12) {
            Spacer(minLength: 0)

            Button {
                appState.updateSettings { $0.soundEnabled.toggle() }
            } label: {
                Image(systemName: appState.settings.soundEnabled ? "speaker.wave.2.fill" : "speaker.slash.fill")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Color.white.opacity(0.62))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Toggle sounds")

            Button(action: openSettings) {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.white.opacity(0.62))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open settings")
        }
        .padding(.horizontal, 14)
        .frame(height: bandHeight, alignment: .center)
    }
}
