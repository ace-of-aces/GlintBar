import CoreGraphics
import Foundation

/// A clear night sky, black as the bar: the faint band of the Milky Way winding along it
/// through a field of stars, a few of them bright enough to sparkle.
enum MidnightSkyArt {
    /// Stars are scattered tile by tile, counted out from the middle, so they stay where they
    /// are as the space grows or shrinks around them.
    private static let tileWidth: CGFloat = 48

    /// Mostly white, with only a hint of the stars' warmer and cooler colours.
    private static let starColors = [
        RGB(1, 1, 1), RGB(1, 1, 1), RGB(0.94, 0.96, 1), RGB(1, 0.95, 0.88), RGB(1, 0.89, 0.78),
    ]

    static func draw(in context: CGContext, size: CGSize) {
        let middle = size.width / 2
        let tiles = Int((-middle / tileWidth).rounded(.down))...Int((middle / tileWidth).rounded(.down))
        Art.fadingEnds(context, size: size, fade: min(26, size.width * 0.2)) {
            context.translateBy(x: middle, y: 0)
            for tile in tiles { drawMilkyWay(context, tile: tile, height: size.height) }
            for tile in tiles { drawStars(context, tile: tile, height: size.height) }
        }
    }

    /// Where the Milky Way runs, `x` from the middle: a slow wave along the bar.
    private static func bandY(_ x: CGFloat, height: CGFloat) -> CGFloat {
        height * (0.5 + 0.2 * sin(x / 95 + 0.9) + 0.07 * sin(x / 31 + 2.2))
    }

    private static func drawMilkyWay(_ context: CGContext, tile: Int, height: CGFloat) {
        var random = SeededRandom(101, tile: tile)
        let x0 = CGFloat(tile) * tileWidth
        // Wisps of faint, neutral starlight, then a brighter core.
        for _ in 0..<12 {
            let x = x0 + random.unit() * tileWidth
            let y = bandY(x, height: height) + (random.unit() - 0.5) * height * 0.42
            let color = RGB(0.85, 0.85, 0.85).mixed(with: RGB(0.95, 0.91, 0.85), random.unit())
            Art.glow(context, at: CGPoint(x: x, y: y), radius: random.between(5, 11), color: color, alpha: 0.07)
        }
        for _ in 0..<8 {
            let x = x0 + random.unit() * tileWidth
            let y = bandY(x, height: height) + (random.unit() - 0.5) * height * 0.16
            Art.glow(
                context, at: CGPoint(x: x, y: y), radius: random.between(3, 6.5), color: RGB(0.96, 0.94, 0.9),
                alpha: 0.085)
        }
        // Dark dust lanes along it.
        for _ in 0..<3 {
            let x = x0 + random.unit() * tileWidth
            let y = bandY(x, height: height) + (random.unit() - 0.5) * height * 0.16
            Art.glow(
                context, at: CGPoint(x: x, y: y), radius: random.between(2.5, 5), color: RGB(0, 0, 0), alpha: 0.55)
        }
    }

    private static func drawStars(_ context: CGContext, tile: Int, height: CGFloat) {
        var random = SeededRandom(202, tile: tile)
        let x0 = CGFloat(tile) * tileWidth
        func color() -> RGB { starColors[Int(random.unit() * CGFloat(starColors.count))] }
        func dot(_ x: CGFloat, _ y: CGFloat, radius: CGFloat, color: RGB, alpha: CGFloat) {
            context.setFillColor(color.color(alpha: alpha))
            context.fillEllipse(in: CGRect(x: x - radius, y: y - radius, width: 2 * radius, height: 2 * radius))
        }
        // The faint multitude, crowding toward the Milky Way.
        for index in 0..<40 {
            let x = x0 + random.unit() * tileWidth
            let y =
                index < 26
                ? random.unit() * height
                : bandY(x, height: height) + (random.unit() - 0.5) * height * 0.5
            dot(x, y, radius: random.between(0.2, 0.4), color: color(), alpha: 0.2 + 0.6 * pow(random.unit(), 1.6))
        }
        for _ in 0..<4 {
            let x = x0 + random.unit() * tileWidth
            let y = random.between(1, height - 1)
            let tint = color()
            Art.glow(context, at: CGPoint(x: x, y: y), radius: 1.6, color: tint, alpha: 0.25)
            dot(x, y, radius: random.between(0.42, 0.62), color: tint, alpha: random.between(0.75, 1))
        }
        // Now and then, one that sparkles.
        if random.unit() < 0.5 {
            let x = x0 + random.unit() * tileWidth
            let y = random.between(height * 0.2, height * 0.8)
            let tint = color().mixed(with: RGB(1, 1, 1), 0.5)
            drawSparkle(context, at: CGPoint(x: x, y: y), size: random.between(3.2, 5), color: tint)
        }
    }

    /// A bright star with a soft halo and four thin rays.
    private static func drawSparkle(_ context: CGContext, at point: CGPoint, size: CGFloat, color: RGB) {
        Art.glow(context, at: point, radius: size * 0.95, color: color, alpha: 0.4)
        let rays: [(CGFloat, CGFloat)] = [(1, 0), (-1, 0), (0, 1), (0, -1)]
        for (dx, dy) in rays {
            let length = size * (dx == 0 ? 0.8 : 1.15)
            let end = CGPoint(x: point.x + dx * length, y: point.y + dy * length)
            Art.gradientLine(
                context, from: point, to: end, width: 0.34, colors: [color.color(alpha: 0.9), color.color(alpha: 0)])
        }
        context.setFillColor(RGB(1, 1, 1).color())
        context.fillEllipse(in: CGRect(x: point.x - 0.6, y: point.y - 0.6, width: 1.2, height: 1.2))
    }
}
