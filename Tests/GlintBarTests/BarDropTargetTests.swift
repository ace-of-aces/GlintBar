import CoreGraphics
import Testing
@testable import GlintBar

@MainActor
struct BarDropTargetTests {
    /// A 300 × 30 bar at (100, 100) holding two 44 pt buttons: frames 0–44 and 52–96.
    private let items = [BarItem(.mute), BarItem(.siri)]
    private var target: BarDropTarget {
        BarDropTarget(items: items, barFrame: CGRect(x: 100, y: 100, width: 300, height: 30), barSize: CGSize(width: 300, height: 30))
    }

    private func drag(_ item: BarItem, from source: DragSession.Source, toBarX x: CGFloat, y: CGFloat = 115) -> DragSession {
        DragSession(item: item, source: source, location: CGPoint(x: 100 + x, y: y), grabOffset: .zero)
    }

    @Test func insertsBeforeTheFirstItemPastThePointer() {
        let new = BarItem(.spotlight)
        #expect(target.outcome(of: drag(new, from: .palette, toBarX: 10)) == .insert(at: 0))
        #expect(target.outcome(of: drag(new, from: .palette, toBarX: 50)) == .insert(at: 1))
        #expect(target.outcome(of: drag(new, from: .palette, toBarX: 250)) == .insert(at: 2))
    }

    @Test func movingAnItemLeavesItsOldSlotOut() {
        // Without mute, siri sits at 0–44; dropping mute to its right puts it after.
        #expect(target.outcome(of: drag(items[0], from: .bar, toBarX: 60)) == .insert(at: 1))
    }

    @Test func offTheBarRemovesOrCancels() {
        #expect(target.outcome(of: drag(items[0], from: .bar, toBarX: 20, y: 300)) == .remove)
        #expect(target.outcome(of: drag(BarItem(.spotlight), from: .palette, toBarX: 20, y: 300)) == .cancel)
    }

    @Test func dropsCountJustOutsideTheBar() {
        // 40 pt of slack above and below.
        #expect(target.outcome(of: drag(BarItem(.spotlight), from: .palette, toBarX: 20, y: 65)) == .insert(at: 0))
    }

    @Test func blockedWhenItDoesntFit() {
        let full = BarDropTarget(items: items, barFrame: CGRect(x: 100, y: 100, width: 120, height: 30), barSize: CGSize(width: 120, height: 30))
        #expect(full.outcome(of: drag(BarItem(.spotlight), from: .palette, toBarX: 20)) == .blocked)
    }

    @Test func showsAPlaceholderWhereTheItemWouldLand() {
        let new = BarItem(.spotlight)
        let entries = target.entries(during: drag(new, from: .palette, toBarX: 50))
        #expect(entries.map(\.item.kind) == [.mute, .spotlight, .siri])
        #expect(entries[1].isPlaceholder)
        #expect(entries.map(\.frame.minX) == [0, 52, 104])
    }

    @Test func keepsAnItemDraggedOffInvisiblyInPlace() {
        let entries = target.entries(during: drag(items[0], from: .bar, toBarX: 20, y: 300))
        #expect(entries.map(\.item.kind) == [.mute, .siri])
        #expect(entries[0].isHidden)
        #expect(entries[0].frame.width == 0)
        #expect(entries[1].frame.minX == 0)
    }

    @Test func withoutADragTheBarIsAsSaved() {
        #expect(target.entries(during: nil).map(\.frame.minX) == [0, 52])
    }
}
