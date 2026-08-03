import AppKit
import Foundation

/// Pane-precise drivers for terminals that expose per-tab TTYs or a control
/// CLI. The TTY is the one identity Claude Code's hook environment gives us
/// for free, and it survives any title rewriting — this is the "exact tab and
/// split" path for Terminal.app and iTerm2 (AppleScript; first use triggers
/// the macOS Automation permission prompt), WezTerm (`wezterm cli`), and
/// kitty (`kitten @`, remote control only).
///
/// Warp (dev.warp.Warp-Stable) exposes no public pane/tab API — no driver;
/// Warp sessions fall through to the AX title scan / app activation.
@MainActor
enum TerminalDrivers {
    /// Selects the exact Terminal.app tab hosting `ttyPath`.
    static func focusTerminalAppTab(ttyPath: String) -> Bool {
        let script = """
        tell application "Terminal"
            repeat with w in windows
                repeat with t in tabs of w
                    if tty of t is equal to "\(ttyPath)" then
                        set selected tab of w to t
                        set index of w to 1
                        activate
                        return true
                    end if
                end repeat
            end repeat
        end tell
        return false
        """
        return runBooleanScript(script)
    }

    /// Selects the exact iTerm2 session (tab/split) hosting `ttyPath`.
    static func focusITermSession(ttyPath: String) -> Bool {
        let script = """
        tell application "iTerm2"
            repeat with w in windows
                repeat with t in tabs of w
                    repeat with s in sessions of t
                        if tty of s is equal to "\(ttyPath)" then
                            select s
                            select t
                            select w
                            activate
                            return true
                        end if
                    end repeat
                end repeat
            end repeat
        end tell
        return false
        """
        return runBooleanScript(script)
    }

    // MARK: - WezTerm (control CLI)

    /// Activates the exact WezTerm pane hosting `ttyPath`. WezTerm has no
    /// AppleScript dictionary, but `wezterm cli list --format json` reports
    /// every pane's `tty_name` + `pane_id`, and `activate-pane` jumps to it.
    static func focusWezTermPane(ttyPath: String) -> Bool {
        guard let list = runTool(["wezterm", "cli", "list", "--format", "json"]),
              list.status == 0,
              let entries = try? JSONSerialization.jsonObject(with: list.stdout) as? [[String: Any]],
              let paneID = entries.first(where: { ($0["tty_name"] as? String) == ttyPath })?["pane_id"] as? NSNumber
        else { return false }

        guard let activate = runTool(["wezterm", "cli", "activate-pane", "--pane-id", paneID.stringValue]),
              activate.status == 0
        else { return false }
        activateApp(bundleID: "com.github.wez.wezterm")
        return true
    }

    // MARK: - kitty (remote control)

    /// Focuses the kitty window whose title carries the session's marker.
    /// Only works when remote control is enabled (`allow_remote_control yes`
    /// in kitty.conf) — matching by env/tty via `kitten @ ls` is unreliable
    /// across configs, so we match the title we stamped ourselves. Any
    /// failure (remote control off, no match, kitten missing) returns false
    /// silently and the jump degrades to the AX scan.
    static func focusKittyWindow(markerTitle: String) -> Bool {
        let pattern = NSRegularExpression.escapedPattern(for: markerTitle)
        guard let result = runTool(["kitten", "@", "focus-window", "--match", "title:\(pattern)"]),
              result.status == 0
        else { return false }
        activateApp(bundleID: "net.kovidgoyal.kitty")
        return true
    }

    // MARK: - Process plumbing

    private static func activateApp(bundleID: String) {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .first?
            .activate()
    }

    /// Runs a CLI tool via /usr/bin/env with an argument array (no shell)
    /// and a hard timeout. Homebrew/kitty paths are appended because
    /// menu-bar apps inherit a minimal PATH. Never throws: launch failure or
    /// timeout returns nil so the caller falls through to the next strategy.
    private static func runTool(
        _ arguments: [String],
        timeout: TimeInterval = 2.0
    ) -> (status: Int32, stdout: Data)? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = arguments

        var environment = ProcessInfo.processInfo.environment
        let basePath = environment["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
        environment["PATH"] = basePath
            + ":/opt/homebrew/bin:/usr/local/bin:/Applications/kitty.app/Contents/MacOS"
        process.environment = environment

        let stdout = Pipe()
        process.standardOutput = stdout
        process.standardError = FileHandle.nullDevice

        let finished = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in finished.signal() }
        do {
            try process.run()
        } catch {
            return nil
        }
        // These tools emit small outputs (well under the 64 KB pipe buffer),
        // so it's safe to wait first and drain after. A tool that floods
        // stdout would stall against the full pipe and hit the timeout,
        // which simply degrades to the next jump strategy.
        guard finished.wait(timeout: .now() + timeout) == .success else {
            process.terminate()
            AppLog.telemetry.error("Terminal driver timed out: \(arguments.joined(separator: " "))")
            return nil
        }
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        return (process.terminationStatus, data)
    }

    private static func runBooleanScript(_ source: String) -> Bool {
        guard let script = NSAppleScript(source: source) else { return false }
        var errorInfo: NSDictionary?
        let output = script.executeAndReturnError(&errorInfo)
        if let errorInfo {
            AppLog.telemetry.error("AppleScript jump failed: \(errorInfo)")
            return false
        }
        return output.booleanValue
    }
}
