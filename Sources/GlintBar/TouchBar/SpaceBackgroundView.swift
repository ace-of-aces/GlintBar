import AppKit

/// A flexible space's background on the Touch Bar. Purely decorative: touches go through
/// it, and VoiceOver skips it.
@MainActor
final class SpaceBackgroundView: NSView {
    let background: SpaceBackground
    private var image: CGImage?
    private var renderedSize = CGSize.zero

    init(_ background: SpaceBackground) {
        self.background = background
        super.init(frame: .zero)
        wantsLayer = true
        layerContentsRedrawPolicy = .onSetNeedsDisplay
        // While the frame animates to a new width the picture, already rendered for it,
        // stays centred and unstretched, and is clipped to the frame.
        layerContentsPlacement = .center
        layer?.masksToBounds = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    /// Renders the picture for a space of `size`. Called before the frame moves there, so a
    /// resize renders once, not on every step of its animation. A space too narrow for the
    /// picture keeps the last one, for the owner to fade out.
    func prepare(for size: CGSize) {
        guard size != renderedSize, background.isShown(inWidth: size.width) else { return }
        renderedSize = size
        let scale = window?.backingScaleFactor ?? 2
        layer?.contentsScale = scale
        image = background.image(size: size, scale: scale)
        needsDisplay = true
    }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        layer?.contents = image
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        guard renderedSize != .zero else { return }
        let size = renderedSize
        renderedSize = .zero
        prepare(for: size)
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func isAccessibilityElement() -> Bool { false }
    override func accessibilityChildren() -> [Any]? { [] }
}
