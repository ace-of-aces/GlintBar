import CoreGraphics
import Foundation

// Small Core Graphics helpers shared by the flexible-space backgrounds.

/// A colour as plain components, so it can be mixed before it becomes a `CGColor`.
struct RGB {
    var r: CGFloat
    var g: CGFloat
    var b: CGFloat

    init(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) {
        self.r = r
        self.g = g
        self.b = b
    }

    func color(alpha: CGFloat = 1) -> CGColor {
        CGColor(srgbRed: r, green: g, blue: b, alpha: min(max(alpha, 0), 1))
    }

    func mixed(with other: RGB, _ t: CGFloat) -> RGB {
        RGB(r + (other.r - r) * t, g + (other.g - g) * t, b + (other.b - b) * t)
    }

    /// The colour at `t` (0…1) along evenly spaced `stops`.
    static func ramp(_ stops: [RGB], _ t: CGFloat) -> RGB {
        let position = min(max(t, 0), 1) * CGFloat(stops.count - 1)
        let index = min(Int(position), stops.count - 2)
        return stops[index].mixed(with: stops[index + 1], position - CGFloat(index))
    }
}

/// A small, fast random number generator (SplitMix64). Seeded, so a background draws the
/// same stars and streaks every time, at every width.
struct SeededRandom: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed &* 0x9E37_79B9_7F4A_7C15 &+ 0x2545_F491_4F6C_DD1D
    }

    /// One generator per tile of a background, so tiles don't change as others come and go.
    init(_ salt: UInt64, tile: Int) {
        self.init(seed: salt &+ UInt64(bitPattern: Int64(tile)) &* 0xD6E8_FEB8_6659_FD93)
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// A number in 0..<1.
    mutating func unit() -> CGFloat {
        CGFloat(next() >> 11) / CGFloat(UInt64(1) << 53)
    }

    mutating func between(_ low: CGFloat, _ high: CGFloat) -> CGFloat {
        low + (high - low) * unit()
    }
}

enum Art {
    static let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!

    static func smoothstep(_ edge0: CGFloat, _ edge1: CGFloat, _ x: CGFloat) -> CGFloat {
        let t = min(max((x - edge0) / (edge1 - edge0), 0), 1)
        return t * t * (3 - 2 * t)
    }

    /// Draws `content` as one layer whose left and right ends fade into the black bar
    /// over `fade` points, so a background never ends in a hard edge next to a button.
    static func fadingEnds(_ context: CGContext, size: CGSize, fade: CGFloat, _ content: () -> Void) {
        context.saveGState()
        context.beginTransparencyLayer(auxiliaryInfo: nil)
        context.saveGState()
        content()
        context.restoreGState()
        let fraction = min(fade / max(size.width, 1), 0.5)
        var locations: [CGFloat] = []
        var colors: [CGColor] = []
        let steps = 8
        for step in 0...steps {
            let t = CGFloat(step) / CGFloat(steps)
            locations.append(t * fraction)
            colors.append(CGColor(gray: 1, alpha: smoothstep(0, 1, t)))
        }
        for step in (0...steps).reversed() {
            let t = CGFloat(step) / CGFloat(steps)
            locations.append(1 - t * fraction)
            colors.append(CGColor(gray: 1, alpha: smoothstep(0, 1, t)))
        }
        if let mask = CGGradient(colorsSpace: sRGB, colors: colors as CFArray, locations: locations) {
            context.setBlendMode(.destinationIn)
            context.drawLinearGradient(
                mask, start: .zero, end: CGPoint(x: size.width, y: 0),
                options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        }
        context.endTransparencyLayer()
        context.restoreGState()
    }

    /// A soft round glow: `color` at the centre, fading to nothing at `radius`.
    static func glow(_ context: CGContext, at center: CGPoint, radius: CGFloat, color: RGB, alpha: CGFloat) {
        guard radius > 0, alpha > 0,
            let gradient = CGGradient(
                colorsSpace: sRGB,
                colors: [
                    color.color(alpha: alpha), color.color(alpha: alpha * 0.42), color.color(alpha: alpha * 0.12),
                    color.color(alpha: 0),
                ] as CFArray, locations: [0, 0.3, 0.62, 1])
        else { return }
        context.drawRadialGradient(
            gradient, startCenter: center, startRadius: 0, endCenter: center, endRadius: radius, options: [])
    }

    /// A straight line `width` thick, shaded from `colors.first` at `start` to `colors.last`
    /// at `end` (evenly spaced, or at `locations`).
    static func gradientLine(
        _ context: CGContext, from start: CGPoint, to end: CGPoint, width: CGFloat, colors: [CGColor],
        locations: [CGFloat]? = nil
    ) {
        let line = CGMutablePath()
        line.move(to: start)
        line.addLine(to: end)
        gradientFill(
            context, line.copy(strokingWithWidth: width, lineCap: .butt, lineJoin: .miter, miterLimit: 10),
            from: start, to: end, colors: colors, locations: locations)
    }

    /// Fills `path` with a linear gradient running from `start` to `end`.
    static func gradientFill(
        _ context: CGContext, _ path: CGPath, from start: CGPoint, to end: CGPoint, colors: [CGColor],
        locations: [CGFloat]? = nil
    ) {
        guard let gradient = CGGradient(colorsSpace: sRGB, colors: colors as CFArray, locations: locations) else {
            return
        }
        context.saveGState()
        context.addPath(path)
        context.clip()
        context.drawLinearGradient(
            gradient, start: start, end: end, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        context.restoreGState()
    }

    /// Strokes a polyline whose opacity varies along it: `alpha` is asked for every segment.
    static func strokeVarying(
        _ context: CGContext, _ points: [CGPoint], color: RGB, width: CGFloat, alpha: (CGPoint, CGFloat) -> CGFloat
    ) {
        guard points.count > 1 else { return }
        context.setLineWidth(width)
        // Butt caps: neighbouring runs meet without overlapping into brighter dots.
        context.setLineCap(.butt)
        context.setLineJoin(.round)
        var distance: CGFloat = 0
        // Neighbouring segments of (nearly) the same opacity go out as one path, which keeps
        // the joins seamless and the number of strokes down.
        var run: [CGPoint] = [points[0]]
        var runAlpha: CGFloat = -1
        func flush() {
            if run.count > 1, runAlpha > 0.004 {
                context.setStrokeColor(color.color(alpha: runAlpha))
                context.addLines(between: run)
                context.strokePath()
            }
        }
        for index in 1..<points.count {
            let a = points[index - 1]
            let b = points[index]
            distance += hypot(b.x - a.x, b.y - a.y)
            let value = (alpha(CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2), distance) * 48).rounded() / 48
            if value != runAlpha, run.count > 1 {
                flush()
                run = [a]
            }
            runAlpha = value
            run.append(b)
        }
        flush()
    }
}
