import AppKit

/// Extra black width on each side of the physical notch (pets on the left,
/// session count on the right). Asymmetric by design, like the reference.
struct NotchWings: Equatable {
    var left: CGFloat
    var right: CGFloat

    static let none = NotchWings(left: 0, right: 0)

    var total: CGFloat { left + right }
    /// How far the island's center shifts off the notch center.
    var centerOffset: CGFloat { (right - left) / 2 }
}

enum NotchWingMetrics {
    /// Collapsed/hover wing widths for the current session population.
    /// Symmetrized: the pill stays centered on the physical notch so
    /// expanding always grows evenly from the center (no lateral lurch).
    /// Widest the Detailed label may push the wing out; longer titles truncate
    /// in place instead of stretching the pill across the menu bar.
    static let labelWidthCap: CGFloat = 110

    static func wings(
        sessionCount: Int,
        label: String?,
        hovering: Bool,
        detailed: Bool
    ) -> NotchWings {
        guard sessionCount > 0 else { return .none }
        let petCount = min(sessionCount, 3)
        var left: CGFloat = CGFloat(petCount) * 26 + 14
        if sessionCount > petCount { left += 12 }
        if detailed || hovering, let label, !label.isEmpty {
            left += min(CGFloat(label.count) * 7.2, labelWidthCap) + 12
        }
        var right: CGFloat = 26
        if hovering { right += 58 }
        let balanced = max(left, right)
        return NotchWings(left: balanced, right: balanced)
    }
}

struct TokenIslandWindowLayout: Equatable {
    var screenFrame: NSRect
    var windowFrame: NSRect
    var anchorXInWindow: CGFloat
    var notchSize: CGSize
    var headerHeight: CGFloat
    var idleSize: CGSize
    var expandedSize: CGSize
    var revealSize: CGSize
    var hasHardwareNotch: Bool
    var description: String

    var shadowInset: CGFloat { 50 }

    /// Tallest an island may grow inside the overlay window — the window keeps
    /// `shadowInset` of slack beneath it for the drop shadow. Anything past
    /// this would be clipped by the window edge.
    var maxIslandHeight: CGFloat { max(idleSize.height, windowFrame.height - shadowInset) }

    /// The band a card cannot use: exactly the physical notch (or the virtual
    /// handler). Not a design choice and not padding — content drawn here is
    /// cut by the hardware. Sized from the notch itself, never from
    /// `headerHeight`, which Display → Tuning can move in either direction.
    var notchBandHeight: CGFloat { notchSize.height }

    /// A reveal is sized by its content: `revealSize.height` is only the floor.
    /// A fixed frame let tall approval/completion cards center themselves and
    /// spill past the window's top edge, which cut off their first row.
    func revealHeight(fitting contentHeight: CGFloat?) -> CGFloat {
        guard let contentHeight, contentHeight > 0 else { return revealSize.height }
        return min(max(contentHeight, revealSize.height), maxIslandHeight)
    }

    /// The panel hugs its sessions. `expandedSize.height` (Display → Max Panel
    /// Height) stops being a fixed size and becomes the point where the session
    /// list starts scrolling — two sessions no longer hang a 560pt slab off the
    /// notch.
    func panelHeight(fitting contentHeight: CGFloat?) -> CGFloat {
        guard let contentHeight, contentHeight > 0 else { return expandedSize.height }
        return min(max(contentHeight, min(expandedSize.height, 120)), expandedSize.height)
    }

    func visibleSize(
        for state: TokenIslandNotchState,
        pinned: Bool,
        wings: NotchWings,
        contentHeight: CGFloat? = nil
    ) -> CGSize {
        if pinned {
            return CGSize(width: expandedSize.width, height: panelHeight(fitting: contentHeight))
        }
        switch state {
        case .collapsed:
            return CGSize(width: idleSize.width + wings.total, height: idleSize.height)
        case .hoverPeek:
            return CGSize(width: idleSize.width + wings.total, height: idleSize.height + 4)
        case .expanded:
            return CGSize(width: expandedSize.width, height: panelHeight(fitting: contentHeight))
        case .error:
            return expandedSize
        case .reveal:
            return CGSize(width: revealSize.width, height: revealHeight(fitting: contentHeight))
        }
    }

