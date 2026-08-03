import AppKit

@MainActor
final class NotchInteractionController {
    private let stateMachine: TokenIslandStateMachine
    private let appState: AppState
    private var hoverOpenTask: Task<Void, Never>?
    private var hoverCloseTask: Task<Void, Never>?

    init(stateMachine: TokenIslandStateMachine, appState: AppState) {
        self.stateMachine = stateMachine
        self.appState = appState
    }

    func handleHover(_ isHovering: Bool) {
        stateMachine.setPointerInside(isHovering)
        hoverOpenTask?.cancel()
        hoverCloseTask?.cancel()

        guard !appState.settings.pinExpandedNotch else { return }
        if isHovering {
            guard appState.settings.expandOnHover else { return }
            guard !stateMachine.state.isExpandedLayout else { return }
            // Hover opens the FULL panel (reference behavior) — even with no
            // sessions, so the setup hint is discoverable.
            hoverOpenTask = Task { [weak self] in
                // Clamp so hover always feels immediate regardless of stored
                // settings; the sentinel already adds up to ~90ms latency.
                let delay = min(max(self?.appState.settings.hoverOpenDelayMS ?? 50, 0), 250)
                try? await Task.sleep(for: .milliseconds(delay))
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    self?.stateMachine.expand()
                }
            }
        } else {
            guard !appState.settings.preventCloseOnMouseLeave else { return }
            hoverCloseTask = Task { [weak self] in
                let delay = self?.appState.settings.mouseLeaveCloseDelayMS ?? 420
                try? await Task.sleep(for: .milliseconds(delay))
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    guard let self else { return }
                    switch self.stateMachine.state {
                    case .hoverPeek:
                        self.stateMachine.endHoverPeek()
                    case .expanded:
                        self.stateMachine.collapse()
                    case .collapsed, .reveal, .error:
                        break
                    }
                }
            }
        }
    }

    /// Clicking only ever OPENS — closing happens via ✕, ESC, or mouse
    /// leave. A toggle here made rapid clicks fight the hover-open.
    func handleClick() {
        guard appState.settings.enableClickToExpand else { return }
        guard !stateMachine.state.isExpandedLayout else { return }
        stateMachine.expand()
    }

    func handleCollapse() {
        if appState.settings.pinExpandedNotch {
            appState.updateSettings { $0.pinExpandedNotch = false }
        }
        stateMachine.collapse()
    }

    func handleEscape() {
        switch stateMachine.state {
        case .reveal:
            stateMachine.finishReveal()
        case .expanded, .hoverPeek:
            handleCollapse()
        case .collapsed, .error:
            break
        }
    }

    func handleScroll(deltaX: CGFloat, deltaY: CGFloat) {
        guard appState.settings.allowHoverGestures else { return }
        let vertical = abs(deltaY) >= abs(deltaX)
        guard vertical, appState.settings.enableVerticalGestures, abs(deltaY) > 4 else { return }
        if deltaY < 0 {
            stateMachine.expand()
        } else {
            handleCollapse()
        }
    }
}
