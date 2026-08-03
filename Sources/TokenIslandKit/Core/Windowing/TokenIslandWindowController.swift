import AppKit
import Combine
import SwiftUI

@MainActor
final class TokenIslandWindowController {
    private let appState: AppState
    private let usageLimits: UsageLimitsService
    private let geometry = TokenIslandScreenGeometry()
    private let stateMachine: TokenIslandStateMachine
    private let interactionController: NotchInteractionController
    private let windowRouter: AppWindowRouter
    private let jumpService: JumpService
    private var sessionSwitcher: SessionSwitcherController?
    private var window: TokenIslandWindow?
    private var hostingView: TokenIslandHostingView<AnyView>?
    private var currentLayout: TokenIslandWindowLayout?
    private var cancellables: Set<AnyCancellable> = []
    private var hoverSentinel: Task<Void, Never>?
    private var outsideClickMonitor: Any?
    private var sentinelPointerInside = false
    private var knownSessionIDs: Set<String> = []
    private var knownPhases: [String: SessionPhase] = [:]

    init(
        appState: AppState,
        usageLimits: UsageLimitsService,
        windowRouter: AppWindowRouter
    ) {
        self.appState = appState
        self.usageLimits = usageLimits
        self.stateMachine = TokenIslandStateMachine()
        self.interactionController = NotchInteractionController(stateMachine: stateMachine, appState: appState)
        self.windowRouter = windowRouter
        self.jumpService = JumpService(titleMarkerService: appState.titleMarkerService)
        self.sessionSwitcher = SessionSwitcherController(
            sessionStore: appState.sessionStore,
            jumpService: jumpService
        )
        wireSessionStore()
        observeState()
        installOutsideClickMonitor()
        observeScreenChanges()
    }

