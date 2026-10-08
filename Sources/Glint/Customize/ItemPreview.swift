import AppKit
import SwiftUI

/// How an item looks on the Touch Bar, drawn in SwiftUI for the customization window.
/// Spacers, invisible on the real bar, get a dashed outline so they can be handled.
struct ItemPreview: View {
    let kind: BarItemKind
    let width: CGFloat

    private static let finderIcon = NSWorkspace.shared.icon(forFile: "/System/Library/CoreServices/Finder.app")

    var body: some View {
        content
            .frame(width: width, height: BarMetrics.height)
            .environment(\.colorScheme, .dark)
    }

    @ViewBuilder private var content: some View {
        switch kind {
        case .space, .flexibleSpace:
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(.white.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                .overlay {
                    if kind == .flexibleSpace, width >= 36 {
                        Image(systemName: "arrow.left.and.right")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.45))
                    }
                }
        case .clock:
            TimelineView(.periodic(from: .now, by: 15)) { context in
                Text(ClockView.text(for: context.date))
                    .font(.system(size: 15, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.white)
                    .lineLimit(1)
            }
        case .nowPlaying:
            VStack(alignment: .leading, spacing: -1) {
                Text(NowPlayingMonitor.shared.title ?? "Now Playing")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(.white)
                Text(NowPlayingMonitor.shared.artist ?? "Artist")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.65))
            }
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .frame(maxHeight: .infinity)
            .glassEffect(.regular, in: .capsule)
        case .appControls:
            Image(nsImage: Self.finderIcon)
                .resizable()
                .frame(width: 22, height: 22)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .glassEffect(.regular, in: .capsule)
        default:
            Image(systemName: kind.symbol ?? "questionmark")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .glassEffect(.regular, in: .capsule)
        }
    }
}
