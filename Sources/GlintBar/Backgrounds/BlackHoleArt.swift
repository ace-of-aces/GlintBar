import CoreGraphics
import Foundation

/// A black hole seen almost edge-on. Its glowing accretion disk crosses in front of it, and
/// gravity bends the light of the disk's far side into an arch over the top and a smaller
/// one underneath, around a thin ring of light at the edge of its shadow.
enum BlackHoleArt {
    /// Coolest first. The inner disk burns yellow, the outer edge a dull red.
    private static let fire = [
        RGB(0.3, 0.025, 0), RGB(0.68, 0.11, 0.01), RGB(0.93, 0.3, 0.03), RGB(1, 0.52, 0.12),
        RGB(1, 0.72, 0.34), RGB(1, 0.88, 0.64),
    ]

    static func draw(in context: CGContext, size: CGSize) {
        // r is the radius of the photon ring, the thin circle of light around the shadow, and
        // sets the scale of everything else: the arch reaches 2.35 r above the middle and
        // the underside 1.8 r below it.
        let r = min((size.height - 1) / 4.15, size.width / 10.5)
        let center = CGPoint(x: size.width / 2, y: (size.height - 4.15 * r) / 2 + 1.8 * r)
        // The disk reaches further out in wider spaces, but stays in proportion.
        let reach = min(max(size.width / 2 - 3, 3.6 * r), 12 * r)
        Art.fadingEnds(context, size: size, fade: min(14, size.width * 0.1)) {
            context.translateBy(x: center.x, y: center.y)
            drawFarSide(context, r: r, reach: reach)
            drawUnderside(context, r: r)
            drawShadow(context, r: r)
            drawNearSide(context, r: r, reach: reach)
        }
    }

    /// One streak of the far side as it appears: `lift` above the middle away from the hole,
    /// arching over it to `apex` above the middle. Light passing the hole at a distance d
    /// shows up pushed out to b, as through a lens (b² − d·b = apex·(apex − lift)), which
    /// lifts the disk right behind the hole up to `apex`. Points are relative to the middle.
    private static func lensedStreak(apex: CGFloat, lift: CGFloat, reach: CGFloat) -> [CGPoint] {
        let einstein = apex * (apex - lift)
        let samples = 140
        var points: [CGPoint] = []
        for index in -samples...samples {
            let t = CGFloat(index) / CGFloat(samples)
            // Dense near the top, where the streak turns fastest.
            let x = reach * t * t * t
            let d = hypot(x, lift)
            let b = (d + (d * d + 4 * einstein).squareRoot()) / 2
            let point = CGPoint(x: x * b / d, y: lift * b / d)
            // Right at the top the samples bunch up within a fraction of a pixel, and so many
            // tiny segments draw a bright line down the middle. Every 0.2 pt is smooth enough.
            if let last = points.last, hypot(point.x - last.x, point.y - last.y) < 0.2, index < samples {
                continue
            }
            points.append(point)
        }
        return points
    }

    /// Brightness along a streak: clumps and gaps, like the turbulent gas of the disk.
    private static func clumps(_ random: inout SeededRandom) -> (CGFloat) -> CGFloat {
        let (f1, f2) = (random.between(0.18, 0.45), random.between(0.7, 1.6))
        let (p1, p2) = (random.between(0, 6.3), random.between(0, 6.3))
        return { distance in
            0.5 + 0.5 * (0.5 + 0.5 * sin(distance * f1 + p1)) * (0.4 + 0.6 * (0.5 + 0.5 * sin(distance * f2 + p2)))
        }
    }

    /// 1 in the middle of a streak, falling smoothly to 0 at `length` from the middle.
    private static func taper(_ x: CGFloat, _ length: CGFloat) -> CGFloat {
        let u = min(abs(x) / length, 1)
        return pow(1 - u * u, 1.6)
    }

    /// The top of the disk behind the hole, bent up and over it.
    private static func drawFarSide(_ context: CGContext, r: CGFloat, reach: CGFloat) {
        var random = SeededRandom(seed: 7)
        // A soft glow underneath holds the streaks together.
        for s in stride(from: 0.06, through: 0.9, by: 0.12) {
            let points = lensedStreak(apex: r * (1.34 + 1.0 * s), lift: r * (0.04 + 0.28 * s), reach: reach)
            let length = reach * (1 - 0.3 * s)
            Art.strokeVarying(
                context, points, color: RGB.ramp(fire, 0.95 - 0.8 * s), width: r * 0.22
            ) { p, _ in 0.13 * taper(p.x, length) }
        }
        let count = 34
        for index in 0..<count {
            let s = (CGFloat(index) + random.unit()) / CGFloat(count)
            let length = reach * (1 - 0.32 * s) * random.between(0.82, 1)
            let points = lensedStreak(apex: r * (1.32 + 1.03 * s), lift: r * (0.03 + 0.3 * s), reach: length)
            let color = RGB.ramp(fire, (1 - s) * 0.85 + random.between(0, 0.15))
            let brightness = random.between(0.4, 1)
            let clumps = clumps(&random)
            Art.strokeVarying(context, points, color: color, width: random.between(0.28, 0.55)) { p, distance in
                brightness * taper(p.x, length) * clumps(distance)
            }
        }
    }

