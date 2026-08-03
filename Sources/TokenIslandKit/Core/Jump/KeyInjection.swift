import ApplicationServices
import CoreGraphics

/// Synthesizes keystrokes into the frontmost app via CGEvent — used to answer
/// `AskUserQuestion` prompts after `JumpService` focused the session's
/// terminal. Requires the Accessibility permission (already granted for
/// window jumping); degrades by returning false so callers can fall back to
/// "Answer in terminal".
@MainActor
enum KeyInjection {
    /// kVK_ANSI_1 … kVK_ANSI_9 — ANSI digit keycodes are not contiguous.
    private static let digitKeyCodes: [CGKeyCode] = [18, 19, 20, 21, 23, 22, 26, 28, 25]
    private static let returnKeyCode: CGKeyCode = 36

    /// Types the digit for a 1-based option index and optionally Return as one
    /// immediate event sequence. Returns false without typing when the events
    /// cannot all be prepared first.
    @discardableResult
    static func typeOption(index: Int, thenReturn: Bool) -> Bool {
        guard AXIsProcessTrusted() else { return false }
        guard (1...9).contains(index) else { return false }
        var keyCodes = [digitKeyCodes[index - 1]]
        if thenReturn { keyCodes.append(returnKeyCode) }
        return press(keyCodes)
    }

    @discardableResult
    private static func press(_ keyCodes: [CGKeyCode]) -> Bool {
        guard let source = CGEventSource(stateID: .hidSystemState) else { return false }
        let events = keyCodes.compactMap { keyCode -> (CGEvent, CGEvent)? in
            guard let down = CGEvent(
                keyboardEventSource: source,
                virtualKey: keyCode,
                keyDown: true
            ), let up = CGEvent(
                keyboardEventSource: source,
                virtualKey: keyCode,
                keyDown: false
            ) else { return nil }
            return (down, up)
        }
        guard events.count == keyCodes.count else { return false }
        for (down, up) in events {
            down.post(tap: .cghidEventTap)
            up.post(tap: .cghidEventTap)
        }
        return true
    }
}
