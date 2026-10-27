import SwiftUI

// Layout helpers for the customization palette.

extension HorizontalAlignment {
    private enum PaletteTile: AlignmentID {
        static func defaultValue(in d: ViewDimensions) -> CGFloat { d[.leading] }
    }

    /// The leading edge of a section's first tile box, which its title aligns to.
    static let paletteTile = HorizontalAlignment(PaletteTile.self)
}

/// Sets the `.paletteTile` guide on a section's first tile only: an `HStack`
/// averages the guides its children set explicitly.
struct PaletteTileGuide: ViewModifier {
    let boxWidth: CGFloat?

    func body(content: Content) -> some View {
        if let boxWidth {
            content.alignmentGuide(.paletteTile) { max(0, ($0.width - boxWidth) / 2) }
        } else {
            content
        }
    }
}

/// Lays subviews out left to right, starting a new row when the next one
/// wouldn't fit the proposed width.
struct FlowLayout: Layout {
    var horizontalSpacing: CGFloat
    var verticalSpacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let frames = frames(for: subviews, width: proposal.width ?? .infinity)
        let union = frames.reduce(CGRect.zero) { $0.union($1) }
        return CGSize(width: union.maxX, height: union.maxY)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for (subview, frame) in zip(subviews, frames(for: subviews, width: bounds.width)) {
            subview.place(
                at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                proposal: ProposedViewSize(frame.size))
        }
    }

    private func frames(for subviews: Subviews, width: CGFloat) -> [CGRect] {
        var frames: [CGRect] = []
        var origin = CGPoint.zero
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if origin.x > 0, origin.x + size.width > width {
                origin = CGPoint(x: 0, y: origin.y + rowHeight + verticalSpacing)
                rowHeight = 0
            }
            frames.append(CGRect(origin: origin, size: size))
            origin.x += size.width + horizontalSpacing
            rowHeight = max(rowHeight, size.height)
        }
        return frames
    }
}
