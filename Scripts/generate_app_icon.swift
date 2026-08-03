#!/usr/bin/env swift
// Generates .build/AppIcon.icns from the crab pixel-pet bitmap.
//
// Standalone: run as `swift Scripts/generate_app_icon.swift` from the repo
// root (or anywhere — paths derive from the script's own location). The
// bitmap is duplicated inline because a script cannot import the package;
// keep it in sync with PetSpecies.crabFrames[0] and the tile drawing with
// AppIconArt.appIcon(size:).

import AppKit
import Foundation

// MARK: - Bitmap (PetSpecies.crab, frame 0; "1" body, "2"/"Y" highlight)

let crabRows = [
    "..1.....1..",
    "1.1.....1.1",
    "1.2211122.1",
    "112121212Y1",
    ".111111111.",
    "..1..1..1..",
    ".1...1...1.",
    "1....1....1"
]

let crabFrame: [[UInt8]] = crabRows.map { row in
    row.map { character in
        switch character {
        case "1": 1
        case "2", "Y": 2
        default: 0
        }
    }
}

// MARK: - Drawing (mirrors AppIconArt.appIcon)

func drawBitmap(_ frame: [[UInt8]], in rect: NSRect, body: NSColor, highlight: NSColor) {
    let rows = frame.count
    let cols = frame.first?.count ?? 1
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

func renderIconPNG(pixelSize: Int) -> Data? {
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixelSize,
        pixelsHigh: pixelSize,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else { return nil }
    rep.size = NSSize(width: pixelSize, height: pixelSize)

    NSGraphicsContext.saveGraphicsState()
    guard let context = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
    NSGraphicsContext.current = context

    let rect = NSRect(x: 0, y: 0, width: pixelSize, height: pixelSize)
    let tileRect = rect.insetBy(dx: rect.width * 0.055, dy: rect.height * 0.055)
    let radius = tileRect.width * 0.2237
    let tile = NSBezierPath(roundedRect: tileRect, xRadius: radius, yRadius: radius)
    NSColor(calibratedRed: 0.04, green: 0.05, blue: 0.08, alpha: 1).setFill()
    tile.fill()

    NSGraphicsContext.current?.saveGraphicsState()
    let glow = NSShadow()
    glow.shadowColor = NSColor(calibratedRed: 0.25, green: 0.60, blue: 1.0, alpha: 0.9)
    glow.shadowBlurRadius = tileRect.width * 0.08
    glow.set()
    drawBitmap(
        crabFrame,
        in: tileRect.insetBy(dx: tileRect.width * 0.19, dy: tileRect.height * 0.19),
        body: NSColor(calibratedRed: 0.42, green: 0.72, blue: 1.0, alpha: 1),
        highlight: NSColor(calibratedRed: 0.78, green: 0.90, blue: 1.0, alpha: 1)
    )
    NSGraphicsContext.current?.restoreGraphicsState()

    context.flushGraphics()
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])
}

// MARK: - Iconset + icns

let scriptURL = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL
let rootURL = scriptURL.deletingLastPathComponent().deletingLastPathComponent()
let buildURL = rootURL.appendingPathComponent(".build")
let iconsetURL = buildURL.appendingPathComponent("AppIcon.iconset")
let icnsURL = buildURL.appendingPathComponent("AppIcon.icns")

let fileManager = FileManager.default
do {
    try? fileManager.removeItem(at: iconsetURL)
    try fileManager.createDirectory(at: iconsetURL, withIntermediateDirectories: true)
} catch {
    FileHandle.standardError.write(Data("error: cannot create \(iconsetURL.path): \(error)\n".utf8))
    exit(1)
}

// (basePoints, scale) → icon_16x16.png … icon_512x512@2x.png (16…1024 px).
let variants: [(base: Int, scale: Int)] = [
    (16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2)
]

for variant in variants {
    let pixels = variant.base * variant.scale
    guard let png = renderIconPNG(pixelSize: pixels) else {
        FileHandle.standardError.write(Data("error: render failed at \(pixels)px\n".utf8))
        exit(1)
    }
    let suffix = variant.scale == 2 ? "@2x" : ""
    let name = "icon_\(variant.base)x\(variant.base)\(suffix).png"
    do {
        try png.write(to: iconsetURL.appendingPathComponent(name))
    } catch {
        FileHandle.standardError.write(Data("error: cannot write \(name): \(error)\n".utf8))
        exit(1)
    }
}

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconsetURL.path, "-o", icnsURL.path]
do {
    try iconutil.run()
    iconutil.waitUntilExit()
} catch {
    FileHandle.standardError.write(Data("error: iconutil launch failed: \(error)\n".utf8))
    exit(1)
}
guard iconutil.terminationStatus == 0 else {
    FileHandle.standardError.write(Data("error: iconutil exited \(iconutil.terminationStatus)\n".utf8))
    exit(Int32(iconutil.terminationStatus))
}

print("Wrote \(icnsURL.path)")
