import AppKit
import SwiftUI

@MainActor
final class OnboardingWindowController: NSWindowController {
    init(appState: AppState) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 640),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "TokenIsland Setup"
        window.center()
        super.init(window: window)
        let hostingView = NSHostingView(
            rootView: OnboardingView { [weak window] in
                window?.close()
            }
            .frame(width: 760, height: 640)
            .environmentObject(appState)
            .preferredColorScheme(.dark)
        )
        // The window frame is fixed; SwiftUI must never drive it. Default
        // sizing options let NSHostingView resize the window to the content's
        // ideal size, which loops on macOS 26 ("more Update Constraints
        // passes than views") and crashes — seen on the Accessibility step.
        hostingView.sizingOptions = []
        window.contentView = hostingView
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