    /// Plugging in a monitor, closing the lid, or changing resolution moves the
    /// screen the island belongs on. Nothing else recomputes the geometry, so
    /// without this the window keeps a frame measured for a display that may
    /// no longer exist.
    private func observeScreenChanges() {
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.updateWindowVisibility()
            }
        }
    }

    /// "Dismiss auto reveal on outside click" (Settings → General): global
    /// monitors only fire for clicks in OTHER apps — exactly "outside".
    private func installOutsideClickMonitor() {
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.appState.settings.dismissRevealOnOutsideClick else { return }
                if case .reveal = self.stateMachine.state {
                    self.stateMachine.finishReveal()
                }
            }
        }
    }

    func showIfNeeded() {
        stateMachine.reconcile(
            settings: appState.settings,
            errorMessage: appState.errorMessage
        )
        updateWindowVisibility()
    }

    private func wireSessionStore() {
        // Blocked Launcher Apps (Settings → Notifications): events whose
        // terminal hint resolves to a blocked launcher never create sessions.
        appState.sessionStore.launcherFilter = { [weak self] hint in
            guard let self, let bundleID = hint?.bundleIdentifier else { return true }
            return !self.appState.settings.blockedLauncherApps.contains(bundleID)
        }
        // Question answering (QuestionCardView taps and ⌃1–9 shortcuts).
        appState.sessionStore.onAnswerQuestion = { [weak self] session, optionIndex in
            self?.answerQuestion(session: session, optionIndex: optionIndex)
        }
        // Prompt-acknowledge / context-limit / idle-reminder sound cues.
        appState.sessionStore.onSoundCue = { [weak self] cue in
            guard let self else { return }
            SoundBank.shared.play(cue, settings: self.appState.settings)
        }
        appState.sessionStore.onReveal = { [weak self] kind, session in
            guard let self else { return }
            let settings = self.appState.settings
            let isQuiet = settings.quietWhenScreenLocked && SoundBank.shared.isScreenLockedNow
            // Quiet mode suppresses completion UI. Attention still appears
            // so an approval cannot be stranded behind a locked-screen rule.
            if isQuiet, kind == .completion {
                return
            }
            // The stored string is retained for migration compatibility;
            // Settings exposes the two supported states as a direct toggle.
            if kind == .completion,
               settings.subagentNotificationMode == "never",
               session.subagents.contains(where: { !$0.isDone }) {
                return
            }
            if !isQuiet {
                switch kind {
                case .completion:
                    SoundBank.shared.play(.taskComplete, settings: settings)
                case .attention:
                    SoundBank.shared.play(.approvalNeeded, settings: settings)
                }
            }
            // Smart suppression: no auto-expand when that session's own
            // terminal is already frontmost.
            if kind == .completion,
               settings.smartSuppression,
               let sessionBundleID = session.terminalHint?.bundleIdentifier,
               NSWorkspace.shared.frontmostApplication?.bundleIdentifier == sessionBundleID {
                return
            }
            switch kind {
            case .completion:
                self.stateMachine.showReveal(.completion, sessionID: session.id)
            case .attention:
                self.stateMachine.showReveal(.attention, sessionID: session.id)
                // Approval shortcuts (⌃Y/⌃N) need key status right away —
                // deferred out of the current display cycle (macOS 26).
                DispatchQueue.main.async { self.window?.makeKey() }
            }
        }
    }

    /// Session-start and error sound cues, derived from population diffs.
    private func playSessionDiffSounds(_ sessions: [AgentSession]) {
        let settings = appState.settings
        let currentIDs = Set(sessions.map(\.id))
        if !knownSessionIDs.isEmpty, !currentIDs.subtracting(knownSessionIDs).isEmpty {
            SoundBank.shared.play(.sessionStart, settings: settings)
        }
        for session in sessions {
            if let previous = knownPhases[session.id], previous != .error, session.phase == .error {
                SoundBank.shared.play(.taskError, settings: settings)
            }
            knownPhases[session.id] = session.phase
        }
        knownSessionIDs = currentIDs
        knownPhases = knownPhases.filter { currentIDs.contains($0.key) }
    }

    private func createWindowIfNeeded() {
        guard window == nil else { return }
        guard let layout = geometry.layout(settings: appState.settings),
              let screen = NSScreen.screens.first(where: { $0.frame == layout.screenFrame }) ?? NSScreen.main
        else {
            return
        }
        currentLayout = layout
        stateMachine.updateGeometry(
            hasHardwareNotch: layout.hasHardwareNotch,
            description: layout.description
        )

        let window = TokenIslandWindow(screen: screen)
        window.interactionController = interactionController
        window.panelKeyHandler = { [weak self] character in
            self?.handlePanelKey(character) ?? false
        }
        window.applyFullscreenMode(appState.settings.fullscreenOverlayMode, hasHardwareNotch: layout.hasHardwareNotch)
        window.setFrame(layout.windowFrame, display: true)

        let hostingView = TokenIslandHostingView(rootView: rootView(for: layout))
        // The window is frame-driven; hosting-view size constraints only add
        // Auto Layout churn (and intermittent macOS 26 display-cycle
        // exceptions). Disable them entirely.
        hostingView.sizingOptions = []
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor
        hostingView.interactiveRectProvider = { [weak self] in
            guard let self, let layout = self.currentLayout else { return nil }
            let store = self.appState.sessionStore
            let wings = NotchWingMetrics.wings(
                sessionCount: store.sessions.count,
                label: store.stripDetailLabel,
                hovering: self.stateMachine.state == .hoverPeek,
                detailed: self.appState.settings.notchDetailedMode
            )
            // Clicks: the island's real bounds only. Anything wider steals
            // menu-bar and toolbar clicks from the app underneath.
            return layout.islandRect(
                for: self.stateMachine.state,
                pinned: self.appState.settings.pinExpandedNotch,
                wings: wings,
                contentHeight: self.stateMachine.contentHeight(
                    pinned: self.appState.settings.pinExpandedNotch
                )
            )
        }
        // Hover detection runs on the polling sentinel (single source of
        // truth) — AppKit tracking events are unreliable for non-key
        // overlay windows, which made the notch feel dead.
        window.contentView = hostingView

        self.hostingView = hostingView
        self.window = window
        startHoverSentinel()
    }

    /// Deterministic hover detection: compares the global mouse location
    /// against the island's screen rect ~11×/second. Immune to event-routing
    /// quirks, occlusion, and key-window status.
    private func startHoverSentinel() {
        guard hoverSentinel == nil else { return }
        hoverSentinel = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(90))
                guard let self else { return }
                self.pollPointer()
            }
        }
    }

    private func pollPointer() {
        guard appState.settings.showNotchOverlay,
              let window, window.isVisible,
              let layout = currentLayout
        else {
            if sentinelPointerInside {
                sentinelPointerInside = false
                interactionController.handleHover(false)
            }
            return
        }
        let store = appState.sessionStore
        let wings = NotchWingMetrics.wings(
            sessionCount: store.sessions.count,
            label: store.stripDetailLabel,
            hovering: stateMachine.state == .hoverPeek,
            detailed: appState.settings.notchDetailedMode
        )
        let rectInWindow = layout.hoverRect(
            for: stateMachine.state,
            pinned: appState.settings.pinExpandedNotch,
            wings: wings,
            contentHeight: stateMachine.contentHeight(pinned: appState.settings.pinExpandedNotch)
        )
        let screenRect = rectInWindow.offsetBy(dx: window.frame.minX, dy: window.frame.minY)
        followPointerAcrossDisplays(layout: layout)
        let inside = screenRect.contains(NSEvent.mouseLocation)
        guard inside != sentinelPointerInside else { return }
        sentinelPointerInside = inside
        interactionController.handleHover(inside)
    }

    /// Display → "Pointer Display": nothing else re-runs the geometry, so the
    /// island used to stay on whichever screen it was born on until some
    /// unrelated event fired.
    private func followPointerAcrossDisplays(layout: TokenIslandWindowLayout) {
        guard appState.settings.displayTarget == "focus" else { return }
        let location = NSEvent.mouseLocation
        guard let pointerScreen = NSScreen.screens.first(where: { $0.frame.contains(location) }),
              pointerScreen.frame != layout.screenFrame
        else {
            return
        }
        updateWindowVisibility()
    }

    private func observeState() {
        stateMachine.$state
            .receive(on: RunLoop.main)
            .sink { [weak self] state in
                guard let self else { return }
                self.updateWindowVisibility()
                // Panel shortcuts (⌃Y/⌃N/…) need key status — but only steal
                // focus when an approval is actually waiting; hover-expands
                // must not yank typing focus from the user's app. Deferred
                // out of the current display cycle: key-window flips during
                // constraint updates intermittently crash on macOS 26.
                DispatchQueue.main.async {
                    if state.isExpandedLayout, !self.appState.approvalCenter.pending.isEmpty {
                        self.window?.makeKey()
                    } else if !state.isExpandedLayout, self.window?.isKeyWindow == true {
                        self.window?.resignKey()
                    }
                }
            }
            .store(in: &cancellables)

        appState.$settings
            .combineLatest(appState.$errorMessage)
            .receive(on: RunLoop.main)
            .sink { [weak self] settings, errorMessage in
                guard let self else { return }
                self.stateMachine.reconcile(settings: settings, errorMessage: errorMessage)
                self.updateWindowVisibility()
            }
            .store(in: &cancellables)

        // Session changes resize the collapsed strip (wings) and can clear
        // an attention reveal once the approval is answered in-terminal.
        appState.sessionStore.$sessions
            .receive(on: RunLoop.main)
            .sink { [weak self] sessions in
                guard let self else { return }
                self.stateMachine.reconcileReveal(sessions: sessions)
                self.playSessionDiffSounds(sessions)
                self.updateWindowVisibility()
            }
            .store(in: &cancellables)
    }

    private func updateWindowVisibility() {
        guard appState.settings.showNotchOverlay else {
            window?.orderOut(nil)
            return
        }
        createWindowIfNeeded()
        // A stale frame is worse than no island: if the geometry can't be
        // resolved, stay hidden instead of re-showing the old one.
        guard updateLayout(), shouldShowIdleIsland else {
            window?.orderOut(nil)
            return
        }
        window?.orderFrontRegardless()
    }

    /// An empty collapsed strip is invisible on a notched Mac — it *is* the
    /// notch. On every other display it is a black tab glued over the menu bar,
    /// so it only earns its place once there is something to show.
    private var shouldShowIdleIsland: Bool {
        guard stateMachine.state == .collapsed else { return true }
        let hasLiveSession = appState.sessionStore.sessions.contains {
            $0.phase.isActive || $0.phase == .error
        }
        if hasLiveSession { return true }
        if appState.settings.autoHideWhenNoSessions { return false }
        return currentLayout?.hasHardwareNotch ?? true
    }

    @discardableResult
    private func updateLayout() -> Bool {
        guard let layout = geometry.layout(settings: appState.settings) else {
            return false
        }
        if layout != currentLayout {
            hostingView?.rootView = rootView(for: layout)
        }
        currentLayout = layout
        stateMachine.updateGeometry(
            hasHardwareNotch: layout.hasHardwareNotch,
            description: layout.description
        )
        window?.applyFullscreenMode(appState.settings.fullscreenOverlayMode, hasHardwareNotch: layout.hasHardwareNotch)
        window?.setFrame(layout.windowFrame, display: true, animate: false)
        return true
    }

    private func jump(to session: AgentSession) {
        guard !appState.settings.disableClickToJump else { return }
        interactionController.handleCollapse()
        jumpService.promptForAccessibilityIfNeverAsked()
        jumpService.jump(to: session)
    }

    /// Focuses the session's terminal, waits for the window to land, then
    /// types the option digit + Return via CGEvent. Falls back silently when
    /// Accessibility is missing — the card keeps its "Answer in terminal"
    /// button for that case.
    private func answerQuestion(session: AgentSession, optionIndex: Int) {
        guard session.phase == .question,
              (1...session.questionOptions.count).contains(optionIndex)
        else { return }
        interactionController.handleCollapse()
        jumpService.promptForAccessibilityIfNeverAsked()
        guard jumpService.focusForInput(to: session) else { return }
        KeyInjection.typeOption(index: optionIndex, thenReturn: true)
    }

    /// ⌃Y approve · ⌃N deny · ⌃A always allow · ⌃B bypass · ⌃T jump ·
    /// ⌃1–9 answer a pending question's option.
    private func handlePanelKey(_ character: Character) -> Bool {
        guard stateMachine.state.isExpandedLayout else { return false }
        let center = appState.approvalCenter
        let approval = focusedPendingApproval()

        if let digit = character.wholeNumberValue, (1...9).contains(digit) {
            guard let session = focusedQuestionSession(),
                  digit <= session.questionOptions.count
            else { return false }
            answerQuestion(session: session, optionIndex: digit)
            return true
        }

        switch character {
        case "y":
            guard let approval else { return false }
            center.approve(id: approval.id)
        case "n":
            guard let approval else { return false }
            center.deny(id: approval.id)
        case "a":
            guard let approval else { return false }
            center.alwaysAllow(id: approval.id)
        case "b":
            guard let approval else { return false }
            center.bypass(id: approval.id)
        case "t":
            guard let session = appState.sessionStore.focusedSession else { return false }
            jump(to: session)
        default:
            return false
        }
        return true
    }

    /// The session whose question ⌃1–9 should answer: the revealed session
    /// first, then the focused one.
    private func focusedQuestionSession() -> AgentSession? {
        if case .reveal(.attention, let sessionID) = stateMachine.state,
           let session = appState.sessionStore.session(withID: sessionID),
           session.phase == .question {
            return session
        }
        if let focused = appState.sessionStore.focusedSession, focused.phase == .question {
            return focused
        }
        return appState.sessionStore.sessions.first { $0.phase == .question }
    }

    private func focusedPendingApproval() -> PendingApproval? {
        if case .reveal(.attention, let sessionID) = stateMachine.state,
           let approval = appState.approvalCenter.pendingApproval(forSessionID: sessionID) {
            return approval
        }
        if let focused = appState.sessionStore.focusedSession,
           let approval = appState.approvalCenter.pendingApproval(forSessionID: focused.id) {
            return approval
        }
        return appState.approvalCenter.pending.last
    }

    private func rootView(for layout: TokenIslandWindowLayout) -> AnyView {
        AnyView(
            TokenIslandNotchView(
                stateMachine: stateMachine,
                layout: layout,
                interactionController: interactionController,
                usageLimits: usageLimits,
                openSettings: { [weak self] in
                    // Collapse first so the panel doesn't hang over Settings.
                    self?.interactionController.handleCollapse()
                    self?.windowRouter.openSettings()
                },
                onJump: { [weak self] session in self?.jump(to: session) }
            )
            .environmentObject(appState)
            .environmentObject(appState.sessionStore)
            .environmentObject(appState.approvalCenter)
            .preferredColorScheme(.dark)
        )
    }
}
