import AppKit
import XCTest
@testable import TokenIslandKit

/// The no-notch path — external monitors and pre-2021 Macs. A machine with a
/// notch can never run it, so it is covered here through the pure geometry.
@MainActor
final class FallbackGeometryTests: XCTestCase {
    private let geometry = TokenIslandScreenGeometry()
    /// A 2560×1440 external display sitting to the right of a built-in one, so
    /// the frame origin is non-zero the way AppKit reports secondary screens.
    private let external = NSRect(x: 1512, y: 0, width: 2560, height: 1440)

    private func fallbackLayout(_ settings: AppSettings = .defaults) -> TokenIslandWindowLayout? {
        geometry.layout(
            screenFrame: external,
            hardwareNotchSize: .zero,
            headerBaseHeight: 38,
            settings: settings
        )
    }

    func testFallbackIslandExistsAndIsLabelled() throws {
        let layout = try XCTUnwrap(fallbackLayout(), "the fallback is on by default")
        XCTAssertFalse(layout.hasHardwareNotch)
        XCTAssertEqual(layout.description, "Virtual top-center notch fallback")
    }

    func testDisabledFallbackYieldsNoIsland() {
        var settings = AppSettings.defaults
        settings.enableNonNotchFallback = false
        XCTAssertNil(fallbackLayout(settings))
    }

    /// The bar used to take its height from the 38pt no-notch constant, so the
    /// "Handler height" setting did nothing.
    func testBarSizeComesFromTheHandlerSettings() throws {
        var settings = AppSettings.defaults
        settings.fallbackHandlerWidth = 170
        settings.fallbackHandlerHeight = 34
        let layout = try XCTUnwrap(fallbackLayout(settings))
        XCTAssertEqual(layout.idleSize.height, 34)
        XCTAssertEqual(layout.idleSize.width, 178)
    }

    func testNotchClearanceTracksTheBarAcrossTheTuningRange() throws {
        for adjustment in stride(from: -20.0, through: 20.0, by: 5.0) {
            var settings = AppSettings.defaults
            settings.notchHeightAdjustment = adjustment
            let layout = try XCTUnwrap(fallbackLayout(settings))
            XCTAssertGreaterThanOrEqual(
                layout.notchBandHeight,
                layout.idleSize.height,
                "card content must clear the bar (adjustment \(adjustment))"
            )
            XCTAssertLessThanOrEqual(
                layout.notchBandHeight,
                layout.idleSize.height + 4,
                "…without leaving a gap (adjustment \(adjustment))"
            )
        }
    }

    func testWindowSpansTheSecondaryScreenAndHangsFromItsTop() throws {
        let layout = try XCTUnwrap(fallbackLayout())
        XCTAssertEqual(layout.windowFrame.maxY, external.maxY)
        XCTAssertEqual(layout.windowFrame.minX, external.minX)
        XCTAssertEqual(layout.windowFrame.width, external.width)
        XCTAssertLessThanOrEqual(layout.windowFrame.height, external.height)
    }

    func testShortExternalDisplayKeepsThePanelOnScreen() throws {
        let short = geometry.layout(
            screenFrame: NSRect(x: 0, y: 0, width: 1280, height: 720),
            hardwareNotchSize: .zero,
            headerBaseHeight: 38,
            settings: .defaults
        )
        let layout = try XCTUnwrap(short)
        XCTAssertLessThanOrEqual(layout.maxIslandHeight, 720 - 24)
        XCTAssertLessThanOrEqual(layout.expandedSize.width, 1280 - 72)
        XCTAssertLessThanOrEqual(layout.windowFrame.height, 720)
    }

    /// The controller re-renders only when the layout value changes, so two
    /// displays must not compare equal.
    func testLayoutsDifferPerDisplay() throws {
        let a = try XCTUnwrap(fallbackLayout())
        let b = try XCTUnwrap(geometry.layout(
            screenFrame: NSRect(x: 0, y: 0, width: 1920, height: 1080),
            hardwareNotchSize: .zero,
            headerBaseHeight: 38,
            settings: .defaults
        ))
        XCTAssertNotEqual(a, b, "a display switch has to invalidate the rendered layout")
    }

    func testHardwareNotchPathIsUnchangedByTheFallbackWork() throws {
        let layout = try XCTUnwrap(geometry.layout(
            screenFrame: NSRect(x: 0, y: 0, width: 1512, height: 982),
            hardwareNotchSize: CGSize(width: 200, height: 32),
            headerBaseHeight: 44,
            settings: .defaults
        ))
        XCTAssertTrue(layout.hasHardwareNotch)
        XCTAssertEqual(layout.idleSize.height, 46, "strip still covers a 32pt notch")
        XCTAssertEqual(layout.notchBandHeight, 32, "the band is the notch itself, not a design margin")
    }
}
