import AppKit

/// Glint's icon outside the app icon: a black bar in front of a bright light, with a diamond
/// of light on its rim. The shapes mirror `Design/Icons` (`menubar.svg`, `touchbar.svg`)
/// point for point, with y pointing down.
enum EclipseGlyph {
    // MARK: - Menu bar

    /// The status item image (22 × 16 pt, template): the bar inside its ring of light, with
    /// the diamond on the ring while Glint's bar is showing and without it while the app's own
    /// controls are.
    static func menuBarImage(glintShowing: Bool) -> NSImage {
        let image = NSImage(size: NSSize(width: 22, height: 16), flipped: true) { _ in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            context.setFillColor(.black)
            for path in menuBarPaths(glintShowing: glintShowing) {
                context.addPath(path)
                context.fillPath()
            }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Glint"
        return image
    }

    private static func menuBarPaths(glintShowing: Bool) -> [CGPath] {
        let ring = capsule(CGRect(x: 2.25, y: 3.75, width: 17.5, height: 8.5))
            .copy(strokingWithWidth: 1.2, lineCap: .butt, lineJoin: .miter, miterLimit: 10)
        let bar = capsule(CGRect(x: 4.8, y: 6.3, width: 12.4, height: 3.4))
        guard glintShowing else { return [ring, bar] }

        let diamond = sparkle(CGPoint(x: 18.3, y: 4.3), rx: 3.5, ry: 3.5, waist: 0.3)
        // The ring stops short of the diamond, leaving a gap around it.
        let gap = diamond.union(
            diamond.copy(strokingWithWidth: 2.4, lineCap: .butt, lineJoin: .round, miterLimit: 10))
        return [ring.subtracting(gap), bar, diamond]
    }

    // MARK: - Touch Bar

    /// The Control Strip glyph (32 × 22 pt), drawn in light on the Touch Bar.
    enum TouchBar {
        static let size = CGSize(width: 32, height: 22)
        /// The bar in front of the light.
        static let bar = CGRect(x: 2.5, y: 6, width: 24.5, height: 10.5)
        /// Where the diamond sits: on the rim, where the bar's right end starts to curve.
        static let diamond: CGPoint = {
            let r = bar.height / 2
            let angle = -50 * CGFloat.pi / 180
            return CGPoint(x: bar.maxX - r + (r + 0.2) * cos(angle), y: bar.minY + r + (r + 0.2) * sin(angle))
        }()
        static let haloRadius: CGFloat = 5.6
        /// How far the light runs along the top edge before it reaches the diamond.
        static let sweepDistance: CGFloat = 0.36 * size.width

        static var barPath: CGPath { capsule(bar) }
        /// The glow just outside the rim.
        static var glowPath: CGPath { capsule(bar.insetBy(dx: -0.6, dy: -0.6)) }

        /// The light on the top edge, before it runs toward the diamond.
        static var sweepPath: CGPath {
            let start = bar.minX + bar.height / 2
            return streak(from: start - 1, to: start + 6, peak: start + 3.5, y: bar.minY, thickness: 0.95)
        }

        static var diamondPath: CGPath { sparkle(diamond, rx: 5, ry: 4.4, waist: 0.24) }
    }

    // MARK: - Shapes

    static func capsule(_ rect: CGRect) -> CGPath {
        CGPath(roundedRect: rect, cornerWidth: rect.height / 2, cornerHeight: rect.height / 2, transform: nil)
    }

    /// A four-point star with concave sides. `waist` sets how thin the arms are.
    static func sparkle(_ c: CGPoint, rx: CGFloat, ry: CGFloat, waist: CGFloat) -> CGPath {
        let w = min(rx, ry) * waist
        let a = w * 0.22
        let path = CGMutablePath()
        path.move(to: CGPoint(x: c.x, y: c.y - ry))
        path.addCurve(
            to: CGPoint(x: c.x + rx, y: c.y), control1: CGPoint(x: c.x + a, y: c.y - w),
            control2: CGPoint(x: c.x + w, y: c.y - a))
        path.addCurve(
            to: CGPoint(x: c.x, y: c.y + ry), control1: CGPoint(x: c.x + w, y: c.y + a),
            control2: CGPoint(x: c.x + a, y: c.y + w))
        path.addCurve(
            to: CGPoint(x: c.x - rx, y: c.y), control1: CGPoint(x: c.x - a, y: c.y + w),
            control2: CGPoint(x: c.x - w, y: c.y + a))
        path.addCurve(
            to: CGPoint(x: c.x, y: c.y - ry), control1: CGPoint(x: c.x - w, y: c.y - a),
            control2: CGPoint(x: c.x - a, y: c.y - w))
        path.closeSubpath()
        return path
    }

    /// A horizontal streak: sharp at both ends, `thickness` thick (half) at `peak`.
    static func streak(from x0: CGFloat, to x1: CGFloat, peak xm: CGFloat, y: CGFloat, thickness t: CGFloat)
        -> CGPath
    {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: x0, y: y))
        path.addQuadCurve(to: CGPoint(x: xm, y: y - t), control: CGPoint(x: xm - (xm - x0) * 0.35, y: y - t))
        path.addQuadCurve(to: CGPoint(x: x1, y: y), control: CGPoint(x: xm + (x1 - xm) * 0.35, y: y - t))
        path.addQuadCurve(to: CGPoint(x: xm, y: y + t), control: CGPoint(x: xm + (x1 - xm) * 0.35, y: y + t))
        path.addQuadCurve(to: CGPoint(x: x0, y: y), control: CGPoint(x: xm - (xm - x0) * 0.35, y: y + t))
        path.closeSubpath()
        return path
    }
}
