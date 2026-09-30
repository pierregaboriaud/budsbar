// Draws the app icon and writes Resources/AppIcon.icns.
//
//     swift scripts/make-icon.swift            # from the repository root
//
// Everything is drawn here (no SF Symbols: their licence does not allow them in app icons):
// the white pair of earbuds on blue from the panel's header, on the macOS rounded square.

import AppKit

let canvas: CGFloat = 1024

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

/// One earbud in the style of the panel's header glyph: a round head on a short stem, the ear
/// tip showing on the outer side. `side` is -1 for the left one, +1 for the right one.
func drawEarbud(centerX: CGFloat, side: CGFloat, in context: CGContext) {
    let headY: CGFloat = 600
    let shape = NSBezierPath(ovalIn: CGRect(x: centerX - 104, y: headY - 104, width: 208, height: 208))
    // The stem hangs from the inner half of the head.
    shape.append(NSBezierPath(roundedRect: CGRect(x: centerX - side * 34 - 40, y: 292, width: 80, height: 330),
                              xRadius: 40, yRadius: 40))
    shape.windingRule = .nonZero
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -10), blur: 26, color: color(0x0A1C6B, 0.45).cgColor)
    color(0xFFFFFF).setFill()
    shape.fill()
    context.restoreGState()

    // Ear tip: a tinted oval on the outer side of the head.
    context.saveGState()
    context.translateBy(x: centerX + side * 50, y: headY + 4)
    context.rotate(by: side * 0.12)
    NSGradient(colors: [color(0xA8C6FF), color(0x7FA8FA)])?
        .draw(in: NSBezierPath(ovalIn: CGRect(x: -34, y: -58, width: 68, height: 116)), angle: -90)
    context.restoreGState()
}

func drawIcon() -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(canvas), pixelsHigh: Int(canvas),
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let context = NSGraphicsContext.current!.cgContext

    // The macOS icon shape: an 824 pt rounded square on a 1024 canvas, with its drop shadow.
    let square = CGRect(x: 100, y: 100, width: 824, height: 824)
    let shape = NSBezierPath(roundedRect: square, xRadius: 186, yRadius: 186)
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: color(0x000000, 0.35).cgColor)
    color(0x1B2B6B).setFill()
    shape.fill()
    context.restoreGState()

    context.saveGState()
    shape.addClip()
    NSGradient(colors: [color(0x5A9BFF), color(0x2F72F2), color(0x1F4FD0)])?.draw(in: square, angle: -90)
    // A soft light from the top, as on system icons.
    NSGradient(colors: [color(0xFFFFFF, 0.22), color(0xFFFFFF, 0)])?
        .draw(in: CGRect(x: 100, y: 512, width: 824, height: 412), angle: -90)

    drawEarbud(centerX: 512 - 128, side: -1, in: context)
    drawEarbud(centerX: 512 + 128, side: 1, in: context)
    context.restoreGState()

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

func png(_ rep: NSBitmapImageRep, side: Int) -> Data {
    let scaled = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side,
                                  bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                  colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: scaled)
    NSGraphicsContext.current?.imageInterpolation = .high
    rep.draw(in: CGRect(x: 0, y: 0, width: side, height: side))
    NSGraphicsContext.restoreGraphicsState()
    return scaled.representation(using: .png, properties: [:])!
}

let icon = drawIcon()
let manager = FileManager.default
let iconset = manager.temporaryDirectory.appendingPathComponent("BudsBar.iconset")
try? manager.removeItem(at: iconset)
try manager.createDirectory(at: iconset, withIntermediateDirectories: true)
for points in [16, 32, 128, 256, 512] {
    try png(icon, side: points).write(to: iconset.appendingPathComponent("icon_\(points)x\(points).png"))
    try png(icon, side: points * 2).write(to: iconset.appendingPathComponent("icon_\(points)x\(points)@2x.png"))
}
try manager.createDirectory(atPath: "docs", withIntermediateDirectories: true)
try png(icon, side: 512).write(to: URL(fileURLWithPath: "docs/icon.png"))

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", "Resources/AppIcon.icns"]
try iconutil.run()
iconutil.waitUntilExit()
print(iconutil.terminationStatus == 0 ? "Wrote Resources/AppIcon.icns and docs/icon.png" : "iconutil failed")
