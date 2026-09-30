import AppKit

/// BudsBar's own drawing of a pair of Galaxy Buds — stemless pebbles with the ear tip peeking
/// out underneath — used for the app icon, the panel header and the menu-bar item, so the three
/// match. Drawn here rather than taken from SF Symbols, whose licence excludes app icons.
enum Artwork {
    /// The pair lives in a 100 × 100 box, y pointing down.
    private static let box: CGFloat = 100

    private struct Bud {
        let body: CGPath
        let tip: CGPath
    }

    /// `side` is -1 for the left earbud, +1 for the right one.
    private static func bud(side: CGFloat) -> Bud {
        // Drawn pointing down, then turned so the two tips point down and towards each other.
        // Shell: a pebble wider than it is deep, with a short nozzle underneath. Tip: the silicone
        // dome on its end, wider than the nozzle — what makes it an in-ear bud and not a pebble.
        var place = CGAffineTransform(translationX: box / 2 + side * 26, y: 43)
            .rotated(by: side * 0.50)
        let wide: CGFloat = 21, deep: CGFloat = 17, nozzle: CGFloat = 11, reach: CGFloat = 10
        let pebble = CGPath(ellipseIn: CGRect(x: -wide, y: -deep, width: wide * 2, height: deep * 2),
                            transform: &place)
        let neck = CGPath(ellipseIn: CGRect(x: -nozzle, y: reach - nozzle, width: nozzle * 2, height: nozzle * 2),
                          transform: &place)
        // One outline, so the hairline gap and the shadow follow the whole shell.
        let body = pebble.union(neck)
        let tip = CGPath(ellipseIn: CGRect(x: -11, y: reach + nozzle - 3, width: 22, height: 13),
                         transform: &place)
        return Bud(body: body, tip: tip)
    }

    /// Draws the pair into `rect` of a y-down context. `gap` leaves a hairline between shell and
    /// tip, which is what keeps them apart when both have the same colour.
    static func draw(in context: CGContext, rect: CGRect, body: CGColor, tip: CGColor,
                     gap: CGFloat = 0, shadow: CGColor? = nil, only: CGFloat? = nil) {
        context.saveGState()
        context.translateBy(x: rect.minX, y: rect.minY)
        context.scaleBy(x: rect.width / box, y: rect.height / box)
        for side in [CGFloat(-1), 1] where only == nil || only == side {
            let bud = bud(side: side)
            context.addPath(bud.tip)
            context.setFillColor(tip)
            context.fillPath()
            if gap > 0 {
                context.saveGState()
                context.setBlendMode(.clear)
                context.addPath(bud.body)
                context.setLineWidth(gap * 2)
                context.strokePath()
                context.restoreGState()
            }
            context.saveGState()
            if let shadow {
                context.setShadow(offset: CGSize(width: 0, height: 1.2), blur: 3.5, color: shadow)
            }
            context.addPath(bud.body)
            context.setFillColor(body)
            context.fillPath()
            context.restoreGState()
        }
        context.restoreGState()
    }

    /// The pair as an image, `side` points square.
    static func image(side: CGFloat, body: NSColor, tip: NSColor, gap: CGFloat = 0) -> NSImage {
        NSImage(size: NSSize(width: side, height: side), flipped: true) { rect in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            draw(in: context, rect: rect, body: body.cgColor, tip: tip.cgColor, gap: gap)
            return true
        }
    }

    /// One earbud on its own, centred, for the battery gauges. `side` is -1 (left) or +1 (right).
    static func budImage(side: CGFloat, points: CGFloat, body: NSColor, tip: NSColor) -> NSImage {
        NSImage(size: NSSize(width: points, height: points), flipped: true) { rect in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            // Twice the scale of the pair, shifted so this earbud sits in the middle.
            let scale = rect.width * 2
            draw(in: context, rect: CGRect(x: rect.midX - (0.5 + side * 0.23) * scale, y: rect.midY - 0.47 * scale,
                                           width: scale, height: scale),
                 body: body.cgColor, tip: tip.cgColor, gap: 3, only: side)
            return true
        }
    }

    /// Monochrome, for the menu bar: macOS tints a template image itself.
    static func menuBarImage() -> NSImage {
        // The pair is wider than tall: a 24 × 16 image, the drawing's empty top and bottom cropped.
        let image = NSImage(size: NSSize(width: 24, height: 16), flipped: true) { _ in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            draw(in: context, rect: CGRect(x: -1, y: -4.5, width: 26, height: 26),
                 body: NSColor.black.cgColor, tip: NSColor.black.cgColor, gap: 4.5)
            return true
        }
        image.isTemplate = true
        return image
    }

    /// The app icon at 1024 × 1024: the pair on the macOS rounded square.
    static func appIcon() -> NSBitmapImageRep? {
        let canvas = 1024
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: canvas, pixelsHigh: canvas,
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
              let graphics = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = graphics
        let context = graphics.cgContext

        // The icon grid: an 824-point rounded square on the 1024 canvas, with its drop shadow.
        let square = CGRect(x: 100, y: 100, width: 824, height: 824)
        let shape = NSBezierPath(roundedRect: square, xRadius: 186, yRadius: 186)
        context.saveGState()
        context.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: NSColor(white: 0, alpha: 0.35).cgColor)
        rgb(0x2F72F2).setFill()
        shape.fill()
        context.restoreGState()

        context.saveGState()
        shape.addClip()
        NSGradient(colors: [rgb(0x5A9BFF), rgb(0x2F72F2), rgb(0x1F4FD0)])?.draw(in: square, angle: -90)
        // The pair is drawn y-down; the bitmap context is y-up.
        context.translateBy(x: 0, y: CGFloat(canvas))
        context.scaleBy(x: 1, y: -1)
        draw(in: context, rect: CGRect(x: 152, y: 172, width: 720, height: 720),
             body: rgb(0xFFFFFF).cgColor, tip: rgb(0xA9C6FF).cgColor,
             shadow: rgb(0x0A1C6B, 0.40).cgColor)
        context.restoreGState()

        NSGraphicsContext.restoreGraphicsState()
        return rep
    }

    private static func rgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
        NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
    }
}
