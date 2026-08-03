import AppKit

@MainActor
final class TokenIslandWindow: NSWindow {
    weak var interactionController: NotchInteractionController?
    /// Panel shortcuts (⌃Y approve, ⌃N deny, ⌃A always, ⌃B bypass, ⌃T jump,
    /// ⌃1–9 answer question options). Returns true when the key was consumed.
    var panelKeyHandler: ((Character) -> Bool)?

    init(screen: NSScreen) {
        super.init(
            contentRect: screen.frame,
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        configure()
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func scrollWheel(with event: NSEvent) {
        interactionController?.handleScroll(deltaX: event.scrollingDeltaX, deltaY: event.scrollingDeltaY)
    }

    override func cancelOperation(_ sender: Any?) {
        interactionController?.handleEscape()
    }

    override func keyDown(with event: NSEvent) {
        if event.modifierFlags.contains(.control),
           let character = event.charactersIgnoringModifiers?.lowercased().first,
           panelKeyHandler?(character) == true {
            return
        }
        super.keyDown(with: event)
    }

    func applyFullscreenMode(_ mode: FullscreenOverlayMode, hasHardwareNotch: Bool) {
        let showInFullscreen: Bool
        switch mode {
        case .never:
            showInFullscreen = false
        case .notchedScreens:
            showInFullscreen = hasHardwareNotch
        case .always:
            showInFullscreen = true
        }

        var behavior: NSWindow.CollectionBehavior = [
            .stationary,
            .ignoresCycle
        ]
        if showInFullscreen {
            behavior.insert(.fullScreenAuxiliary)
            behavior.insert(.canJoinAllSpaces)
        }
        collectionBehavior = behavior
    }

    private func configure() {
        isOpaque = false
        alphaValue = 1
        backgroundColor = .clear
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isMovable = false
        hasShadow = false
        acceptsMouseMovedEvents = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        applyFullscreenMode(.notchedScreens, hasHardwareNotch: true)
        level = .statusBar + 8
    }
}
