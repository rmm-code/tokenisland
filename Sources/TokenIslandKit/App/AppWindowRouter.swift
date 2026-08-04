import AppKit
import SwiftUI

@MainActor
final class AppWindowRouter {
    private let appState: AppState
    private var dashboardWindowController: NSWindowController?
    private var settingsWindowController: NSWindowController?
    private var onboardingWindowController: OnboardingWindowController?

    init(appState: AppState) {
        self.appState = appState
    }

    /// Replays the welcome + setup walkthrough. It otherwise appears exactly
    /// once, on the first launch, and there was no way back to it — which is
    /// where the integration list and permission explanations live.
    func openWelcomeGuide() {
        if let window = onboardingWindowController?.window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let controller = OnboardingWindowController(appState: appState)
        onboardingWindowController = controller
        controller.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func openDashboard() {
        if let window = dashboardWindowController?.window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let rootView = DashboardView()
            .environmentObject(appState)
            .preferredColorScheme(.dark)
            .frame(minWidth: 940, minHeight: 640)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1080, height: 720),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "TokenIsland Dashboard"
        window.center()
        // The user resizes this window; SwiftUI must not (macOS 26 loop).
        let hostingView = NSHostingView(rootView: rootView)
        hostingView.sizingOptions = []
        window.contentView = hostingView
        let controller = NSWindowController(window: window)
        dashboardWindowController = controller
        controller.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func openSettings() {
        // Never route through the SwiftUI Settings scene
        // (`showSettingsWindow:`): for accessory (no-Dock) apps the action
        // reports success without reliably surfacing a window. Our own
        // controller is deterministic.
        NSApp.activate(ignoringOtherApps: true)

        if let window = settingsWindowController?.window {
            window.makeKeyAndOrderFront(nil)
            return
        }

        let rootView = SettingsView()
            .environmentObject(appState)
            .preferredColorScheme(.dark)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 860, height: 640),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "TokenIsland Settings"
        window.isReleasedWhenClosed = false
        window.center()
        // The user resizes this window; SwiftUI must not (macOS 26 loop).
        let hostingView = NSHostingView(rootView: rootView)
        hostingView.sizingOptions = []
        window.contentView = hostingView
        let controller = NSWindowController(window: window)
        settingsWindowController = controller
        controller.showWindow(nil)
        window.makeKeyAndOrderFront(nil)
    }
}
