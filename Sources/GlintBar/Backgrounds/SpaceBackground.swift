import CoreGraphics
import Foundation

/// A picture a flexible space can show instead of staying empty. Each is drawn in code for
/// the width the space has, so it fits whatever the rest of the bar leaves over.
enum SpaceBackground: String, CaseIterable, Sendable {
    case midnightSky
    case blackHole
    case prism

    var title: String {
        switch self {
        case .midnightSky: "Midnight Sky"
        case .blackHole: "Black Hole"
        case .prism: "Prism"
        }
    }

    /// An SF Symbol standing in for the picture in menus, and in the customization window
    /// where a space is too narrow to show it.
    var symbol: String {
        switch self {
        case .midnightSky: "moon.stars.fill"
        case .blackHole: "circle.and.line.horizontal.fill"
        case .prism: "triangle"
        }
    }

    /// Narrower than this the picture would be cramped, so the space shows nothing.
    var minimumWidth: CGFloat {
        switch self {
        case .midnightSky: 48
        case .blackHole: 72
        case .prism: 104
        }
    }

    /// Whether a flexible space `width` points wide shows the picture.
    func isShown(inWidth width: CGFloat) -> Bool {
        width >= minimumWidth - 0.5
    }

    /// Draws the picture filling `size` (in points, y up), on a transparent background meant
    /// to sit on the black bar.
    func draw(in context: CGContext, size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }
        switch self {
        case .midnightSky: MidnightSkyArt.draw(in: context, size: size)
        case .blackHole: BlackHoleArt.draw(in: context, size: size)
        case .prism: PrismArt.draw(in: context, size: size)
        }
    }

    /// The picture rendered at `size` for a display of `scale`. Rendered once per size: the
    /// Touch Bar and the customization window ask for the same few sizes over and over.
    @MainActor func image(size: CGSize, scale: CGFloat) -> CGImage? {
        let key = ImageKey(background: self, width: size.width, height: size.height, scale: scale)
        if let cached = Self.cache[key] { return cached }
        let pixelWidth = Int((size.width * scale).rounded(.up))
        let pixelHeight = Int((size.height * scale).rounded(.up))
        guard pixelWidth > 0, pixelHeight > 0,
            let context = CGContext(
                data: nil, width: pixelWidth, height: pixelHeight, bitsPerComponent: 8, bytesPerRow: 0,
                space: Art.sRGB,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        context.scaleBy(x: scale, y: scale)
        draw(in: context, size: size)
        guard let image = context.makeImage() else { return nil }
        // Drags in the customization window go through many widths; keep only recent ones.
        if Self.cache.count >= 48 { Self.cache.removeAll() }
        Self.cache[key] = image
        return image
    }

    private struct ImageKey: Hashable {
        var background: SpaceBackground
        var width: CGFloat
        var height: CGFloat
        var scale: CGFloat
    }

    @MainActor private static var cache: [ImageKey: CGImage] = [:]
}
