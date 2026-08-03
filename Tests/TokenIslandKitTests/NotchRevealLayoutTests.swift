import SwiftUI
import XCTest
@testable import TokenIslandKit

/// Regression cover for the reveal card that used to be cut off at the top:
/// the island frame was fixed at `revealSize.height`, SwiftUI centered the
/// taller card inside it, and everything above the screen's top edge was lost.
@MainActor
final class NotchRevealLayoutTests: XCTestCase {
    /// 14" MacBook Pro geometry (1512×982pt, ~200×32pt notch).
    private var layout: TokenIslandWindowLayout {
        TokenIslandWindowLayout(
            screenFrame: NSRect(x: 0, y: 0, width: 1512, height: 982),
            windowFrame: NSRect(x: 0, y: 372, width: 1512, height: 610),
            anchorXInWindow: 756,
            notchSize: CGSize(width: 200, height: 32),
            headerHeight: 44,
            idleSize: CGSize(width: 208, height: 46),
            expandedSize: CGSize(width: 640, height: 560),
            revealSize: CGSize(width: 530, height: 132),
            hasHardwareNotch: true,
            description: "test notch"
        )
    }

    // MARK: - Sizing

    func testRevealGrowsToFitTallContent() {
        let tall = layout.revealSize.height + 90
        let size = layout.visibleSize(for: .reveal(.attention, sessionID: "s1"), pinned: false, wings: .none, contentHeight: tall)
        XCTAssertEqual(size.height, tall, "a tall approval card must size the island, not overflow it")
        XCTAssertEqual(size.width, layout.revealSize.width)
    }

    func testRevealKeepsFloorForShortContent() {
        let size = layout.visibleSize(for: .reveal(.completion, sessionID: "s1"), pinned: false, wings: .none, contentHeight: 40)
        XCTAssertEqual(size.height, layout.revealSize.height, "short cards keep the minimum reveal height")
    }

    func testRevealNeverExceedsTheOverlayWindow() {
        let size = layout.visibleSize(for: .reveal(.completion, sessionID: "s1"), pinned: false, wings: .none, contentHeight: 5_000)
        XCTAssertEqual(size.height, layout.maxIslandHeight)
        XCTAssertLessThanOrEqual(size.height, layout.windowFrame.height, "the island has to stay inside the window")
    }

    func testUnmeasuredRevealFallsBackToRevealSize() {
        let unmeasured = layout.visibleSize(for: .reveal(.completion, sessionID: "s1"), pinned: false, wings: .none, contentHeight: 0)
        XCTAssertEqual(unmeasured.height, layout.revealSize.height)
    }

    func testContentHeightDoesNotDisturbTheStrip() {
        let collapsed = layout.visibleSize(for: .collapsed, pinned: false, wings: .none, contentHeight: 400)
        XCTAssertEqual(collapsed.height, layout.idleSize.height)
        let hover = layout.visibleSize(for: .hoverPeek, pinned: false, wings: .none, contentHeight: 400)
        XCTAssertEqual(hover.height, layout.idleSize.height + 4)
        let error = layout.visibleSize(for: .error("boom"), pinned: false, wings: .none, contentHeight: 400)
        XCTAssertEqual(error.height, layout.expandedSize.height, "the error panel stays a fixed sheet")
    }

    // MARK: - Panel

    func testPanelHugsItsSessions() {
        let twoSessions: CGFloat = 210
        let size = layout.visibleSize(for: .expanded, pinned: false, wings: .none, contentHeight: twoSessions)
        XCTAssertEqual(size.height, twoSessions, "a short panel must not hang a full-height slab off the notch")
        XCTAssertEqual(size.width, layout.expandedSize.width)
        XCTAssertLessThan(size.height, layout.expandedSize.height)
    }

    func testPanelStopsGrowingAtTheMaxAndScrollsInstead() {
        let size = layout.visibleSize(for: .expanded, pinned: false, wings: .none, contentHeight: 900)
        XCTAssertEqual(size.height, layout.expandedSize.height, "Max Panel Height becomes the scroll threshold")
    }

    func testUnmeasuredPanelFallsBackToMaxHeight() {
        let size = layout.visibleSize(for: .expanded, pinned: false, wings: .none, contentHeight: 0)
        XCTAssertEqual(size.height, layout.expandedSize.height)
    }

    func testPinnedPanelHugsContentToo() {
        let size = layout.visibleSize(for: .collapsed, pinned: true, wings: .none, contentHeight: 210)
        XCTAssertEqual(size.height, 210, "pinning shows the panel, so it sizes like the panel")
    }

    func testStateMachinePicksTheMeasurementForWhatIsOnScreen() {
        let stateMachine = TokenIslandStateMachine()
        stateMachine.expand()
        stateMachine.reportPanelContentHeight(210)
        XCTAssertEqual(stateMachine.contentHeight(pinned: false), 210)

        stateMachine.collapse()
        stateMachine.showReveal(.attention, sessionID: "s1")
        stateMachine.reportRevealContentHeight(269)
        XCTAssertEqual(stateMachine.contentHeight(pinned: false), 269, "a reveal must not size itself from the panel")
        XCTAssertEqual(stateMachine.contentHeight(pinned: true), 210, "pinned always shows the panel")

        stateMachine.collapse()
        XCTAssertEqual(stateMachine.contentHeight(pinned: false), 0, "the strip is never content-sized")
    }

