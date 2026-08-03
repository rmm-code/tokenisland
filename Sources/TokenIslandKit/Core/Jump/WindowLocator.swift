import AppKit
import ApplicationServices

/// Accessibility-based window lookup: finds the window whose title carries a
/// session's marker slug. Requires the Accessibility permission (same one the
/// reference app asks for during onboarding).
@MainActor
enum WindowLocator {
    struct WindowHit {
        let application: NSRunningApplication
        let window: AXUIElement
        let title: String
    }

    static var hasAccessibilityPermission: Bool {
        AXIsProcessTrusted()
    }

    /// Shows the system prompt directing the user to System Settings.
    /// (Key spelled literally: the `kAXTrustedCheckOptionPrompt` global is
    /// not concurrency-safe under Swift 6.)
    @discardableResult
    static func requestAccessibilityPermission() -> Bool {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    /// Apps we bother scanning: known terminals/IDEs first, then anything
    /// regular if `restrictToKnownHosts` is false.
    private static let knownHostBundleIDs: Set<String> = [
        "com.apple.Terminal",
        "com.googlecode.iterm2",
        "com.mitchellh.ghostty",
        "dev.warp.Warp-Stable",
        "com.github.wez.wezterm",
        "net.kovidgoyal.kitty",
        "org.alacritty",
        "co.zeit.hyper",
        "com.microsoft.VSCode",
        "com.todesktop.230313mzl4w4u92", // Cursor
        "com.exafunction.windsurf",
        "dev.zed.Zed"
    ]

    static func findWindow(
        titleContaining needle: String,
        preferredBundleID: String? = nil
    ) -> WindowHit? {
        guard hasAccessibilityPermission, !needle.isEmpty else { return nil }

        let running = NSWorkspace.shared.runningApplications
        var candidates = running.filter { app in
            guard let bundleID = app.bundleIdentifier else { return false }
            return knownHostBundleIDs.contains(bundleID)
        }
        // Search the session's own terminal first.
        if let preferredBundleID {
            candidates.sort { ($0.bundleIdentifier == preferredBundleID ? 0 : 1) < ($1.bundleIdentifier == preferredBundleID ? 0 : 1) }
        }

        for app in candidates {
            if let hit = scan(app: app, needle: needle) {
                return hit
            }
        }
        return nil
    }

    private static func scan(app: NSRunningApplication, needle: String) -> WindowHit? {
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        var windowsValue: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &windowsValue)
        guard result == .success, let windows = windowsValue as? [AXUIElement] else { return nil }

        for window in windows {
            var titleValue: CFTypeRef?
            guard AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &titleValue) == .success,
                  let title = titleValue as? String,
                  title.localizedCaseInsensitiveContains(needle)
            else { continue }
            return WindowHit(application: app, window: window, title: title)
        }
        return nil
    }

    /// Raises the window and activates its application.
    static func focus(_ hit: WindowHit) {
        AXUIElementPerformAction(hit.window, kAXRaiseAction as CFString)
        let focusedValue: CFTypeRef = kCFBooleanTrue
        AXUIElementSetAttributeValue(hit.window, kAXMainAttribute as CFString, focusedValue)
        hit.application.activate()
    }
}
