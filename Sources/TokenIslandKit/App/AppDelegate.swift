import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    static var environment: AppEnvironment?

    private var notchWindowController: TokenIslandWindowController?
    private var onboardingWindowController: OnboardingWindowController?
    private var updateCheckTask: Task<Void, Never>?
    private var statusItemController: StatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        installExceptionLogger()
        NSApp.setActivationPolicy(.accessory)
        guard let environment = Self.environment else { return }

        statusItemController = StatusItemController(
            appState: environment.appState,
            windowRouter: environment.windowRouter,
            updateChecker: environment.updateChecker
        )

        notchWindowController = TokenIslandWindowController(
            appState: environment.appState,
            usageLimits: environment.usageLimits,
            windowRouter: environment.windowRouter
        )
        Task { @MainActor in
            await environment.appState.start()
            notchWindowController?.showIfNeeded()
            environment.updateChecker.checkIfDue(
                enabled: environment.appState.settings.autoCheckForUpdates
            )
            startUpdateCheckLoop(environment: environment)
            if !environment.appState.settings.hasCompletedOnboarding {
                onboardingWindowController = OnboardingWindowController(appState: environment.appState)
                onboardingWindowController?.showWindow(nil)
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    /// A long-running menu bar app rarely relaunches, so the launch check
    /// alone would leave it on an old build for weeks. The checker itself is
    /// rate-limited; this just gives it the chance.
    private func startUpdateCheckLoop(environment: AppEnvironment) {
        updateCheckTask = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3600))
                guard !Task.isCancelled else { return }
                environment.updateChecker.checkIfDue(
                    enabled: environment.appState.settings.autoCheckForUpdates
                )
            }
        }
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
            // No force-unwrap here of all places: this runs while the app is
            // already crashing, and a trap would destroy the very log it is
            // trying to write.
            let base = FileManager.default
                .urls(for: .applicationSupportDirectory, in: .userDomainMask)
                .first
                ?? URL(fileURLWithPath: NSHomeDirectory())
                    .appendingPathComponent("Library/Application Support")
            let url = base.appendingPathComponent("TokenIsland/last-exception.log")
            try? FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try? Data(text.utf8).write(to: url)
        }
    }
}
