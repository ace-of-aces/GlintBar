import SwiftUI

/// The popover for choosing what a flexible space shows: nothing, or one of the
/// backgrounds, each previewed as it looks on the Touch Bar. A choice applies at once,
/// so the Touch Bar can be watched while trying them out.
struct BackgroundPicker: View {
    let selection: SpaceBackground?
    /// How wide the space is now, to say when it's too narrow for its background.
    let width: CGFloat
    let onSelect: (SpaceBackground?) -> Void

    static let thumbnailWidth: CGFloat = 156

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Background")
                .font(.headline)
            Grid(horizontalSpacing: 14, verticalSpacing: 12) {
                GridRow {
                    option(nil)
                    option(.midnightSky)
                }
                GridRow {
                    option(.blackHole)
                    option(.prism)
                }
            }
            if let selection, !selection.isShown(inWidth: width) {
                Label(
                    "This space is too narrow to show \(selection.title). Remove an item to make room.",
                    systemImage: "info.circle"
                )
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(width: 2 * (Self.thumbnailWidth + 2 * BackgroundOption.inset) + 14, alignment: .leading)
        .padding(16)
    }

    private func option(_ background: SpaceBackground?) -> some View {
        BackgroundOption(background: background, isSelected: background == selection) { onSelect(background) }
    }
}

/// One choice in the picker: its preview in a black box, ringed when chosen.
private struct BackgroundOption: View {
    let background: SpaceBackground?
    let isSelected: Bool
    let action: () -> Void

    static let inset: CGFloat = 6
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                ItemPreview(kind: .flexibleSpace(background), width: BackgroundPicker.thumbnailWidth)
                    .padding(Self.inset)
                    .background(.black, in: box)
                    .overlay {
                        box.strokeBorder(
                            isSelected ? Color.accentColor : .white.opacity(isHovered ? 0.3 : 0.1),
                            lineWidth: isSelected ? 2 : 1)
                    }
                Text(background?.title ?? "None")
                    .font(.callout)
                    .foregroundStyle(isSelected ? .primary : .secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovered)
        .accessibilityLabel(background?.title ?? "No Background")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var box: RoundedRectangle { RoundedRectangle(cornerRadius: 10, style: .continuous) }
}

/// Hangs the background picker off a flexible space in the customization bar, above it
/// so it doesn't cover the bar. Other items are left alone.
struct BackgroundChoice: ViewModifier {
    let item: BarItem
    let width: CGFloat
    @Binding var isPresented: Bool
    let onSelect: (SpaceBackground?) -> Void

    func body(content: Content) -> some View {
        if item.kind.isFlexibleSpace {
            content
                .help("Click to choose a background for this space")
                .popover(isPresented: $isPresented, arrowEdge: .top) {
                    BackgroundPicker(selection: item.kind.background, width: width, onSelect: onSelect)
                }
        } else {
            content
        }
    }
}
