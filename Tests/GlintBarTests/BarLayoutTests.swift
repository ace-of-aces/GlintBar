import CoreGraphics
import Testing
@testable import GlintBar

struct BarLayoutTests {
    @Test func spacersBringTheirOwnSpacing() {
        #expect(BarLayout.gap(between: .mute, and: .siri) == BarLayout.gap)
        #expect(BarLayout.gap(between: .mute, and: .space) == 0)
        #expect(BarLayout.gap(between: .flexibleSpace, and: .siri) == 0)
    }

    @Test func fixedWidthCountsItemsAndGaps() {
        // 44 + 8 + 56 + 0 + 18 + 0 + 44
        #expect(BarLayout.fixedWidth(of: [.mute, .volume, .space, .siri]) == 170)
        #expect(BarLayout.fixedWidth(of: []) == 0)
    }

    @Test func itemsSitSideBySide() {
        let frames = BarLayout.frames(for: [.mute, .volume, .space, .siri], in: CGSize(width: 1000, height: 30))
        #expect(frames.map(\.minX) == [0, 52, 108, 126])
        #expect(frames.map(\.width) == [44, 56, 18, 44])
        #expect(frames.allSatisfy { $0.height == 30 })
    }

    @Test func flexibleSpacesShareWhatIsLeft() {
        let frames = BarLayout.frames(for: [.mute, .flexibleSpace, .siri, .flexibleSpace], in: CGSize(width: 288, height: 30))
        // 288 - 88 fixed, split in two.
        #expect(frames[1].width == 100)
        #expect(frames[3].width == 100)
        #expect(frames[2].minX == 144)
        #expect(frames[3].maxX == 288)
    }

    @Test func flexibleSpacesNeverGoNegative() {
        let frames = BarLayout.frames(for: [.nowPlaying, .flexibleSpace], in: CGSize(width: 100, height: 30))
        #expect(frames[1].width == 0)
    }

    @Test func fitsAllowsHalfAPointOfRounding() {
        #expect(BarLayout.fits([.mute], in: 44))
        #expect(BarLayout.fits([.mute], in: 43.5))
        #expect(!BarLayout.fits([.mute], in: 43))
    }
}
