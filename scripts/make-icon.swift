// Draws the app icon and writes Resources/AppIcon.icns.
//
//     swift scripts/make-icon.swift            # from the repository root
//
// Everything is drawn here (no SF Symbols: their licence does not allow them in app icons):
// a pair of earbuds inside the battery ring of the panel, on the macOS rounded square.

import AppKit

let canvas: CGFloat = 1024

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

/// One earbud seen from outside: a pebble-shaped body with the ear tip peeking out below.
/// `side` is +1 for the left one, -1 for the right one.
func drawEarbud(center: CGPoint, side: CGFloat, in context: CGContext) {
    context.saveGState()
    context.translateBy(x: center.x, y: center.y)
    context.rotate(by: -side * 0.16)

    // Ear tip: a silicone dome peeking out below the body, on the outer side.
    let tip = NSBezierPath(roundedRect: CGRect(x: -side * 30 - 48, y: -166, width: 96, height: 116),
                           xRadius: 48, yRadius: 48)
    context.setShadow(offset: CGSize(width: 0, height: -8), blur: 22, color: color(0x050B22, 0.40).cgColor)
    NSGradient(colors: [color(0xB9C8EC), color(0x93A8DC)])?.draw(in: tip, angle: -90)

    // Body.
    let body = NSBezierPath(roundedRect: CGRect(x: -86, y: -104, width: 172, height: 216), xRadius: 86, yRadius: 86)
    NSGradient(colors: [color(0xFFFFFF), color(0xDCE5F8)])?.draw(in: body, angle: -90)
    context.setShadow(offset: .zero, blur: 0, color: nil)

    // A soft shade towards the other earbud gives the shell some volume.
    context.saveGState()
    body.addClip()
    NSGradient(colors: [color(0xFFFFFF, 0), color(0xAFC0E8, 0.45)])?
        .draw(from: CGPoint(x: side * 10, y: 0), to: CGPoint(x: side * 86, y: 0), options: [])
    context.restoreGState()
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
    NSGradient(colors: [color(0x4F8BFF), color(0x2B4FD6), color(0x1A2470)])?.draw(in: square, angle: -65)
    // A soft light from the top, as on system icons.
    NSGradient(colors: [color(0xFFFFFF, 0.22), color(0xFFFFFF, 0)])?
        .draw(in: CGRect(x: 100, y: 512, width: 824, height: 412), angle: -90)

    // Battery ring: a faint track and a green arc, three quarters full, starting at 12 o'clock.
    let middle = CGPoint(x: 512, y: 512)
    let radius: CGFloat = 292
    let track = NSBezierPath()
    track.appendArc(withCenter: middle, radius: radius, startAngle: 0, endAngle: 360)
    track.lineWidth = 50
    color(0xFFFFFF, 0.16).setStroke()
    track.stroke()

    let charge = NSBezierPath()
    charge.appendArc(withCenter: middle, radius: radius, startAngle: 90, endAngle: 90 - 270, clockwise: true)
    charge.lineWidth = 50
    charge.lineCapStyle = .round
    context.setShadow(offset: .zero, blur: 30, color: color(0x63E58A, 0.55).cgColor)
    color(0x63E58A).setStroke()
    charge.stroke()
    context.setShadow(offset: .zero, blur: 0, color: nil)

    drawEarbud(center: CGPoint(x: 512 - 104, y: 548), side: 1, in: context)
    drawEarbud(center: CGPoint(x: 512 + 104, y: 548), side: -1, in: context)
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
