#!/usr/bin/env swift
// Renders the Sootling app icon (Wattson on a mossy dark squircle) at every size
// macOS needs, into an .iconset directory. Pure CoreGraphics — no asset tooling.
//
// Usage: swift scripts/make-icon.swift [output.iconset]
import AppKit
import CoreGraphics

let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "build/Sootling.iconset"

// (filename, pixel size)
let variants: [(String, Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]

func rgb(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) -> CGColor {
    CGColor(srgbRed: r, green: g, blue: b, alpha: a)
}

/// Draws the full icon in a 1024×1024 top-left design space.
func drawIcon(_ ctx: CGContext) {
    let space = CGColorSpaceCreateDeviceRGB()

    // --- squircle background ---
    let plate = CGRect(x: 100, y: 100, width: 824, height: 824)
    let platePath = CGPath(roundedRect: plate, cornerWidth: 185, cornerHeight: 185, transform: nil)
    ctx.saveGState()
    ctx.addPath(platePath)
    ctx.clip()

    if let bg = CGGradient(
        colorsSpace: space,
        colors: [rgb(0.09, 0.21, 0.16), rgb(0.03, 0.06, 0.05)] as CFArray,
        locations: [0, 1]
    ) {
        ctx.drawLinearGradient(bg, start: CGPoint(x: 512, y: 100), end: CGPoint(x: 512, y: 924), options: [])
    }
    // green aura behind the pet
    if let glow = CGGradient(
        colorsSpace: space,
        colors: [rgb(0.30, 0.85, 0.45, 0.40), rgb(0.30, 0.85, 0.45, 0)] as CFArray,
        locations: [0, 1]
    ) {
        ctx.drawRadialGradient(
            glow,
            startCenter: CGPoint(x: 512, y: 500), startRadius: 0,
            endCenter: CGPoint(x: 512, y: 500), endRadius: 380,
            options: []
        )
    }
    ctx.restoreGState()

    let bodyCenter = CGPoint(x: 512, y: 545)
    let bodyR: CGFloat = 248

    // --- ground shadow ---
    ctx.setFillColor(rgb(0, 0, 0, 0.22))
    ctx.fillEllipse(in: CGRect(x: 512 - 186, y: 846 - 40, width: 372, height: 80))

    // --- sprout (drawn behind the body crown) ---
    ctx.setFillColor(rgb(0.133, 0.773, 0.369))
    let stem = CGPath(roundedRect: CGRect(x: 505, y: 235, width: 14, height: 64), cornerWidth: 7, cornerHeight: 7, transform: nil)
    ctx.addPath(stem)
    ctx.fillPath()
    drawLeaf(ctx, center: CGPoint(x: 476, y: 226), rx: 31, ry: 20, degrees: -35)
    drawLeaf(ctx, center: CGPoint(x: 548, y: 226), rx: 31, ry: 20, degrees: 35)

    // --- crown tufts ---
    ctx.setFillColor(rgb(0.302, 0.702, 0.361))
    for (x, y, r) in [
        (352.6, 403.3, 66.4), (671.4, 412.1, 57.6), (512.0, 314.7, 53.1),
        (715.7, 571.6, 48.7), (308.3, 562.7, 48.7),
    ] {
        ctx.fillEllipse(in: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
    }

    // --- body ---
    let bodyRect = CGRect(x: bodyCenter.x - bodyR, y: bodyCenter.y - bodyR, width: bodyR * 2, height: bodyR * 2)
    ctx.saveGState()
    ctx.addEllipse(in: bodyRect)
    ctx.clip()
    if let body = CGGradient(
        colorsSpace: space,
        colors: [rgb(0.451, 0.851, 0.451), rgb(0.180, 0.620, 0.302)] as CFArray,
        locations: [0, 1]
    ) {
        ctx.drawLinearGradient(body, start: CGPoint(x: 512, y: 297), end: CGPoint(x: 512, y: 793), options: [])
    }
    // glossy highlight
    if let shine = CGGradient(
        colorsSpace: space,
        colors: [rgb(1, 1, 1, 0.42), rgb(1, 1, 1, 0)] as CFArray,
        locations: [0, 1]
    ) {
        ctx.drawRadialGradient(
            shine,
            startCenter: CGPoint(x: 438, y: 436), startRadius: 0,
            endCenter: CGPoint(x: 438, y: 436), endRadius: 300,
            options: []
        )
    }
    ctx.restoreGState()

    // --- cheeks ---
    ctx.setFillColor(rgb(0.957, 0.447, 0.714, 0.4))
    ctx.fillEllipse(in: CGRect(x: 396.9 - 22, y: 567.1 - 22, width: 44, height: 44))
    ctx.fillEllipse(in: CGRect(x: 627.1 - 22, y: 567.1 - 22, width: 44, height: 44))

    // --- eyes ---
    for (ex, px) in [(441.1, 447.7), (582.9, 589.5)] {
        ctx.setFillColor(rgb(0.96, 0.96, 0.96))
        ctx.fillEllipse(in: CGRect(x: ex - 31, y: 509.6 - 40, width: 62, height: 80))
        ctx.setFillColor(rgb(0.04, 0.04, 0.05, 0.88))
        ctx.fillEllipse(in: CGRect(x: px - 15, y: 514 - 15, width: 30, height: 30))
        ctx.setFillColor(rgb(1, 1, 1, 0.9))
        ctx.fillEllipse(in: CGRect(x: px - 8 - 5, y: 514 - 9 - 5, width: 10, height: 10))
    }

    // --- smile ---
    ctx.setStrokeColor(rgb(0.04, 0.04, 0.05, 0.55))
    ctx.setLineWidth(15)
    ctx.setLineCap(.round)
    ctx.beginPath()
    ctx.move(to: CGPoint(x: 458.9, y: 607))
    ctx.addQuadCurve(to: CGPoint(x: 565.1, y: 607), control: CGPoint(x: 512, y: 651))
    ctx.strokePath()
}

func drawLeaf(_ ctx: CGContext, center: CGPoint, rx: CGFloat, ry: CGFloat, degrees: CGFloat) {
    ctx.saveGState()
    ctx.translateBy(x: center.x, y: center.y)
    ctx.rotate(by: degrees * .pi / 180)
    ctx.setFillColor(rgb(0.133, 0.773, 0.369))
    ctx.fillEllipse(in: CGRect(x: -rx, y: -ry, width: rx * 2, height: ry * 2))
    ctx.restoreGState()
}

func render(size: Int) -> Data? {
    guard let ctx = CGContext(
        data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return nil }

    ctx.interpolationQuality = .high
    // Flip to a top-left origin, then map 1024 design units onto the pixel size.
    ctx.translateBy(x: 0, y: CGFloat(size))
    ctx.scaleBy(x: 1, y: -1)
    ctx.scaleBy(x: CGFloat(size) / 1024, y: CGFloat(size) / 1024)
    drawIcon(ctx)

    guard let image = ctx.makeImage() else { return nil }
    let rep = NSBitmapImageRep(cgImage: image)
    return rep.representation(using: .png, properties: [:])
}

let fm = FileManager.default
try? fm.createDirectory(atPath: outDir, withIntermediateDirectories: true)
for (name, size) in variants {
    guard let data = render(size: size) else {
        FileHandle.standardError.write("failed to render \(name)\n".data(using: .utf8)!)
        exit(1)
    }
    try! data.write(to: URL(fileURLWithPath: "\(outDir)/\(name).png"))
}
print("wrote \(variants.count) PNGs to \(outDir)")
