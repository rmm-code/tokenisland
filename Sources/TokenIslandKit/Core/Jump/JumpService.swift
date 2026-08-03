import AppKit

enum JumpResult: Equatable {
    case exactSession
    case applicationOnly
    case failed

    var succeeded: Bool { self != .failed }
}

/// Click-to-jump: lands the user on the exact terminal tab/split hosting a
/// session. Resolution order:
///   1. Pane-precise drivers (Terminal.app, iTerm2, WezTerm, kitty)
///   2. Accessibility title-marker scan (any known terminal/IDE)
///   3. Activate the session's terminal app
@MainActor
final class JumpService {
    private let titleMarkerService: TitleMarkerService

    init(titleMarkerService: TitleMarkerService) {
        self.titleMarkerService = titleMarkerService
    }

    private var hasPromptedForAccessibility = false

    var hasAccessibilityPermission: Bool {
        WindowLocator.hasAccessibilityPermission
    }

    /// Shows the system Accessibility prompt at most once per app run —
    /// repeated clicks must never spam the dialog. Jumps degrade to
    /// app-activation until the permission is granted.
    func promptForAccessibilityIfNeverAsked() {
        guard !hasAccessibilityPermission, !hasPromptedForAccessibility else { return }
        hasPromptedForAccessibility = true
        WindowLocator.requestAccessibilityPermission()
    }

    @discardableResult
    func focusForInput(to session: AgentSession) -> Bool {
        let hint = session.terminalHint
        let tty = hint?.ttyPath ?? ""
        switch hint?.bundleIdentifier {
        case "com.apple.Terminal" where !tty.isEmpty:
            if TerminalDrivers.focusTerminalAppTab(ttyPath: tty) { return true }
        case "com.googlecode.iterm2" where !tty.isEmpty:
            if TerminalDrivers.focusITermSession(ttyPath: tty) { return true }
        case "com.github.wez.wezterm" where !tty.isEmpty:
            if TerminalDrivers.focusWezTermPane(ttyPath: tty) { return true }
        case "net.kovidgoyal.kitty":
            if let marker = titleMarkerService.markerTitle(forSessionID: session.id),
               TerminalDrivers.focusKittyWindow(markerTitle: marker) {
                return true
            }
        default:
            break
        }

        if let marker = titleMarkerService.markerTitle(forSessionID: session.id),
           let hit = WindowLocator.findWindow(
               titleContaining: marker,
               preferredBundleID: hint?.bundleIdentifier
           ) {
            WindowLocator.focus(hit)
            return true
        }
        return false
    }

    @discardableResult
    func jump(to session: AgentSession) -> JumpResult {
        let hint = session.terminalHint

        // Custom URL schemes are useful for navigation, but successful URL
        // opening does not prove that the exact pane is ready for input.
        if let bundleID = hint?.bundleIdentifier,
           let template = JumpRules.template(forBundleID: bundleID),
           let marker = titleMarkerService.markerTitle(forSessionID: session.id),
           let url = JumpRules.url(fromTemplate: template, markerTitle: marker),
           NSWorkspace.shared.open(url) {
            return .applicationOnly
        }

        if focusForInput(to: session) {
            return .exactSession
        }

        // Also try the project name — helps when the CLI overwrote our title.
        // It is deliberately classified as app-only because project names are
        // not unique enough to authorize global key injection.
        if !session.projectName.isEmpty,
           let hit = WindowLocator.findWindow(
               titleContaining: session.projectName,
               preferredBundleID: hint?.bundleIdentifier
           ) {
            WindowLocator.focus(hit)
            return .applicationOnly
        }

        // 3. App-level activation.
        if let bundleID = hint?.bundleIdentifier,
           let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first {
            app.activate()
            return .applicationOnly
        }
        return .failed
    }
}
