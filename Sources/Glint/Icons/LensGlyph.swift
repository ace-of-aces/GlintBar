import AppKit

/// Glint's icon outside the app icon: a glass lens on a slider track. The shapes mirror
/// `Design/Icons` (`menubar.svg`, `touchbar.svg`) point for point, with y pointing down.
enum LensGlyph {
    // MARK: - Menu bar

    /// The status item image (22 × 16 pt, template): a clear lens over the track with a
    /// glint while Glint's bar is showing, the solid resting knob while the app's own
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
        let knob = CGPoint(x: 11.8, y: 8)
        let radius: CGFloat = 5.3
        let lineWidth: CGFloat = 1.3
        let track = capsule(CGRect(x: 1, y: 7, width: 20, height: 2))
        guard glintShowing else { return [track, circle(knob, radius)] }

        let glass = circle(knob, radius - lineWidth / 2)
        return [
            track.subtracting(glass),
            swollenTrack(center: knob, halfWidth: radius - lineWidth / 2 + 0.3, edge: 0.9, middle: 1.35),
            circle(knob, radius).copy(strokingWithWidth: lineWidth, lineCap: .butt, lineJoin: .miter, miterLimit: 10),
            sparkle(CGPoint(x: 4.3, y: 3.1), radius: 2.8, waist: 0.3),
        ]
    }

    // MARK: - Touch Bar

    /// The Control Strip glyph (32 × 22 pt), drawn white on the Touch Bar.
    enum TouchBar {
        static let size = CGSize(width: 32, height: 22)
        static let knob = CGPoint(x: 18, y: 11)
        static let radius: CGFloat = 7.2
        static let rimWidth: CGFloat = 1.2
        /// The glass inside the rim.
        static let glassRadius: CGFloat = radius - 0.6
        /// Half the thickness of the track in the middle of the lens.
        static let swollen: CGFloat = 1.4
        static let star = CGPoint(x: knob.x - 4.4, y: knob.y - 4.2)

        static var track: CGPath { capsule(CGRect(x: 1.5, y: 10, width: 29, height: 2)) }
        static var fill: CGPath { capsule(CGRect(x: 1.5, y: 10, width: knob.x - 1.5, height: 2)) }
        static var glass: CGPath { circle(knob, glassRadius) }

        /// The track as the lens magnifies it.
        static var swollenTrack: CGPath {
            LensGlyph.swollenTrack(center: knob, halfWidth: glassRadius + 0.3, edge: 0.9, middle: swollen)
        }

        /// The part of the swollen track that is filled: it ends at the knob's center in a
        /// round cap, like the slider's fill layer.
        static var swollenFill: CGPath {
            let upToCap = CGPath(
                rect: CGRect(x: knob.x - glassRadius, y: 0, width: glassRadius - swollen, height: size.height),
                transform: nil)
            return swollenTrack.intersection(upToCap.union(circle(CGPoint(x: knob.x - swollen, y: knob.y), swollen)))
        }

        static var starPath: CGPath { sparkle(star, radius: 2.9, waist: 0.28) }
    }

    // MARK: - Shapes

    static func capsule(_ rect: CGRect) -> CGPath {
        CGPath(roundedRect: rect, cornerWidth: rect.height / 2, cornerHeight: rect.height / 2, transform: nil)
    }

    static func circle(_ center: CGPoint, _ radius: CGFloat) -> CGPath {
        CGPath(
            ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: 2 * radius, height: 2 * radius),
            transform: nil)
    }

    /// A four-point star with concave sides. `waist` sets how thin the arms are.
    static func sparkle(_ c: CGPoint, radius r: CGFloat, waist: CGFloat) -> CGPath {
        let w = r * waist
        let a = w * 0.22
        let path = CGMutablePath()
        path.move(to: CGPoint(x: c.x, y: c.y - r))
        path.addCurve(
            to: CGPoint(x: c.x + r, y: c.y), control1: CGPoint(x: c.x + a, y: c.y - w),
            control2: CGPoint(x: c.x + w, y: c.y - a))
        path.addCurve(
            to: CGPoint(x: c.x, y: c.y + r), control1: CGPoint(x: c.x + w, y: c.y + a),
            control2: CGPoint(x: c.x + a, y: c.y + w))
        path.addCurve(
            to: CGPoint(x: c.x - r, y: c.y), control1: CGPoint(x: c.x - a, y: c.y + w),
            control2: CGPoint(x: c.x - w, y: c.y + a))
        path.addCurve(
            to: CGPoint(x: c.x, y: c.y - r), control1: CGPoint(x: c.x - w, y: c.y - a),
            control2: CGPoint(x: c.x - a, y: c.y - w))
        path.closeSubpath()
        return path
    }

    /// A track seen through round glass: `edge` thick (half) where it meets the rim,
    /// swelling to `middle` at the center.
    static func swollenTrack(center c: CGPoint, halfWidth: CGFloat, edge: CGFloat, middle: CGFloat) -> CGPath {
        let control = 2 * middle - edge
        let path = CGMutablePath()
        path.move(to: CGPoint(x: c.x - halfWidth, y: c.y - edge))
        path.addQuadCurve(to: CGPoint(x: c.x + halfWidth, y: c.y - edge), control: CGPoint(x: c.x, y: c.y - control))
        path.addLine(to: CGPoint(x: c.x + halfWidth, y: c.y + edge))
        path.addQuadCurve(to: CGPoint(x: c.x - halfWidth, y: c.y + edge), control: CGPoint(x: c.x, y: c.y + control))
        path.closeSubpath()
        return path
    }
}