    // MARK: - Hit testing

    func testHitRectCoversTheWholeRevealCard() {
        let contentHeight = layout.revealSize.height + 120
        let rect = layout.islandRect(
            for: .reveal(.attention, sessionID: "s1"),
            pinned: false,
            wings: .none,
            contentHeight: contentHeight
        )
        // Window coordinates are bottom-left origin: the island hangs from the
        // window's top edge, so the card occupies [maxY - contentHeight, maxY].
        XCTAssertGreaterThanOrEqual(rect.maxY, layout.windowFrame.height, "the card starts at the top of the window")
        XCTAssertLessThanOrEqual(
            rect.minY,
            layout.windowFrame.height - contentHeight,
            "Allow/Deny buttons at the bottom of a tall card must stay clickable"
        )
    }

    /// The click target used to be inflated by 22/20pt and floored at
    /// `notchSize.width + 140`, which reached ~354×66pt of screen — the window
    /// sits over the menu bar and the top of the frontmost window, so those
    /// clicks disappeared into the overlay.
    func testCollapsedClickTargetDoesNotReachBeyondTheStrip() {
        let wings = NotchWings(left: 92, right: 92)
        let clicks = layout.islandRect(for: .collapsed, pinned: false, wings: wings)
        let expected = layout.visibleSize(for: .collapsed, pinned: false, wings: wings)
        XCTAssertEqual(clicks.height, expected.height, "clicks stop where the strip stops")
        XCTAssertEqual(clicks.width, expected.width)
        XCTAssertEqual(clicks.maxY, layout.windowFrame.height, "the strip hangs from the top of the window")

        let hover = layout.hoverRect(for: .collapsed, pinned: false, wings: wings)
        XCTAssertGreaterThan(hover.height, clicks.height, "hover keeps its generous margin")
        XCTAssertGreaterThan(hover.width, clicks.width)
    }

    // MARK: - Notch clearance

    /// Display → Tuning moves `headerHeight` (24…58); the clearance must track
    /// the hardware instead, or a shrunk header puts the session title back
    /// under the notch and a stretched one wastes the top of the card.
    func testNotchClearanceTracksTheHardwareNotThePreference() {
        var shrunkHeader = layout
        shrunkHeader.headerHeight = 24
        XCTAssertEqual(
            shrunkHeader.notchBandHeight,
            shrunkHeader.notchSize.height,
            "the band is exactly the hardware — no design margin on top of it"
        )

        var stretchedHeader = layout
        stretchedHeader.headerHeight = 58
        XCTAssertEqual(
            stretchedHeader.notchBandHeight,
            shrunkHeader.notchBandHeight,
            "the gap above the first row is the notch, not the header preference"
        )
        XCTAssertLessThanOrEqual(
            stretchedHeader.notchBandHeight,
            stretchedHeader.notchSize.height,
            "nothing above the first row except the notch itself"
        )
    }

    // MARK: - Window headroom

    func testRevealCeilingSurvivesASmallMaxPanelHeight() {
        let geometry = TokenIslandScreenGeometry()
        let screenHeight: CGFloat = 982
        // Display → Max Panel Height at its minimum must not cap reveals.
        let tightPanel = geometry.windowHeight(expandedHeight: 300, screenHeight: screenHeight)
        XCTAssertGreaterThanOrEqual(
            tightPanel - layout.shadowInset,
            geometry.revealCeiling(screenHeight: screenHeight),
            "a small panel preference must not shrink the room a reveal can grow into"
        )

        // A panel taller than the reveal ceiling still gets its own room.
        XCTAssertEqual(geometry.windowHeight(expandedHeight: 700, screenHeight: screenHeight), 750)
    }

    // MARK: - Measurement plumbing

    func testStateMachineTracksRevealHeightPerReveal() {
        let stateMachine = TokenIslandStateMachine()
        stateMachine.reportRevealContentHeight(220)
        XCTAssertEqual(stateMachine.revealContentHeight, 0, "no reveal on screen, nothing to measure")

        stateMachine.showReveal(.attention, sessionID: "s1")
        stateMachine.reportRevealContentHeight(220)
        XCTAssertEqual(stateMachine.revealContentHeight, 220)

        stateMachine.collapse()
        XCTAssertEqual(stateMachine.revealContentHeight, 0, "a stale height must not size the next reveal")
    }

    func testRevealToRevealKeepsTheMeasurementUntilTheNextOneLands() {
        let stateMachine = TokenIslandStateMachine()
        stateMachine.showReveal(.completion, sessionID: "s1")
        stateMachine.reportRevealContentHeight(220)

        stateMachine.showReveal(.attention, sessionID: "s2")
        XCTAssertEqual(
            stateMachine.revealContentHeight,
            220,
            "hold the previous size for the frame before the new card measures, so the island doesn't blink"
        )

        stateMachine.reportRevealContentHeight(269)
        XCTAssertEqual(stateMachine.revealContentHeight, 269)
    }
}
