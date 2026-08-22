import AppKit
import SwiftUI

/// The menu bar icon. Clicking it opens the settings window — the sidebar with
/// Integrations, Display, Sound and the rest — because that is the app's real
/// surface. The secondary click gets a small menu for everything else.
///
/// This replaced a SwiftUI `MenuBarExtra` popover that led with the legacy
/// token counter (OTLP/proxy dots, "0 tokens today"), which is not what anyone
/// clicks a session monitor for.
@MainActor
final class StatusItemController: NSObject {
    private let appState: AppState
    private let windowRouter: AppWindowRouter
    private let updateChecker: UpdateChecker
    private let statusItem: NSStatusItem

    init(appState: AppState, windowRouter: AppWindowRouter, updateChecker: UpdateChecker) {
        self.appState = appState
        self.windowRouter = windowRouter
        self.updateChecker = updateChecker
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        guard let button = statusItem.button else { return }
        button.image = AppIconArt.menuBarIcon()
        button.image?.isTemplate = true
        button.toolTip = AppConstants.appName
        button.target = self
        button.action = #selector(handleClick)
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    @objc private func handleClick() {
        let isSecondary = NSApp.currentEvent.map { event in
            event.type == .rightMouseUp || event.modifierFlags.contains(.control)
        } ?? false

        if isSecondary {
            presentMenu()
        } else {
            openSettings()
        }
    }

    /// Attaching the menu to the status item permanently would make every click
    /// open it, so it is shown for this click only and detached again.
    private func presentMenu() {
        statusItem.menu = buildMenu()
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()

        if let update = updateChecker.available {
            menu.addItem(
                item("Update available — \(update.version)", #selector(installUpdate))
            )
            menu.addItem(.separator())
        }

        menu.addItem(item("Settings…", #selector(openSettings), key: ","))
        menu.addItem(
            item(
                appState.settings.showNotchOverlay ? "Hide Island" : "Show Island",
                #selector(toggleIsland)
            )
        )
        menu.addItem(item("Check for Updates", #selector(checkForUpdates)))
        menu.addItem(.separator())
        // The legacy token counter, kept reachable but out of the way.
        menu.addItem(item("Usage Dashboard", #selector(openDashboard)))
        menu.addItem(.separator())
        menu.addItem(item("Quit TokenIsland", #selector(quit), key: "q"))
        return menu
    }

    private func item(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let menuItem = NSMenuItem(title: title, action: action, keyEquivalent: key)
        menuItem.target = self
        return menuItem
    }

    // MARK: - Actions

    @objc private func openDashboard() {
        windowRouter.openDashboard()
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func openSettings() {
        windowRouter.openSettings()
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func toggleIsland() {
        appState.updateSettings { $0.showNotchOverlay.toggle() }
    }

    @objc private func checkForUpdates() {
        updateChecker.checkNow()
    }

    @objc private func installUpdate() {
        updateChecker.installOrOpenDownload()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
