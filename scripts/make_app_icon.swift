#!/usr/bin/env swift

import AppKit
import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let resources = root.appendingPathComponent("Sootling/App/Resources", isDirectory: true)
let iconset = resources.appendingPathComponent("AppIcon.iconset", isDirectory: true)
let preview = resources.appendingPathComponent("AppIcon-1024.png")
let icns = resources.appendingPathComponent("AppIcon.icns")

try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

let sizes: [(name: String, pixels: Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024)
]

func drawIcon(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    defer { image.unlockFocus() }

    NSGraphicsContext.current?.imageInterpolation = .high
    let rect = NSRect(x: 0, y: 0, width: size, height: size)
    NSColor.clear.setFill()
    rect.fill()

    func scale(_ value: CGFloat) -> CGFloat { value / 1024 * size }
    func oval(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ color: NSColor) {
        color.setFill()
        NSBezierPath(ovalIn: NSRect(x: scale(x), y: scale(y), width: scale(w), height: scale(h))).fill()
    }
    func rounded(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ r: CGFloat, _ color: NSColor) {
        color.setFill()
        NSBezierPath(
            roundedRect: NSRect(x: scale(x), y: scale(y), width: scale(w), height: scale(h)),
            xRadius: scale(r),
            yRadius: scale(r)
        ).fill()
    }

    let tile = NSBezierPath(
        roundedRect: NSRect(x: scale(76), y: scale(76), width: scale(872), height: scale(872)),
        xRadius: scale(210),
        yRadius: scale(210)
    )
    NSColor(red: 0.08, green: 0.10, blue: 0.09, alpha: 1).setFill()
    tile.fill()

    let glow = NSGradient(colors: [
        NSColor(red: 0.34, green: 0.95, blue: 0.55, alpha: 0.36),
        NSColor(red: 0.34, green: 0.95, blue: 0.55, alpha: 0.00)
    ])
    glow?.draw(
        in: NSBezierPath(ovalIn: NSRect(x: scale(130), y: scale(210), width: scale(760), height: scale(650))),
        relativeCenterPosition: NSPoint(x: -0.14, y: 0.12)
    )

    oval(198, 238, 628, 584, NSColor(red: 0.16, green: 0.60, blue: 0.29, alpha: 1))
    oval(170, 520, 190, 190, NSColor(red: 0.11, green: 0.42, blue: 0.21, alpha: 1))
    oval(663, 516, 176, 176, NSColor(red: 0.11, green: 0.42, blue: 0.21, alpha: 1))
    oval(422, 690, 176, 176, NSColor(red: 0.11, green: 0.42, blue: 0.21, alpha: 1))
    oval(198, 325, 126, 126, NSColor(red: 0.11, green: 0.42, blue: 0.21, alpha: 1))
    oval(708, 330, 112, 112, NSColor(red: 0.11, green: 0.42, blue: 0.21, alpha: 1))

    let shine = NSGradient(colors: [
        NSColor.white.withAlphaComponent(0.32),
        NSColor.white.withAlphaComponent(0.00)
    ])
    shine?.draw(
        in: NSBezierPath(ovalIn: NSRect(x: scale(278), y: scale(514), width: scale(250), height: scale(205))),
        relativeCenterPosition: NSPoint(x: -0.35, y: 0.35)
    )

    oval(360, 510, 104, 126, .white)
    oval(560, 510, 104, 126, .white)
    oval(397, 538, 36, 48, NSColor(red: 0.05, green: 0.07, blue: 0.06, alpha: 1))
    oval(597, 538, 36, 48, NSColor(red: 0.05, green: 0.07, blue: 0.06, alpha: 1))

    rounded(438, 402, 148, 34, 17, NSColor.white.withAlphaComponent(0.86))

    let stem = NSBezierPath()
    stem.move(to: NSPoint(x: scale(512), y: scale(812)))
    stem.curve(
        to: NSPoint(x: scale(520), y: scale(912)),
        controlPoint1: NSPoint(x: scale(497), y: scale(842)),
        controlPoint2: NSPoint(x: scale(500), y: scale(884))
    )
    stem.lineWidth = scale(18)
    stem.lineCapStyle = .round
    NSColor(red: 0.62, green: 0.95, blue: 0.55, alpha: 1).setStroke()
    stem.stroke()
    oval(452, 870, 86, 52, NSColor(red: 0.62, green: 0.95, blue: 0.55, alpha: 1))
    oval(520, 874, 92, 54, NSColor(red: 0.62, green: 0.95, blue: 0.55, alpha: 1))

    oval(650, 318, 124, 82, NSColor.black.withAlphaComponent(0.20))
    oval(708, 275, 82, 58, NSColor.black.withAlphaComponent(0.16))
    oval(764, 355, 50, 42, NSColor.black.withAlphaComponent(0.18))

    return image
}

func writePNG(_ image: NSImage, to url: URL) throws {
    guard let tiff = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff),
          let data = bitmap.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "SootlingIcon", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not render PNG"])
    }
    try data.write(to: url, options: [.atomic])
}

for item in sizes {
    let image = drawIcon(size: CGFloat(item.pixels))
    try writePNG(image, to: iconset.appendingPathComponent(item.name))
    if item.pixels == 1024 {
        try writePNG(image, to: preview)
    }
}

let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", iconset.path, "-o", icns.path]
try process.run()
process.waitUntilExit()

guard process.terminationStatus == 0 else {
    throw NSError(domain: "SootlingIcon", code: Int(process.terminationStatus), userInfo: [NSLocalizedDescriptionKey: "iconutil failed"])
}

let previewProcess = Process()
previewProcess.executableURL = URL(fileURLWithPath: "/usr/bin/sips")
previewProcess.arguments = ["-z", "1024", "1024", preview.path]
try previewProcess.run()
previewProcess.waitUntilExit()

print(icns.path)
