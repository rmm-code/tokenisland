import Combine
import Foundation

/// What an auto-reveal is showing.
enum NotchRevealKind: Equatable, Sendable {
    case completion
    case attention
}

enum TokenIslandNotchState: Equatable, Sendable {
    /// Plain black strip fused with the notch (pets + count when sessions exist).
    case collapsed
    /// Hover widening: same strip, brighter, with status word and count label.
    case hoverPeek
    /// Full session panel (user-opened).
    case expanded
    /// Auto-opened card for a completion or an approval/question.
    case reveal(NotchRevealKind, sessionID: String)
    case error(String)

    var isExpandedLayout: Bool {
        switch self {
        case .expanded, .error, .reveal:
            true
        case .collapsed, .hoverPeek:
            false
        }
    }

    var isReveal: Bool {
        if case .reveal = self { true } else { false }
    }
}

/// Presentation state for the notch overlay. Sessions live in `SessionStore`;
/// this machine only decides what the island is currently showing.
@MainActor
final class TokenIslandStateMachine: ObservableObject {
    @Published private(set) var state: TokenIslandNotchState = .collapsed
    @Published private(set) var geometryDescription = "Unknown display"
    @Published private(set) var hasHardwareNotch = false
    @Published private(set) var isPointerInside = false
    /// Intrinsic height of the reveal card currently on screen, measured by the
    /// SwiftUI layer (0 = not measured yet). Both the island frame and the
    /// window's hit rect size from it, so a tall approval card can't hang
    /// outside either one.
    @Published private(set) var revealContentHeight: CGFloat = 0
    /// Natural height of the expanded panel (header + session list). Kept
    /// across closes on purpose: reopening at the last known size and adjusting
    /// beats opening at the maximum and snapping shut.
    @Published private(set) var panelContentHeight: CGFloat = 0

    /// Dwell before an auto-reveal collapses (Settings → General, default 5s).
    var revealDwellSeconds: Double = 5
    /// Approval/question reveals stay until acted on when true.
    var attentionRevealSticks = true

    private var revealTask: Task<Void, Never>?
    private var overlayEnabled = true

    func updateGeometry(hasHardwareNotch: Bool, description: String) {
        self.hasHardwareNotch = hasHardwareNotch
        self.geometryDescription = description
    }

    func reconcile(settings: AppSettings, errorMessage: String?) {
        overlayEnabled = settings.showNotchOverlay
        revealDwellSeconds = max(2, settings.autoRevealDwellSeconds)
        if let errorMessage, settings.showErrorAlerts {
            transition(to: .error(errorMessage))
            return
        }
        if case .error = state {
            transition(to: .collapsed)
        }
    }

    func setPointerInside(_ isInside: Bool) {
        isPointerInside = isInside
    }

    /// Reported by the notch view once the reveal card has laid out.
    func reportRevealContentHeight(_ height: CGFloat) {
        guard state.isReveal, height > 0 else { return }
        guard abs(height - revealContentHeight) > 0.5 else { return }
        revealContentHeight = height
    }

    /// Reported by the notch view once the expanded panel has laid out.
    func reportPanelContentHeight(_ height: CGFloat) {
        guard height > 0, abs(height - panelContentHeight) > 0.5 else { return }
        panelContentHeight = height
    }

    /// The measurement that applies to whatever the island is showing right now.
    func contentHeight(pinned: Bool) -> CGFloat {
        if pinned { return panelContentHeight }
        switch state {
        case .expanded:
            return panelContentHeight
        case .reveal:
            return revealContentHeight
        case .collapsed, .hoverPeek, .error:
            return 0
        }
    }

    // MARK: - Hover

    func showHoverPeek() {
        guard state == .collapsed else { return }
        transition(to: .hoverPeek)
    }

    func endHoverPeek() {
        guard state == .hoverPeek else { return }
        transition(to: .collapsed)
    }

    // MARK: - Panel

    func toggleExpanded() {
        switch state {
        case .expanded:
            transition(to: .collapsed)
        case .collapsed, .hoverPeek, .reveal, .error:
            expand()
        }
    }

    func expand() {
        revealTask?.cancel()
        transition(to: .expanded)
    }

    func collapse() {
        revealTask?.cancel()
        transition(to: .collapsed)
    }

    // MARK: - Auto reveal

    func showReveal(_ kind: NotchRevealKind, sessionID: String) {
        guard overlayEnabled else { return }
        // Never steal the panel from the user.
        if state == .expanded { return }
        transition(to: .reveal(kind, sessionID: sessionID))

        revealTask?.cancel()
        if kind == .attention, attentionRevealSticks { return }
        let dwell = revealDwellSeconds
        revealTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(dwell))
            guard !Task.isCancelled else { return }
            self?.finishReveal()
        }
    }

    /// Called when the revealed session's condition clears (approval resolved,
    /// user prompt submitted) or dwell elapses.
    func finishReveal() {
        if case .reveal = state {
            transition(to: isPointerInside ? .hoverPeek : .collapsed)
        }
    }

    /// Drops a reveal that points at a session which no longer needs it.
    func reconcileReveal(sessions: [AgentSession]) {
        guard case .reveal(let kind, let sessionID) = state else { return }
        guard let session = sessions.first(where: { $0.id == sessionID }) else {
            finishReveal()
            return
        }
        if kind == .attention, session.phase != .waitingApproval, session.phase != .question {
            finishReveal()
        }
    }

    private func transition(to nextState: TokenIslandNotchState) {
        guard state != nextState else { return }
        // Leaving a reveal drops the measurement; the next one re-measures
        // (reveal → reveal keeps it, so the card doesn't blink between sizes).
        if !nextState.isReveal {
            revealContentHeight = 0
        }
        state = nextState
    }
}