    /// The underside of the disk behind the hole, bent down and under it.
    private static func drawUnderside(_ context: CGContext, r: CGFloat) {
        var random = SeededRandom(seed: 11)
        let count = 18
        for index in 0..<count {
            let s = (CGFloat(index) + random.unit()) / CGFloat(count)
            let length = r * (1.9 + 0.7 * s)
            let points = lensedStreak(apex: r * (1.16 + 0.64 * s), lift: r * (0.05 + 0.26 * s), reach: length)
                .map { CGPoint(x: $0.x, y: -$0.y) }
            let color = RGB.ramp(fire, (1 - s) * 0.8 + random.between(0, 0.12))
            let brightness = random.between(0.35, 0.8)
            let clumps = clumps(&random)
            Art.strokeVarying(context, points, color: color, width: random.between(0.3, 0.55)) { p, distance in
                brightness * taper(p.x, length) * clumps(distance)
            }
        }
    }

    /// The shadow, rimmed by the photon ring.
    private static func drawShadow(_ context: CGContext, r: CGFloat) {
        context.setFillColor(CGColor(gray: 0, alpha: 1))
        context.fillEllipse(in: CGRect(x: -1.12 * r, y: -1.12 * r, width: 2.24 * r, height: 2.24 * r))
        let ring = CGRect(x: -r, y: -r, width: 2 * r, height: 2 * r)
        context.setStrokeColor(RGB(1, 0.6, 0.22).color(alpha: 0.16))
        context.setLineWidth(r * 0.16)
        context.strokeEllipse(in: ring)
        context.setStrokeColor(RGB(1, 0.8, 0.52).color(alpha: 0.9))
        context.setLineWidth(max(0.3, r * 0.04))
        context.strokeEllipse(in: ring)
    }

    /// The front of the disk, between us and the hole: flat, and dipping a little below the
    /// middle where it's nearest.
    private static func drawNearSide(_ context: CGContext, r: CGFloat, reach: CGFloat) {
        let dip = 0.4 * r
        // Hides the photon ring and the underside where the disk passes in front of them,
        // stepping down away from the ring so it doesn't cut into the far side's streaks.
        let blocker = CGMutablePath()
        let width = 2.5 * r
        let steps = 48
        let edge = (0...steps).map { step in -width + 2 * width * CGFloat(step) / CGFloat(steps) }
        blocker.addLines(
            between: edge.map { x in
                CGPoint(x: x, y: 0.02 * r - 0.16 * r * Art.smoothstep(0.95 * r, 1.35 * r, abs(x)))
            })
        for x in edge.reversed() {
            let u = x / width
            blocker.addLine(to: CGPoint(x: x, y: -(0.16 * r + dip) * (1 - u * u).squareRoot()))
        }
        blocker.closeSubpath()
        context.addPath(blocker)
        context.setFillColor(CGColor(gray: 0, alpha: 1))
        context.fillPath()

        var random = SeededRandom(seed: 23)
        let count = 30
        for index in 0..<count {
            let s = (CGFloat(index) + random.unit()) / CGFloat(count)
            let radius = 1.5 * r + (reach - 1.5 * r) * pow(s, 1.3)
            let depth = dip * radius / reach
            let points = (0...120).map { step in
                let angle = CGFloat.pi * CGFloat(step) / 120
                return CGPoint(x: -radius * cos(angle), y: 0.04 * r - depth * sin(angle))
            }
            let color = RGB.ramp(fire, (1 - s) * 0.9 + random.between(0, 0.1))
            let brightness = random.between(0.45, 1)
            let clumps = clumps(&random)
            Art.strokeVarying(context, points, color: color, width: random.between(0.28, 0.5)) { p, distance in
                brightness * taper(p.x, reach) * pow(taper(p.x, radius * 1.02), 0.25) * clumps(distance)
            }
        }
    }
}
