import AppKit
import XCTest
@testable import TokenIslandKit

final class AppIconArtTests: XCTestCase {
    func testMenuBarIconIsNonEmptyTemplate() {
        let image = AppIconArt.menuBarIcon()
        XCTAssertTrue(image.isTemplate)
        XCTAssertEqual(image.size, NSSize(width: 18, height: 18))
        XCTAssertTrue(hasVisiblePixel(image))
    }

    func testAppIconTileRendersNonEmpty() {
        let image = AppIconArt.appIcon(size: 128)
        XCTAssertEqual(image.size, NSSize(width: 128, height: 128))
        XCTAssertTrue(hasVisiblePixel(image))
    }

    /// The icon used to render `PetSpecies.crab.frames[0]`, so rebalancing the
    /// pet sprite silently redrew the user's menu bar. The two have different
    /// jobs — a lone glyph in a square tile versus one of four pets sharing a
    /// row — and must keep their own art.
    func testIconArtIsIndependentOfThePetSprite() {
        XCTAssertEqual(AppIconArt.iconFrame.count, 8)
        XCTAssertEqual(AppIconArt.iconFrame.first?.count, 11)
        XCTAssertNotEqual(
            AppIconArt.iconFrame, PetSpecies.crab.frames[0],
            "icon art must not track the pet sprite"
        )
    }

    private func hasVisiblePixel(_ image: NSImage) -> Bool {
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return false }
        for x in 0..<rep.pixelsWide {
            for y in 0..<rep.pixelsHigh {
                if let color = rep.colorAt(x: x, y: y), color.alphaComponent > 0.1 {
                    return true
                }
            }
        }
        return false
    }
}
