import CoreGraphics
import Foundation

/// A beam of white light comes in from the left, and a glass prism in the middle splits it
/// into a spectrum that fans out to the right.
enum PrismArt {
    /// Red, bent least, on top; violet, bent most, at the bottom.
    private static let spectrum = [
        RGB(1, 0.13, 0.1), RGB(1, 0.46, 0.04), RGB(1, 0.84, 0.1), RGB(0.32, 0.9, 0.28), RGB(0.1, 0.74, 1),
        RGB(0.25, 0.36, 1), RGB(0.56, 0.24, 1),
    ]

    private struct Geometry {
        var apex: CGPoint
        var left: CGPoint
        var right: CGPoint
        /// Where the beam enters the left face.
        var entry: CGPoint
        /// Where red and violet leave the right face.
        var exitRed: CGPoint
        var exitViolet: CGPoint
        /// Where the beam comes from, at the left end.
        var source: CGPoint
        /// Where red and violet reach the right end.
        var endRed: CGPoint
        var endViolet: CGPoint
    }

    static func draw(in context: CGContext, size: CGSize) {
        let geometry = geometry(for: size)
        Art.fadingEnds(context, size: size, fade: min(18, size.width * 0.12)) {
            drawBeam(context, geometry)
            drawSpectrum(context, geometry)
            drawInside(context, geometry)
            drawGlass(context, geometry)
        }
    }

    private static func geometry(for size: CGSize) -> Geometry {
        let height = size.height
        let prismHeight = height * 0.8
        let halfBase = prismHeight / 3.squareRoot()
        let middle = size.width / 2
        // On the Touch Bar's 2× pixel grid, so the base's half-point edge is one crisp pixel row.
        let bottom = ((height - prismHeight) / 2).rounded() + 0.25
        let apex = CGPoint(x: middle, y: bottom + prismHeight)
        let left = CGPoint(x: middle - halfBase, y: bottom)
        let right = CGPoint(x: middle + halfBase, y: bottom)
        func point(from a: CGPoint, to b: CGPoint, _ t: CGFloat) -> CGPoint {
            CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
        }
        let entry = point(from: left, to: apex, 0.5)
        let exitRed = point(from: right, to: apex, 0.5)
        let exitViolet = point(from: right, to: apex, 0.36)
        // The beam rises gently toward the prism, more steeply when there's little room.
        let source = CGPoint(x: 0, y: entry.y - min(entry.x * 0.1, height * 0.2))
        // The spectrum leans down toward the base and spreads as it goes, up to most of the bar.
        let run = size.width - exitRed.x
        let spread = min(height * 0.66, run * 0.5)
        let centerY = (exitRed.y + exitViolet.y) / 2 - min(run * 0.05, height * 0.1)
        let top = min(centerY + spread / 2, height - 1)
        let endRed = CGPoint(x: size.width, y: top)
        let endViolet = CGPoint(x: size.width, y: max(top - spread, 1))
        return Geometry(
            apex: apex, left: left, right: right, entry: entry, exitRed: exitRed, exitViolet: exitViolet,
            source: source, endRed: endRed, endViolet: endViolet)
    }

    private static func drawBeam(_ context: CGContext, _ g: Geometry) {
        let white = RGB(1, 1, 1)
        let layers: [(width: CGFloat, alpha: CGFloat)] = [(3.2, 0.1), (1.6, 0.28), (0.7, 0.95)]
        for layer in layers {
            Art.gradientLine(
                context, from: g.source, to: g.entry, width: layer.width,
                colors: [
                    white.color(alpha: 0), white.color(alpha: layer.alpha * 0.7), white.color(alpha: layer.alpha),
                ],
                locations: [0, 0.45, 1])
        }
    }

