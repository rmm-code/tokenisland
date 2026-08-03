import AppKit
import SwiftUI

/// ⌃G session switcher (⌘Tab-style): hold ⌃ and tap G to cycle a centered HUD
/// over live sessions (⌃⇧G reverses); releasing ⌃ jumps to the highlighted
/// session. Uses global + local NSEvent monitors — global keyDown monitoring
/// needs the Accessibility permission and degrades silently without it (the
/// local monitor still works while a TokenIsland window is key).
///
/// Owned by `TokenIslandWindowController` for the app's lifetime, so monitor
/// teardown in deinit is intentionally omitted.
@MainActor
final class SessionSwitcherController {
    private let sessionStore: SessionStore
    private let jumpService: JumpService
    private let model = SwitcherHUDModel()
    private var panel: NSPanel?
    private var hostingView: NSHostingView<SwitcherHUDView>?
    private var isActive = false

    private static let gKeyCode: UInt16 = 5 // kVK_ANSI_G

    init(sessionStore: SessionStore, jumpService: JumpService) {
        self.sessionStore = sessionStore
        self.jumpService = jumpService
        installMonitors()
    }

    // MARK: - Event monitors

    private func installMonitors() {
        // Handlers run on the main thread; only Sendable scalars cross into
        // the assumeIsolated hop.
        _ = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let keyCode = event.keyCode
            let flags = event.modifierFlags
            MainActor.assumeIsolated {
                _ = self?.handleKeyDown(keyCode: keyCode, flags: flags)
            }
        }
        _ = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let keyCode = event.keyCode
            let flags = event.modifierFlags
            let handled = MainActor.assumeIsolated {
                self?.handleKeyDown(keyCode: keyCode, flags: flags) ?? false
            }
            return handled ? nil : event
        }
        _ = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            let flags = event.modifierFlags
            MainActor.assumeIsolated {
                self?.handleFlagsChanged(flags: flags)
            }
        }
        _ = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            let flags = event.modifierFlags
            MainActor.assumeIsolated {
                self?.handleFlagsChanged(flags: flags)
            }
            return event
        }
    }

    /// ⌃G advances the selection (⇧ reverses); first press opens the HUD
    /// highlighting the next session. Returns true when consumed.
    private func handleKeyDown(keyCode: UInt16, flags: NSEvent.ModifierFlags) -> Bool {
        guard keyCode == Self.gKeyCode,
              flags.contains(.control),
              !flags.contains(.command), !flags.contains(.option)
        else { return false }

        if !isActive {
            let sessions = sessionStore.sessions
            guard !sessions.isEmpty else { return false }
            isActive = true
            model.sessions = sessions
            model.selectedIndex = 0
        }
        step(reverse: flags.contains(.shift))
        showHUD()
        return true
    }

    /// Releasing ⌃ commits the highlighted session.
    private func handleFlagsChanged(flags: NSEvent.ModifierFlags) {
        guard isActive, !flags.contains(.control) else { return }
        commit()
    }

    private func step(reverse: Bool) {
        let count = model.sessions.count
        guard count > 0 else { return }
        let next = model.selectedIndex + (reverse ? -1 : 1)
        model.selectedIndex = ((next % count) + count) % count
    }

    private func commit() {
        isActive = false
        panel?.orderOut(nil)
        guard model.sessions.indices.contains(model.selectedIndex) else { return }
        jumpService.jump(to: model.sessions[model.selectedIndex])
    }

    // MARK: - HUD panel

    private func showHUD() {
        let panel = panel ?? makePanel()
        if let hostingView {
            hostingView.layoutSubtreeIfNeeded()
            let size = hostingView.fittingSize
            let screen = NSScreen.main ?? NSScreen.screens.first
            let screenFrame = screen?.visibleFrame ?? .zero
            panel.setFrame(
                NSRect(
                    x: screenFrame.midX - size.width / 2,
                    y: screenFrame.midY - size.height / 2,
                    width: size.width,
                    height: size.height
                ),
                display: true
            )
        }
        panel.orderFrontRegardless()
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        let hostingView = NSHostingView(rootView: SwitcherHUDView(model: model))
        // Panel frame is set manually; never let SwiftUI resize it (macOS 26
        // constraint-loop crash class).
        hostingView.sizingOptions = []
        panel.contentView = hostingView
        self.hostingView = hostingView
        self.panel = panel
        return panel
    }
}

// MARK: - HUD view

@MainActor
final class SwitcherHUDModel: ObservableObject {
    @Published var sessions: [AgentSession] = []
    @Published var selectedIndex = 0
}

/// Compact ⌘Tab-style list: pet + "project · title" per session, the
/// selected row highlighted.
struct SwitcherHUDView: View {
    @ObservedObject var model: SwitcherHUDModel

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(Array(model.sessions.enumerated()), id: \.element.id) { index, session in
                row(session, selected: index == model.selectedIndex)
            }
        }
        .padding(10)
        .frame(width: 340)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.black.opacity(0.94))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
        .preferredColorScheme(.dark)
    }

    private func row(_ session: AgentSession, selected: Bool) -> some View {
        HStack(spacing: 8) {
            SessionPetBadge(session: session, pixelSize: 1.8, showCursor: false)
                .frame(width: 26)
            Text("\(session.projectName) · \(session.displayTitle)")
                .font(.system(size: 11.5, weight: selected ? .semibold : .regular))
                .foregroundStyle(selected ? TITheme.primaryText : TITheme.secondaryText)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 10)
            Text(session.statusWord)
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(TITheme.tertiaryText)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(selected ? Color.white.opacity(0.14) : Color.clear)
        )
    }
}