    func centerOffset(for state: TokenIslandNotchState, wings: NotchWings) -> CGFloat {
        switch state {
        case .collapsed, .hoverPeek:
            wings.centerOffset
        case .expanded, .reveal, .error:
            0
        }
    }

    /// Where clicks belong to the island: its drawn bounds, nothing more. The
    /// overlay window covers the menu bar and the top of whatever is frontmost,
    /// so any padding here silently eats the user's clicks on the menu bar and
    /// on centered window toolbars.
    func islandRect(
        for state: TokenIslandNotchState,
        pinned: Bool,
        wings: NotchWings,
        contentHeight: CGFloat? = nil
    ) -> NSRect {
        let size = visibleSize(for: state, pinned: pinned, wings: wings, contentHeight: contentHeight)
        let x = anchorXInWindow + centerOffset(for: state, wings: wings) - size.width / 2
        let y = windowFrame.height - size.height
        return NSRect(x: x, y: y, width: size.width, height: size.height)
    }

    /// Where the pointer counts as "on the island". Wider than the drawn strip
    /// so hover doesn't demand pixel accuracy on a 40pt-tall target — hovering
    /// only opens the panel, so a generous margin costs the user nothing.
    func hoverRect(
        for state: TokenIslandNotchState,
        pinned: Bool,
        wings: NotchWings,
        contentHeight: CGFloat? = nil
    ) -> NSRect {
        var rect = islandRect(for: state, pinned: pinned, wings: wings, contentHeight: contentHeight)
        if !state.isExpandedLayout {
            let width = max(rect.width, notchSize.width + 140)
            rect = NSRect(x: rect.midX - width / 2, y: rect.minY, width: width, height: rect.height)
        }
        return rect.insetBy(dx: -22, dy: -20)
    }
}

extension NSScreen {
    var tokenIslandNotchSize: CGSize {
        guard safeAreaInsets.top > 0 else { return .zero }
        let leftPadding = auxiliaryTopLeftArea?.width ?? 0
        let rightPadding = auxiliaryTopRightArea?.width ?? 0
        guard leftPadding > 0, rightPadding > 0 else { return .zero }
        let width = frame.width - leftPadding - rightPadding
        guard width > 0 else { return .zero }
        return CGSize(width: width, height: safeAreaInsets.top)
    }

    var tokenIslandHeaderHeight: CGFloat {
        let notchSize = tokenIslandNotchSize
        if notchSize == .zero {
            return 38
        }
        return max(34, min(58, notchSize.height + 12))
    }

    var tokenIslandIsBuiltinDisplay: Bool {
        let key = NSDeviceDescriptionKey(rawValue: "NSScreenNumber")
        guard let id = deviceDescription[key],
              let rawID = (id as? NSNumber)?.uint32Value
        else {
            return false
        }
        return CGDisplayIsBuiltin(rawID) == 1
    }

    static var tokenIslandBuiltin: NSScreen? {
        screens.first { $0.tokenIslandIsBuiltinDisplay }
    }
}

@MainActor
struct TokenIslandScreenGeometry {
    private let shadowInset: CGFloat = 50

    /// Reveals size to their content, so the window has to have room for a tall
    /// approval card even when Max Panel Height is dialled all the way down —
    /// otherwise that slider silently truncates a reveal (and un-clicks the
    /// buttons at its bottom edge).
    func revealCeiling(screenHeight: CGFloat) -> CGFloat {
        min(520, max(200, screenHeight - 80))
    }

    func windowHeight(expandedHeight: CGFloat, screenHeight: CGFloat) -> CGFloat {
        max(expandedHeight, revealCeiling(screenHeight: screenHeight)) + shadowInset
    }

    func layout(for preferredScreen: NSScreen? = nil, settings: AppSettings = .defaults) -> TokenIslandWindowLayout? {
        guard let screen = preferredScreen ?? screenForIsland(settings: settings) else { return nil }
        return layout(
            screenFrame: screen.frame,
            hardwareNotchSize: screen.tokenIslandNotchSize,
            headerBaseHeight: screen.tokenIslandHeaderHeight,
            settings: settings
        )
    }

