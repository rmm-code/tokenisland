import SwiftUI

/// Intrinsic height of the reveal card, reported up so the island frame (and
/// the window's hit rect) can match it exactly.
struct IslandContentHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// Natural height of the expanded panel — header plus session list — so the
/// panel hugs its sessions instead of hanging a fixed slab off the notch.
/// `expandedSize.height` becomes the point where the list starts scrolling.
struct PanelContentHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
