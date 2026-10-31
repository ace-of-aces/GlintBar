import AppKit
import SwiftUI

/// How an item looks on the Touch Bar, drawn in SwiftUI for the customization window.
/// Spacers, invisible on the real bar, get a dashed outline so they can be handled.
struct ItemPreview: View {
    let kind: BarItemKind
    let width: CGFloat
    /// Brightens a spacer's outline, and outlines a flexible space showing a background:
    /// it's under the pointer, or its background is being chosen.
    var isHighlighted = false

    private static let finderIcon = NSWorkspace.shared.icon(forFile: "/System/Library/CoreServices/Finder.app")

    var body: some View {
        content
            .frame(width: width, height: BarMetrics.height)
            .environment(\.colorScheme, .dark)
    }

    @ViewBuilder private var content: some View {
        switch kind {
        case .flexibleSpace(let background?) where background.isShown(inWidth: width):
            SpaceBackgroundImage(background: background, width: width)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                // Rendered for the final width, so clipped while the frame animates there.
                .clipped()
                .overlay {
                    if isHighlighted { spacerOutline }
                }
        case .space, .flexibleSpace:
            spacerOutline
                .overlay {
                    if kind.isFlexibleSpace, width >= 36 {
                        // Too narrow for its background, a space shows which one it would show.
                        Image(systemName: kind.background?.symbol ?? "arrow.left.and.right")
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
        case .systemResources:
            // Sampled while the customization window is open.
            ResourceMetersPreview(usage: SystemResources.shared.usage)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .battery:
            // Battery has no SwiftUI observation; a slow tick is plenty for a preview.
            TimelineView(.periodic(from: .now, by: 30)) { _ in
                if let state = Battery.shared.state {
                    HStack(spacing: 5) {
                        Text(BatteryView.text(for: state))
                            .font(.system(size: 13, weight: .semibold).monospacedDigit())
                            .foregroundStyle(.white)
                        Image(nsImage: BatteryGlyph.image(for: state))
                    }
                    .lineLimit(1)
                }
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
            .offset(y: -1.5)
            .frame(maxHeight: .infinity)
            .overlay(alignment: .bottom) {
                // Progress line, as on the Touch Bar.
                let progress = CGFloat(NowPlayingMonitor.shared.progress ?? 0.35)
                Capsule()
                    .fill(.white.opacity(0.18))
                    .overlay(alignment: .leading) {
                        GeometryReader { proxy in
                            Capsule().fill(Color(cgColor: GlassSlider.fillColor)).frame(
                                width: proxy.size.width * progress)
                        }
                    }
                    .frame(height: 2)
                    .padding(.horizontal, 15)
                    .padding(.bottom, 2.5)
            }
            .glassEffect(.regular, in: .capsule)
        case .appControls:
            appIcon(Self.finderIcon)
        case .app(let url?) where kind.isAvailable:
            appIcon(BarItemKind.icon(for: url))
        case .app(.some):
            // The app has been deleted or moved; the Touch Bar leaves it out.
            Image(systemName: "questionmark.app.dashed")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white.opacity(0.45))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .glassEffect(.regular, in: .capsule)
                .help("\(kind.title) can’t be found. Right-click to choose another app.")
        default:
            Image(systemName: kind.symbol ?? "questionmark")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .glassEffect(.regular, in: .capsule)
        }
    }

    private var spacerOutline: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .strokeBorder(.white.opacity(isHighlighted ? 0.6 : 0.3), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
    }

    private func appIcon(_ icon: NSImage) -> some View {
        Image(nsImage: icon)
            .resizable()
            .frame(width: 22, height: 22)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .glassEffect(.regular, in: .capsule)
    }
}

/// A flexible space's background, rendered by the same code as on the Touch Bar.
struct SpaceBackgroundImage: View {
    let background: SpaceBackground
    let width: CGFloat
    @Environment(\.displayScale) private var scale

    var body: some View {
        if let image = background.image(size: CGSize(width: width, height: BarMetrics.height), scale: scale) {
            Image(decorative: image, scale: scale)
        }
    }
}
