import SwiftUI

/// Content of the collapsed/hovering notch strip: pixel pets on the left
/// wing, session count on the right wing, black gap over the physical notch.
struct CollapsedStripView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var sessionStore: SessionStore
    var layout: TokenIslandWindowLayout
    var hovering: Bool

    private var visiblePets: [AgentSession] {
        Array(sessionStore.sessions.prefix(3))
    }

    private var overflowCount: Int {
        max(0, sessionStore.sessions.count - visiblePets.count)
    }

    private var showsStatusWord: Bool {
        appState.settings.notchDetailedMode || hovering
    }

    var body: some View {
        HStack(spacing: 0) {
            leftWing
                .frame(maxWidth: .infinity, alignment: .leading)
            // Gap for the hardware notch. Without one there is nothing to step
            // around — a 170pt hole would just split the bar in two.
            Color.clear
                .frame(width: layout.hasHardwareNotch ? layout.notchSize.width + 4 : 12)
            rightWing
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .opacity(sessionStore.sessions.isEmpty ? 0 : 1)
    }

    private var leftWing: some View {
        HStack(spacing: 7) {
            ForEach(visiblePets) { session in
                AnimatedPetView(
                    species: PetSpecies.assigned(toSessionID: session.id),
                    phase: session.phase,
                    pixelSize: 2
                )
            }
            if let focused = sessionStore.focusedSession ?? sessionStore.sessions.first {
                CursorBlockView(phase: focused.phase, size: CGSize(width: 4.5, height: 11))
            }
            if overflowCount > 0 {
                Text("+\(overflowCount)")
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundStyle(TITheme.tertiaryText)
            }
            if showsStatusWord, let label = sessionStore.stripDetailLabel {
                Text(label)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(hovering ? TITheme.primaryText : TITheme.secondaryText)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    // Long titles truncate rather than widening the pill.
                    .frame(maxWidth: NotchWingMetrics.labelWidthCap, alignment: .leading)
                    .transition(.opacity)
            }
        }
    }

    private var rightWing: some View {
        HStack(spacing: 4) {
            Text("\(sessionStore.sessions.count)")
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(TITheme.primaryText)
            if hovering {
                Text(sessionStore.sessions.count == 1 ? "session" : "sessions")
                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                    .foregroundStyle(TITheme.secondaryText)
                    .transition(.opacity)
            }
        }
    }
}
