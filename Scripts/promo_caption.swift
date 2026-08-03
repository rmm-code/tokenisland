#!/usr/bin/env swift
// Renders one promo caption to a transparent PNG for ffmpeg to overlay.
//
// The Homebrew ffmpeg on this machine is built without freetype/libass, so
// `drawtext` and `subtitles` are unavailable — captions are composited as
// images instead. Rendering here via AppKit also gets us real SF Pro with
// proper kerning, which drawtext would not.
//
//   swift Scripts/promo_caption.swift --text "4 AI agents. One notch." \
//     --out /tmp/cap.png --width 1920 --size 54
//
// Prints the rendered pixel height to stdout so the caller can position it.
import AppKit

func arg(_ name: String, default fallback: String? = nil) -> String {
    let args = CommandLine.arguments
    if let i = args.firstIndex(of: "--\(name)"), i + 1 < args.count { return args[i + 1] }
    guard let fallback else {
        FileHandle.standardError.write("missing required --\(name)\n".data(using: .utf8)!)
        exit(1)
    }
    return fallback
}

let text = arg("text")
let outPath = arg("out")
let width = CGFloat(Double(arg("width", default: "1920"))!)
let fontSize = CGFloat(Double(arg("size", default: "54"))!)
// Horizontal room the pill may occupy, as a fraction of canvas width. Keeps
// long captions off the edges on 9:16 without shrinking short ones.
let maxFraction = CGFloat(Double(arg("maxfraction", default: "0.86"))!)

let padX = fontSize * 0.72
let padY = fontSize * 0.42
let maxTextWidth = width * maxFraction - padX * 2

let style = NSMutableParagraphStyle()
style.alignment = .center
style.lineBreakMode = .byWordWrapping
style.lineHeightMultiple = 1.12

let attributes: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: fontSize, weight: .semibold),
    .foregroundColor: NSColor.white,
    .paragraphStyle: style,
    .kern: fontSize * -0.012
]

let attributed = NSAttributedString(string: text, attributes: attributes)
let textBounds = attributed.boundingRect(
    with: NSSize(width: maxTextWidth, height: .greatestFiniteMagnitude),
    options: [.usesLineFragmentOrigin, .usesFontLeading]
)

let textW = ceil(textBounds.width)
let textH = ceil(textBounds.height)
let pillW = min(width, textW + padX * 2)
let pillH = textH + padY * 2
// Even canvas dimensions — libx264 with yuv420p rejects odd sizes.
let canvasH = Int(ceil(pillH / 2) * 2)
let canvasW = Int(ceil(width / 2) * 2)

// Drawn into an explicitly-sized bitmap rather than via NSImage.lockFocus:
// on a Retina display lockFocus renders at the 2x backing scale, which would
// silently double the PNG's pixel size and break the overlay positioning.
guard let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: canvasW,
    pixelsHigh: canvasH,
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .calibratedRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
) else {
    FileHandle.standardError.write("failed to allocate bitmap\n".data(using: .utf8)!)
    exit(1)
}
rep.size = NSSize(width: canvasW, height: canvasH)

guard let context = NSGraphicsContext(bitmapImageRep: rep) else { exit(1) }
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = context
context.imageInterpolation = .high

let pillRect = NSRect(
    x: (CGFloat(canvasW) - pillW) / 2,
    y: (CGFloat(canvasH) - pillH) / 2,
    width: pillW,
    height: pillH
)
let pill = NSBezierPath(roundedRect: pillRect, xRadius: pillH * 0.32, yRadius: pillH * 0.32)
NSColor(calibratedWhite: 0.04, alpha: 0.78).setFill()
pill.fill()
NSColor(calibratedWhite: 1.0, alpha: 0.10).setStroke()
pill.lineWidth = 1.5
pill.stroke()

attributed.draw(
    with: NSRect(
        x: pillRect.minX + padX,
        y: pillRect.minY + padY,
        width: pillW - padX * 2,
        height: textH
    ),
    options: [.usesLineFragmentOrigin, .usesFontLeading]
)
NSGraphicsContext.restoreGraphicsState()

guard let png = rep.representation(using: .png, properties: [:]) else {
    FileHandle.standardError.write("failed to encode PNG\n".data(using: .utf8)!)
    exit(1)
}
try png.write(to: URL(fileURLWithPath: outPath))
print(canvasH)
