import AppKit

/// Renders the wide invader as the app's iconography: an 18 pt template glyph
/// for the menu bar and a black rounded-rect tile with a glowing blue invader
/// for the app icon. Original art — drawn straight from our own pixel bitmaps,
/// no bundled assets.
enum AppIconArt {
    /// 18×18 pt template image (black pixels, `isTemplate`) for the
    /// MenuBarExtra label. The system recolors it for menu-bar state.
    static func menuBarIcon() -> NSImage {
        let side: CGFloat = 18
        let image = NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            drawBitmap(
                iconFrame,
                in: rect.insetBy(dx: 0.5, dy: 0.5),
                body: .black,
                highlight: .black
            )
            return true
        }
        image.isTemplate = true
        return image
    }

    /// App-icon tile at `size` points: near-black rounded rect with the
    /// blue-tinted crab glowing at its center.
    static func appIcon(size: CGFloat) -> NSImage {
        NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            // macOS-style margin: the tile floats inside the canvas.
            let tileRect = rect.insetBy(dx: rect.width * 0.055, dy: rect.height * 0.055)
            let radius = tileRect.width * 0.2237
            let tile = NSBezierPath(roundedRect: tileRect, xRadius: radius, yRadius: radius)
            NSColor(calibratedRed: 0.04, green: 0.05, blue: 0.08, alpha: 1).setFill()
            tile.fill()

            // Glowing crab: a blue shadow behind every pixel reads as glow.
            NSGraphicsContext.current?.saveGraphicsState()
            let glow = NSShadow()
            glow.shadowColor = NSColor(calibratedRed: 0.25, green: 0.60, blue: 1.0, alpha: 0.9)
            glow.shadowBlurRadius = tileRect.width * 0.08
            glow.set()
            drawBitmap(
                iconFrame,
                in: tileRect.insetBy(dx: tileRect.width * 0.19, dy: tileRect.height * 0.19),
                body: NSColor(calibratedRed: 0.42, green: 0.72, blue: 1.0, alpha: 1),
                highlight: NSColor(calibratedRed: 0.78, green: 0.90, blue: 1.0, alpha: 1)
            )
            NSGraphicsContext.current?.restoreGraphicsState()
            return true
        }
    }

    // MARK: - Bitmap plumbing

    /// The icon owns its art rather than borrowing `PetSpecies.crab`. The pet
    /// sprite has to stay small enough to sit in a row beside the other
    /// species; the icon is a lone glyph in a square tile and wants the wide,
    /// detailed silhouette. Sharing one bitmap meant shrinking the pet also
    /// silently redrew the menu bar.
    /// Kept internal so a test can assert it stays decoupled from the pet.
    static let iconFrame: [[UInt8]] = [
        "..1.....1..",
        "1.1.....1.1",
        "1.2211122.1",
        "112121212Y1",
        ".111111111.",
        "..1..1..1..",
        ".1...1...1.",
        "1....1....1"
    ].map { row in
        row.map { character in
            switch character {
            case "1": UInt8(1)
            case "2", "Y": UInt8(2)
            default: UInt8(0)
            }
        }
    }

    /// Fills the bitmap's pixels as squares, scaled to fit and centered in
    /// `rect`. `1` = body color, `2` = highlight color.
    private static func drawBitmap(
        _ frame: [[UInt8]],
        in rect: NSRect,
        body: NSColor,
        highlight: NSColor
    ) {
        let rows = frame.count
        let cols = frame.first?.count ?? 1
        guard rows > 0, cols > 0 else { return }
        let pixel = min(rect.width / CGFloat(cols), rect.height / CGFloat(rows))
        let originX = rect.midX - pixel * CGFloat(cols) / 2
        let originY = rect.midY - pixel * CGFloat(rows) / 2
        for (rowIndex, row) in frame.enumerated() {
            for (colIndex, value) in row.enumerated() where value > 0 {
                (value == 2 ? highlight : body).setFill()
                NSRect(
                    x: originX + CGFloat(colIndex) * pixel,
                    y: originY + CGFloat(rows - 1 - rowIndex) * pixel,
                    width: pixel,
                    height: pixel
                ).fill()
            }
        }
    }
}
