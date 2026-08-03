import SwiftUI

@MainActor
final class TokenIslandHostingView<Content: View>: NSHostingView<Content> {
    var interactiveRectProvider: (() -> NSRect?)?
    var hoverHandler: ((Bool) -> Void)?
    private var isHoveringIsland = false

    /// Overlay windows are never key, so mouse-moved events only arrive via
    /// an always-active tracking area — without this, hover fires only
    /// sporadically (hitTest side effects) and the notch feels dead.
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        ))
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let rect = interactiveRectProvider?(), rect.contains(point) else {
            return nil
        }
        return super.hitTest(point)
    }

    override func mouseEntered(with event: NSEvent) {
        updateHover(pointInside: isPointInIsland(event))
        super.mouseEntered(with: event)
    }

    override func mouseMoved(with event: NSEvent) {
        updateHover(pointInside: isPointInIsland(event))
        super.mouseMoved(with: event)
    }

    override func mouseExited(with event: NSEvent) {
        updateHover(pointInside: false)
        super.mouseExited(with: event)
    }

    private func isPointInIsland(_ event: NSEvent) -> Bool {
        guard let rect = interactiveRectProvider?() else { return false }
        return rect.contains(convert(event.locationInWindow, from: nil))
    }

    private func updateHover(pointInside: Bool) {
        guard pointInside != isHoveringIsland else { return }
        isHoveringIsland = pointInside
        hoverHandler?(pointInside)
    }
}