    /// The colours fanning out to the right, brightest as they leave the prism.
    private static func drawSpectrum(_ context: CGContext, _ g: Geometry) {
        let bands = 56
        func point(_ a: CGPoint, _ b: CGPoint, _ t: CGFloat) -> CGPoint {
            CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
        }
        context.saveGState()
        context.beginTransparencyLayer(auxiliaryInfo: nil)
        // A soft halo first, then the bands themselves. Each pass is drawn opaque into a
        // layer of its own and faded as a whole, so the overlapping bands leave no seams.
        let passes: [(grow: CGFloat, alpha: CGFloat)] = [(1.5, 0.22), (1, 0.9)]
        for pass in passes {
            let mid = point(g.endRed, g.endViolet, 0.5)
            let endRed = CGPoint(x: g.endRed.x, y: mid.y + (g.endRed.y - mid.y) * pass.grow)
            let endViolet = CGPoint(x: g.endViolet.x, y: mid.y + (g.endViolet.y - mid.y) * pass.grow)
            context.saveGState()
            context.setAlpha(pass.alpha)
            context.beginTransparencyLayer(auxiliaryInfo: nil)
            for band in 0..<bands {
                let t0 = CGFloat(band) / CGFloat(bands)
                let t1 = CGFloat(band + 1) / CGFloat(bands)
                let path = CGMutablePath()
                // Overlapping its neighbours a little, so no seams show between them.
                path.addLines(between: [
                    point(g.exitRed, g.exitViolet, t0 - 0.01), point(endRed, endViolet, t0 - 0.004),
                    point(endRed, endViolet, t1 + 0.004), point(g.exitRed, g.exitViolet, t1 + 0.01),
                ])
                path.closeSubpath()
                context.addPath(path)
                context.setFillColor(RGB.ramp(spectrum, (t0 + t1) / 2).color())
                context.fillPath()
            }
            context.endTransparencyLayer()
            context.restoreGState()
        }
        // Fades as it spreads.
        let start = CGPoint(x: g.exitRed.x, y: 0)
        let colors = [1, 0.75, 0.35, 0].map { CGColor(gray: 1, alpha: $0) }
        if let fade = CGGradient(colorsSpace: Art.sRGB, colors: colors as CFArray, locations: [0, 0.3, 0.75, 1]) {
            context.setBlendMode(.destinationIn)
            context.drawLinearGradient(
                fade, start: start, end: CGPoint(x: g.endRed.x, y: 0),
                options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        }
        context.endTransparencyLayer()
        context.restoreGState()
    }

    /// Inside the glass, the beam already starts to come apart.
    private static func drawInside(_ context: CGContext, _ g: Geometry) {
        let path = CGMutablePath()
        path.addLines(between: [g.entry, g.exitRed, g.exitViolet])
        path.closeSubpath()
        let mid = CGPoint(x: (g.exitRed.x + g.exitViolet.x) / 2, y: (g.exitRed.y + g.exitViolet.y) / 2)
        Art.gradientFill(
            context, path, from: g.entry, to: mid,
            colors: [RGB(1, 1, 1).color(alpha: 0.75), RGB(1, 0.96, 0.9).color(alpha: 0.4)])
        Art.glow(context, at: g.entry, radius: 3.2, color: RGB(1, 1, 1), alpha: 0.55)
        Art.glow(context, at: mid, radius: 2.6, color: RGB(1, 0.95, 0.85), alpha: 0.3)
    }

    /// The prism: clear glass with fine, bright edges and sharp corners.
    private static func drawGlass(_ context: CGContext, _ g: Geometry) {
        let path = CGMutablePath()
        path.addLines(between: [g.left, g.right, g.apex])
        path.closeSubpath()
        let base = CGPoint(x: g.apex.x, y: g.left.y)
        Art.gradientFill(
            context, path, from: g.apex, to: base,
            colors: [RGB(0.8, 0.88, 1).color(alpha: 0.2), RGB(0.8, 0.88, 1).color(alpha: 0.06)])
        context.addPath(path)
        context.setStrokeColor(RGB(0.92, 0.96, 1).color(alpha: 0.75))
        context.setLineWidth(0.5)
        // A 60° corner mitres out to twice the line width, well inside the limit.
        context.setLineJoin(.miter)
        context.setMiterLimit(4)
        context.strokePath()
    }
}
