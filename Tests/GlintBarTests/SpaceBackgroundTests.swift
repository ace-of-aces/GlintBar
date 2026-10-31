import AppKit
import Testing

@testable import GlintBar

@MainActor
struct SpaceBackgroundTests {
    @Test func hiddenBelowItsMinimumWidth() {
        for background in SpaceBackground.allCases {
            #expect(background.isShown(inWidth: background.minimumWidth))
            #expect(background.isShown(inWidth: BarMetrics.width))
            #expect(!background.isShown(inWidth: background.minimumWidth - 1))
        }
    }

    @Test(arguments: SpaceBackground.allCases)
    func drawsSomethingAtEveryWidthItShows(_ background: SpaceBackground) throws {
        for width in [background.minimumWidth, 300, BarMetrics.width] {
            let pixels = try Pixels(background, width: width)
            #expect(pixels.litCount > 0, "\(background) is blank at \(width) pt")
        }
    }

    /// No hard edge next to the items on either side.
    @Test(arguments: SpaceBackground.allCases)
    func fadesOutAtBothEnds(_ background: SpaceBackground) throws {
        let pixels = try Pixels(background, width: 300)
        #expect(pixels.maxAlpha(column: 0) < 4)
        #expect(pixels.maxAlpha(column: pixels.width - 1) < 4)
    }

    /// Resizing the space reveals or hides sky at its ends; the stars in the middle stay put.
    @Test func skyStaysPutAsTheSpaceResizes() throws {
        let narrow = try Pixels(.midnightSky, width: 200)
        let wide = try Pixels(.midnightSky, width: 320)
        let middle = 80 * Pixels.scale
        let before = narrow.columns((narrow.width - middle) / 2, count: middle)
        let after = wide.columns((wide.width - middle) / 2, count: middle)
        // Give or take the gradients' dithering.
        #expect(zip(before, after).allSatisfy { abs(Int($0) - Int($1)) <= 2 })
    }

    /// The Touch Bar row gives every flexible space with a background a view of its own,
    /// keeps it while other items come and go, and hides it while the space is too narrow.
    @Test func barRowKeepsABackgroundViewPerSpace() {
        let row = Self.row()
        let left = BarItem(.flexibleSpace(.blackHole))
        let right = BarItem(.flexibleSpace(.blackHole))
        row.setLayout([left, BarItem(.mute), right, BarItem(.flexibleSpace(nil))], views: [:])
        row.layoutSubtreeIfNeeded()
        let before = Self.backgroundViews(in: row)
        #expect(before.count == 2)

        row.setLayout([BarItem(.siri), left, BarItem(.mute), right], views: [:])
        row.layoutSubtreeIfNeeded()
        #expect(Set(Self.backgroundViews(in: row).map(ObjectIdentifier.init)) == Set(before.map(ObjectIdentifier.init)))

        row.setLayout([BarItem(.flexibleSpace(.prism))], views: [:])
        row.layoutSubtreeIfNeeded()
        #expect(Self.backgroundViews(in: row).map(\.background) == [.prism])
        #expect(Self.backgroundViews(in: row).first?.alphaValue == 1)

        row.setFrameSize(NSSize(width: 80, height: BarMetrics.height))
        row.layoutSubtreeIfNeeded()
        #expect(Self.backgroundViews(in: row).first?.alphaValue == 0)
    }

    /// Giving one space the picture another one already shows leaves that other picture
    /// where it is, instead of handing it over (and sliding it across the bar).
    @Test func changingOneSpaceLeavesTheOthersInPlace() {
        let row = Self.row()
        let left = BarItem(.flexibleSpace(.blackHole))
        let right = BarItem(.flexibleSpace(.prism))
        row.setLayout([left, BarItem(.mute), right], views: [:])
        row.layoutSubtreeIfNeeded()
        let prism = Self.backgroundViews(in: row).first { $0.background == .prism }
        let prismFrame = prism?.frame

        row.setLayout([BarItem(.flexibleSpace(.prism), id: left.id), BarItem(.mute), right], views: [:])
        row.layoutSubtreeIfNeeded()
        let views = Self.backgroundViews(in: row)
        #expect(views.count == 2 && views.allSatisfy { $0.background == .prism })
        #expect(views.contains { $0 === prism })
        #expect(prism?.frame == prismFrame)
    }

    /// Removing the first of two spaces with the same picture leaves the second's alone.
    @Test func removingASpaceLeavesTheOthersInPlace() {
        let row = Self.row()
        let first = BarItem(.flexibleSpace(.blackHole))
        let second = BarItem(.flexibleSpace(.blackHole))
        let mute = BarItem(.mute)
        row.setLayout([first, mute, second], views: [:])
        row.layoutSubtreeIfNeeded()
        let secondView = Self.backgroundViews(in: row).max { $0.frame.minX < $1.frame.minX }

        row.setLayout([mute, second], views: [:])
        row.layoutSubtreeIfNeeded()
        #expect(Self.backgroundViews(in: row).map(ObjectIdentifier.init) == secondView.map { [ObjectIdentifier($0)] })
    }

    private static func row() -> MainRowView {
        MainRowView(frame: NSRect(x: 0, y: 0, width: BarMetrics.width, height: BarMetrics.height))
    }

    private static func backgroundViews(in row: MainRowView) -> [SpaceBackgroundView] {
        row.subviews.compactMap { $0 as? SpaceBackgroundView }
    }
}

/// A background rendered at 2× into plain RGBA bytes.
@MainActor
private struct Pixels {
    static let scale = 2
    let width: Int
    let height: Int
    private let bytes: [UInt8]

    struct RenderError: Error {}

    init(_ background: SpaceBackground, width points: CGFloat) throws {
        guard
            let image = background.image(
                size: CGSize(width: points, height: BarMetrics.height), scale: CGFloat(Self.scale))
        else { throw RenderError() }
        width = image.width
        height = image.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard
                let context = CGContext(
                    data: buffer.baseAddress, width: image.width, height: image.height, bitsPerComponent: 8,
                    bytesPerRow: image.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            return true
        }
        guard drawn else { throw RenderError() }
        self.bytes = bytes
    }

    /// Pixels at least faintly visible.
    var litCount: Int {
        stride(from: 3, to: bytes.count, by: 4).filter { bytes[$0] > 8 }.count
    }

    func maxAlpha(column: Int) -> UInt8 {
        (0..<height).map { bytes[($0 * width + column) * 4 + 3] }.max() ?? 0
    }

    /// `count` columns from `first`, row by row.
    func columns(_ first: Int, count: Int) -> [UInt8] {
        // Spelled out step by step: as one expression it takes some compilers too long to
        // type-check.
        var result: [UInt8] = []
        result.reserveCapacity(height * count * 4)
        for row in 0..<height {
            let start: Int = (row * width + first) * 4
            let end: Int = start + count * 4
            result.append(contentsOf: bytes[start..<end])
        }
        return result
    }
}
