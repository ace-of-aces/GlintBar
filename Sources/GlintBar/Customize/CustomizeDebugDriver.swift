#if DEBUG
import SwiftUI

/// Drives `CustomizeView`'s drag logic from debug commands (see `BarController.debug`),
/// so drag and drop can be exercised and snapshotted without a mouse.
@MainActor
@Observable
final class CustomizeDebugDriver {
    enum Step {
        case pickUpBarItem(index: Int)
        case pickUpPaletteItem(BarItemKind)
        /// x in bar coordinates.
        case moveOverBar(x: CGFloat)
        case moveOffBar
        case drop
    }

    static let shared = CustomizeDebugDriver()
    private(set) var pending: [Step] = []
    private(set) var generation = 0

    func perform(_ step: Step) {
        pending.append(step)
        generation += 1
    }

    func takeSteps() -> [Step] {
        defer { pending = [] }
        return pending
    }
}

extension CustomizeView {
    func runDebugSteps() {
        for step in CustomizeDebugDriver.shared.takeSteps() {
            switch step {
            case .pickUpBarItem(let index):
                let entries = displayedEntries
                guard entries.indices.contains(index) else { continue }
                let center = CGPoint(x: barFrame.minX + entries[index].frame.midX, y: barFrame.midY)
                drag = DragSession(item: entries[index].item, source: .bar, location: center, grabOffset: .zero)
            case .pickUpPaletteItem(let kind):
                let frame = tileFrames[kind] ?? .zero
                drag = DragSession(
                    item: BarItem(kind), source: .palette, location: CGPoint(x: frame.midX, y: frame.midY),
                    grabOffset: .zero)
            case .moveOverBar(let x):
                drag?.location = CGPoint(x: barFrame.minX + x, y: barFrame.midY)
            case .moveOffBar:
                drag?.location = CGPoint(x: barFrame.midX, y: barFrame.maxY + 160)
            case .drop:
                finishDrag()
            }
        }
    }
}
#endif
