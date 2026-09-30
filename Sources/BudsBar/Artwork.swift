import AppKit

/// BudsBar's own drawing of a pair of Galaxy Buds, after the way they sit in their case: two
/// glossy eggs leaning towards each other, narrow ends down, each with its silicone ear tip
/// showing underneath on the outer side. Used for the app icon, the panel and the menu-bar item,
/// so the three match. Drawn here rather than taken from SF Symbols, whose licence excludes app
/// icons.
enum Artwork {
    /// The pair lives in a 100 × 100 box, y pointing down.
    private static let box: CGFloat = 100

    private struct Bud {
        let body: CGPath
        let tip: CGPath
        /// From the earbud's own frame (origin at the middle of its wide end) to the box.
        let place: CGAffineTransform
    }

    /// `side` is -1 for the left earbud, +1 for the right one.
    private static func bud(side: CGFloat) -> Bud {
        var place = CGAffineTransform(translationX: box / 2 + side * 20.5, y: 40)
            .rotated(by: side * 0.46)
        // An egg: the hull of a large circle and a smaller one further down.
        let wide: CGFloat = 18, narrow: CGFloat = 12, reach: CGFloat = 13
        let lean = asin((wide - narrow) / reach)
        let body = CGMutablePath()
        body.move(to: CGPoint(x: -wide * cos(lean), y: wide * sin(lean)), transform: place)
        body.addArc(center: .zero, radius: wide, startAngle: .pi - lean, endAngle: lean,
                    clockwise: false, transform: place)
        body.addArc(center: CGPoint(x: 0, y: reach), radius: narrow, startAngle: lean, endAngle: .pi - lean,
                    clockwise: false, transform: place)
        body.closeSubpath()
        // The ear tip: a dome tucked under the narrow end, on the outer side.
        let tip = CGPath(ellipseIn: CGRect(x: side * 15 - 10.5, y: 8, width: 21, height: 17), transform: &place)
        return Bud(body: body, tip: tip, place: place)
    }

    /// Draws the pair into `rect` of a y-down context. `gap` leaves a hairline between shell and
    /// tip, which is what keeps them apart when both have the same colour. `gloss` shades the
    /// shell towards that colour and adds the highlight of the real thing.
    static func draw(in context: CGContext, rect: CGRect, body: CGColor, tip: CGColor,
                     gap: CGFloat = 0, shadow: CGColor? = nil, gloss: CGColor? = nil, only: CGFloat? = nil) {
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
                context.setShadow(offset: CGSize(width: 0, height: 1.6), blur: 4, color: shadow)
            }
            context.addPath(bud.body)
            context.setFillColor(body)
            context.fillPath()
            context.restoreGState()

            guard let gloss, let space = CGColorSpace(name: CGColorSpace.sRGB),
                  let shade = CGGradient(colorsSpace: space, colors: [body, body, gloss] as CFArray,
                                         locations: [0, 0.35, 1]) else { continue }
            context.saveGState()
            context.addPath(bud.body)
            context.clip()
            // Light from the upper outer side: the shell darkens towards the lower inner edge.
            context.drawRadialGradient(shade, startCenter: CGPoint(x: side * 7, y: -8).applying(bud.place),
                                       startRadius: 0, endCenter: CGPoint(x: side * 2, y: 0).applying(bud.place),
                                       endRadius: 34, options: [.drawsAfterEndLocation])
            context.restoreGState()
            // Specular highlight, on the side facing the other earbud.
            context.saveGState()
            context.concatenate(bud.place)
            context.setFillColor(CGColor(gray: 1, alpha: 0.95))
            context.addPath(CGPath(roundedRect: CGRect(x: -side * 8 - 2.2, y: -4.5, width: 4.4, height: 3.6),
                                   cornerWidth: 1, cornerHeight: 1, transform: nil))
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
            draw(in: context, rect: CGRect(x: rect.midX - (0.5 + side * 0.205) * scale, y: rect.midY - 0.47 * scale,
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

        // The icon grid's 824-point rounded square is the case itself, seen from above with the
        // lid off: a white shell, the coloured tray inside, the two earbuds and the status light.
        let square = CGRect(x: 100, y: 100, width: 824, height: 824)
        let shell = NSBezierPath(roundedRect: square, xRadius: 186, yRadius: 186)
        context.saveGState()
        context.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: NSColor(white: 0, alpha: 0.35).cgColor)
        rgb(0xF4F6FA).setFill()
        shell.fill()
        context.restoreGState()
        NSGradient(colors: [rgb(0xFFFFFF), rgb(0xDDE3EE)])?.draw(in: shell, angle: -90)

        let trayRect = square.insetBy(dx: 52, dy: 52)
        let tray = NSBezierPath(roundedRect: trayRect, xRadius: 140, yRadius: 140)
        context.saveGState()
        tray.addClip()
        NSGradient(colors: [rgb(0x4C8DFB), rgb(0x2B62DE)])?.draw(in: trayRect, angle: -90)
        // The rim's shadow falling into the tray.
        context.setShadow(offset: CGSize(width: 0, height: -14), blur: 36, color: rgb(0x0B1F66, 0.55).cgColor)
        let rim = NSBezierPath(rect: trayRect.insetBy(dx: -60, dy: -60))
        rim.append(tray.reversed)
        rgb(0x0B1F66).setFill()
        rim.fill()
        context.restoreGState()

        context.saveGState()
        tray.addClip()
        // The pair is drawn y-down; the bitmap context is y-up.
        context.translateBy(x: 0, y: CGFloat(canvas))
        context.scaleBy(x: 1, y: -1)
        draw(in: context, rect: CGRect(x: 512 - 330, y: 512 - 292, width: 660, height: 660),
             body: rgb(0xFFFFFF).cgColor, tip: rgb(0x9DB4E6).cgColor,
             shadow: rgb(0x071A5C, 0.55).cgColor, gloss: rgb(0xC3D0EC).cgColor)
        // Status light, between the two narrow ends.
        context.setShadow(offset: .zero, blur: 18, color: rgb(0x6CFF9A, 0.9).cgColor)
        context.setFillColor(rgb(0x6CF59A).cgColor)
        context.fillEllipse(in: CGRect(x: 512 - 11, y: 716, width: 22, height: 22))
        context.restoreGState()

        NSGraphicsContext.restoreGraphicsState()
        return rep
    }

    private static func rgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
        NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
    }
}
