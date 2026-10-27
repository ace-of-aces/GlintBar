import CoreGraphics

/// An item being dragged in the customization window.
struct DragSession {
    enum Source { case bar, palette }
    var item: BarItem
    var source: Source
    /// Pointer location in the window's coordinate space.
    var location: CGPoint
    /// Pointer offset from the item's centre, so the item doesn't jump under it.
    var grabOffset: CGSize
}

/// What letting go of the dragged item would do.
enum DropOutcome: Equatable {
    case insert(at: Int)
    /// Over the bar, but there's no room for it.
    case blocked
    /// A bar item dragged off the bar.
    case remove
    /// A palette item dragged off the bar.
    case cancel
}

/// An item as the customization bar draws it.
struct BarEntry: Identifiable {
    let item: BarItem
    var frame: CGRect
    var isPlaceholder = false
    /// The dragged item while it's off the bar: kept (invisibly) so its view and
    /// gesture survive.
    var isHidden = false
    var id: BarItem.ID { item.id }
    var layoutKey: String { "\(item.id)\(frame.minX)\(frame.width)" }
}

/// The customization bar's drag-and-drop rules, apart from the view: what letting go
/// would do, and how the bar looks meanwhile.
struct BarDropTarget {
    var items: [BarItem]
    /// Where the bar is, in the same coordinate space as drag locations.
    var barFrame: CGRect
    var barSize: CGSize

    func outcome(of drag: DragSession) -> DropOutcome {
        // The bar's hit area for drops; generous vertically so it's easy to aim for.
        guard barFrame.insetBy(dx: -16, dy: -40).contains(drag.location) else {
            return drag.source == .bar ? .remove : .cancel
        }
        let base = items(without: drag).map(\.kind)
        guard BarLayout.fits(base + [drag.item.kind], in: barSize.width) else { return .blocked }
        let centerX = drag.location.x - drag.grabOffset.width - barFrame.minX
        let frames = BarLayout.frames(for: base, in: barSize)
        return .insert(at: frames.firstIndex { $0.midX > centerX } ?? base.count)
    }

    /// The bar's items without the one being dragged.
    func items(without drag: DragSession) -> [BarItem] {
        items.filter { $0.id != drag.item.id }
    }

    /// The bar as it would look if `drag` ended now.
    func entries(during drag: DragSession?) -> [BarEntry] {
        var entries = items.map { BarEntry(item: $0, frame: .zero) }
        if let drag {
            let original = entries.firstIndex { $0.id == drag.item.id }
            entries.removeAll { $0.id == drag.item.id }
            if case .insert(let index) = outcome(of: drag) {
                entries.insert(BarEntry(item: drag.item, frame: .zero, isPlaceholder: true), at: index)
            } else if let original {
                entries.insert(BarEntry(item: drag.item, frame: .zero, isHidden: true), at: original)
            }
        }
        let visible = entries.filter { !$0.isHidden }
        let frames = BarLayout.frames(for: visible.map(\.item.kind), in: barSize)
        var x: CGFloat = 0
        var next = frames.makeIterator()
        for index in entries.indices {
            if entries[index].isHidden {
                entries[index].frame = CGRect(x: x, y: 0, width: 0, height: barSize.height)
            } else if let frame = next.next() {
                entries[index].frame = frame
                x = frame.maxX
            }
        }
        return entries
    }
}