    /// Pure geometry. These three values are everything the layout needs from
    /// `NSScreen`, so the no-notch fallback — which no machine with a notch can
    /// ever exercise — is testable.
    func layout(
        screenFrame: NSRect,
        hardwareNotchSize: CGSize,
        headerBaseHeight: CGFloat,
        settings: AppSettings
    ) -> TokenIslandWindowLayout? {
        var notchSize = hardwareNotchSize
        let hasHardwareNotch = notchSize != .zero
        guard hasHardwareNotch || settings.enableNonNotchFallback else { return nil }
        if notchSize == .zero {
            // The virtual handler is the user's bar: its height carries the
            // Display → Tuning adjustment, since there is no hardware to match.
            notchSize = CGSize(
                width: max(96, settings.fallbackHandlerWidth),
                height: max(20, settings.fallbackHandlerHeight + CGFloat(settings.notchHeightAdjustment))
            )
        }

        // With a notch the strip has to cover the hardware; without one its
        // height is the user's "Handler height" — deriving it from the
        // no-notch header constant ignored that setting entirely.
        let headerBase = hasHardwareNotch ? headerBaseHeight : notchSize.height + 6
        let headerHeight = max(24, headerBase + (hasHardwareNotch ? CGFloat(settings.notchHeightAdjustment) : 0))
        let idleWidth = max(96, min(screenFrame.width - 80, notchSize.width + 8 + CGFloat(settings.notchWidthAdjustment)))
        let idleHeight = hasHardwareNotch
            ? max(24, min(62, headerHeight + 2))
            : max(20, min(62, notchSize.height))
        // Reference caps: Max Panel Width/Height are user-tunable (Display).
        let maxPanelWidth = CGFloat(min(max(settings.maxPanelWidth, 440), 900))
        let maxPanelHeight = CGFloat(min(max(settings.maxPanelHeight, 240), 700))
        let expandedWidth = min(maxPanelWidth, screenFrame.width - 72)
        let expandedHeight = min(maxPanelHeight, screenFrame.height - 80)
        let revealWidth = max(440, min(560, notchSize.width + 330 + CGFloat(settings.notchWidthAdjustment)))
        let revealHeight = max(120, min(170, 132 + CGFloat(settings.notchHeightAdjustment)))

        let windowHeight = windowHeight(expandedHeight: expandedHeight, screenHeight: screenFrame.height)
        let windowFrame = NSRect(
            x: screenFrame.minX,
            y: screenFrame.maxY - windowHeight,
            width: screenFrame.width,
            height: windowHeight
        )

        let anchorX = screenFrame.width / 2
        let description = hasHardwareNotch
            ? "Hardware notch, \(Int(notchSize.width))x\(Int(notchSize.height))px"
            : "Virtual top-center notch fallback"

        return TokenIslandWindowLayout(
            screenFrame: screenFrame,
            windowFrame: windowFrame,
            anchorXInWindow: anchorX,
            notchSize: notchSize,
            headerHeight: headerHeight,
            idleSize: CGSize(width: idleWidth, height: idleHeight),
            expandedSize: CGSize(width: expandedWidth, height: expandedHeight),
            revealSize: CGSize(width: revealWidth, height: revealHeight),
            hasHardwareNotch: hasHardwareNotch,
            description: description
        )
    }

    /// Honors Display → "Display" target ("builtin" | "main" | "focus"),
    /// falling back gracefully when the preferred screen is unavailable.
    private func screenForIsland(settings: AppSettings) -> NSScreen? {
        switch settings.displayTarget {
        case "main":
            // The primary display (menu-bar screen). `NSScreen.main` is the
            // screen with the KEY window — and this overlay takes key status
            // for approval shortcuts, which made "Main Display" self-pinning.
            if let primary = NSScreen.screens.first { return primary }
        case "focus":
            if let focused = screenUnderMouse() { return focused }
        default: // "builtin"
            if let builtin = NSScreen.tokenIslandBuiltin { return builtin }
        }
        // Fallback chain shared by all targets.
        return NSScreen.tokenIslandBuiltin
            ?? screenUnderMouse()
            ?? NSScreen.main
            ?? NSScreen.screens.first
    }

    private func screenUnderMouse() -> NSScreen? {
        let location = NSEvent.mouseLocation
        return NSScreen.screens.first { $0.frame.contains(location) }
    }
}
