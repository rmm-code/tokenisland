import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    static var environment: AppEnvironment?

    private var notchWindowController: TokenIslandWindowController?
    private var onboardingWindowController: OnboardingWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        installExceptionLogger()
        NSApp.setActivationPolicy(.accessory)
        guard let environment = Self.environment else { return }

        notchWindowController = TokenIslandWindowController(
            appState: environment.appState,
            usageLimits: environment.usageLimits,
            windowRouter: environment.windowRouter
        )
        Task { @MainActor in
            await environment.appState.start()
            notchWindowController?.showIfNeeded()
            if !environment.appState.settings.hasCompletedOnboarding {
                onboardingWindowController = OnboardingWindowController(appState: environment.appState)
                onboardingWindowController?.showWindow(nil)
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    /// macOS 26 occasionally throws Auto Layout exceptions in the display
    /// cycle and AppKit converts them to crashes without recording the
    /// reason. Persist it so the next crash is diagnosable:
    /// ~/Library/Application Support/TokenIsland/last-exception.log
    private func installExceptionLogger() {
        NSSetUncaughtExceptionHandler { exception in
            let text = """
            \(Date()) — \(exception.name.rawValue)
            reason: \(exception.reason ?? "nil")
            stack:
            \(exception.callStackSymbols.joined(separator: "\n"))
            """
            let url = FileManager.default
                .urls(for: .applicationSupportDirectory, in: .userDomainMask)
                .first!
                .appendingPathComponent("TokenIsland/last-exception.log")
            try? FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try? Data(text.utf8).write(to: url)
        }
    }
}
