import AppKit

enum BarMetrics {
    /// Usable width of the Touch Bar to the right of the Esc key, in points.
    static let width: CGFloat = 1004
    static let height: CGFloat = 30
}

/// The whole GlintBar: a row of controls, plus the level panel that pops out of a
/// level button over it. Everything lives in a single Touch Bar item so GlintBar fully
/// controls layout and transitions.
@MainActor
final class BarView: NSView {
    let main = MainRowView()
    let panel = SliderPanelView()

    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: BarMetrics.width, height: BarMetrics.height))
        wantsLayer = true
        addSubview(main)
        addSubview(panel)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var intrinsicContentSize: NSSize { NSSize(width: BarMetrics.width, height: BarMetrics.height) }

    override func layout() {
        super.layout()
        main.frame = bounds
        panel.frame = bounds
    }

    /// Pops the slider panel out of `anchor`; the rest of the row fades away.
    /// The row stays in the view hierarchy (only transparent) so the touch that
    /// began on `anchor` keeps being delivered to it.
    func openPanel(
        from anchor: NSView, placement: SliderPanelView.Placement,
        leading: PanelAccessory, trailing: PanelAccessory, value: Float
    ) {
        panel.present(
            from: convert(anchor.bounds, from: anchor), placement: placement, leading: leading, trailing: trailing,
            value: value)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = SliderPanelView.popDuration
            main.animator().alphaValue = 0
        }
    }

    func closePanel(animated: Bool = true) {
        guard panel.isPresented else { return }
        panel.dismiss(animated: animated)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = animated ? SliderPanelView.popDuration : 0
            main.animator().alphaValue = 1
        }
    }
}

/// The configurable row of items. Views are owned by `BarController`; this view only
/// shows and positions them according to `BarLayout`.
@MainActor
final class MainRowView: NSView {
    private var kinds: [BarItemKind] = []
    private var views: [BarItemKind: NSView] = [:]
    /// Views added by the last `setLayout`, which fade in instead of sliding.
    private var addedKinds: Set<BarItemKind> = []
    private var animateNextLayout = false

    func setLayout(_ kinds: [BarItemKind], views: [BarItemKind: NSView]) {
        for (kind, view) in self.views where views[kind] !== view || !kinds.contains(kind) {
            view.removeFromSuperview()
        }
        animateNextLayout = !self.kinds.isEmpty && window != nil
        self.kinds = kinds
        self.views = views.filter { kinds.contains($0.key) }
        addedKinds = []
        for (kind, view) in self.views where view.superview !== self {
            addSubview(view)
            addedKinds.insert(kind)
        }
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let animate = animateNextLayout
        animateNextLayout = false
        NSAnimationContext.runAnimationGroup { context in
            context.duration = animate ? 0.25 : 0
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            for (kind, frame) in zip(kinds, BarLayout.frames(for: kinds, in: bounds.size)) {
                guard let view = views[kind] else { continue }
                if animate, addedKinds.contains(kind) {
                    view.frame = frame
                    view.alphaValue = 0
                    view.animator().alphaValue = 1
                } else {
                    (animate ? view.animator() : view).frame = frame
                }
            }
        }
        addedKinds = []
    }
}

/// What sits at either end of a slider panel.
enum PanelAccessory: Equatable {
    case symbol(String, size: CGFloat)
    case text(String)
}

/// A slider that pops out of a bar item, modelled on the native Control Strip: a
/// fixed-size panel (end accessories, track) grown out of its anchor, and an ✕ once
/// the finger lifts. Level controls sit it beside their button like the native strip;
/// Now Playing centres it over the widget.
@MainActor
final class SliderPanelView: NSView {
    enum Placement {
        /// Leftwards from the anchor (rightwards if there's no room); ✕ in the anchor's slot.
        case besideAnchor
        /// Centred over the anchor; ✕ next to the panel.
        case overAnchor
    }

    let slider = GlassSlider(frame: .zero)
    let closeButton = GlassButton(symbol: "xmark")
    /// A touch on the bar outside the panel and the ✕.
    var onOutsideTouch: (() -> Void)?

    /// Showing, or on its way there. Once dismissed it hides, so new touches reach the row
    /// underneath again.
    private(set) var isPresented = false
    private let background = NSGlassEffectView()
    private let leading = AccessoryView()
    private let trailing = AccessoryView()
    private var panelFrame = NSRect.zero
    private var anchorFrame = NSRect.zero
    /// Bumped on every present/dismiss so stale animation callbacks are ignored.
    private var generation = 0
    /// Clips the slider to the growing panel, so the track emerges from the anchor.
    private let reveal = CALayer()

    // Native geometry, measured on the Touch Bar: a 357 pt panel, icons centred
    // 35 pt in from its ends and a 202 pt track between them.
    static let panelWidth: CGFloat = 357
    static let accessoryInset: CGFloat = 35
    static let trackInset: CGFloat = 77.5
    static let popDuration: TimeInterval = 0.2
    private static let gap: CGFloat = 4

    init() {
        super.init(frame: .zero)
        isHidden = true
        allowedTouchTypes = .direct
        background.cornerRadius = BarMetrics.height / 2
        slider.trackInset = Self.trackInset
        closeButton.alphaValue = 0
        closeButton.setAccessibilityLabel("Close")
        [background, leading, trailing, slider, closeButton].forEach(addSubview)
        reveal.backgroundColor = NSColor.black.cgColor
        reveal.cornerRadius = BarMetrics.height / 2
        slider.wantsLayer = true
        slider.layer?.mask = reveal
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func present(
        from anchorFrame: NSRect, placement: Placement, leading: PanelAccessory, trailing: PanelAccessory, value: Float
    ) {
        isHidden = false
        isPresented = true
        self.anchorFrame = anchorFrame
        let width = Self.panelWidth
        let x: CGFloat
        switch placement {
        case .besideAnchor:
            // Grow leftwards out of the button like the native strip; rightwards if the
            // button sits too close to the left edge.
            let leftX = anchorFrame.minX - Self.gap - width
            x = leftX >= 0 ? leftX : min(anchorFrame.maxX + Self.gap, bounds.width - width)
        case .overAnchor:
            x = min(max(anchorFrame.midX - width / 2, 0), bounds.width - width)
        }
        panelFrame = NSRect(x: x, y: 0, width: width, height: BarMetrics.height)
        setAccessories(leading: leading, trailing: trailing)
        slider.frame = panelFrame
        slider.setValue(value)

        let closeWidth = closeButton.intrinsicContentSize.width
        let closeX: CGFloat =
            switch placement {
            case .besideAnchor:
                anchorFrame.midX - closeWidth / 2
            case .overAnchor:
                panelFrame.maxX + Self.gap + closeWidth <= bounds.width
                    ? panelFrame.maxX + Self.gap
                    : panelFrame.minX - Self.gap - closeWidth
            }
        closeButton.frame = NSRect(x: closeX, y: 0, width: closeWidth, height: BarMetrics.height)
        closeButton.alphaValue = 0

        // Start collapsed into the anchor, then grow out of it.
        background.frame = anchorFrame
        self.leading.frame = accessoryFrame(centerX: anchorFrame.midX)
        self.trailing.frame = accessoryFrame(centerX: anchorFrame.midX)
        [self.leading, self.trailing].forEach { $0.alphaValue = 0 }
        slider.alphaValue = 1
        background.alphaValue = 1
        setReveal(anchorFrame, animated: false)

        // Animate from the next run-loop turn: only then have the start frames above
        // reached the layers, otherwise everything animates from where it last was.
        generation += 1
        let current = generation
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                guard current == self.generation else { return }
                self.setReveal(self.panelFrame, animated: true)
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = Self.popDuration
                    context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                    self.background.animator().frame = self.panelFrame
                    self.leading.animator().frame = self.accessoryFrame(
                        centerX: self.panelFrame.minX + Self.accessoryInset)
                    self.trailing.animator().frame = self.accessoryFrame(
                        centerX: self.panelFrame.maxX - Self.accessoryInset)
                    self.leading.animator().alphaValue = 1
                    self.trailing.animator().alphaValue = 1
                }
            }
        }
    }

    /// Updates the end accessories in place (e.g. elapsed and remaining time).
    func setAccessories(leading: PanelAccessory, trailing: PanelAccessory) {
        self.leading.show(leading, small: true)
        self.trailing.show(trailing, small: false)
    }

    /// Collapses back into the anchor, then hides unless presented again in the meantime.
    func dismiss(animated: Bool) {
        isPresented = false
        generation += 1
        let current = generation
        setReveal(anchorFrame, animated: animated)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = animated ? Self.popDuration : 0
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            background.animator().frame = anchorFrame
            background.animator().alphaValue = 0
            leading.animator().frame = accessoryFrame(centerX: anchorFrame.midX)
            trailing.animator().frame = accessoryFrame(centerX: anchorFrame.midX)
            [leading, trailing, slider, closeButton].forEach { $0.animator().alphaValue = 0 }
        } completionHandler: {
            MainActor.assumeIsolated {
                if current == self.generation { self.isHidden = true }
            }
        }
    }

    func showCloseButton() {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            closeButton.animator().alphaValue = 1
        }
    }

    // MARK: - Touches

    /// The whole panel drives the slider, the ✕ is itself, and everything else is
    /// "outside" (handled here).
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard !isHidden else { return nil }
        let local = convert(point, from: superview)
        if closeButton.alphaValue > 0, closeButton.frame.contains(local) { return closeButton }
        if panelFrame.contains(local) { return slider }
        return bounds.contains(local) ? self : nil
    }

    override func touchesBegan(with event: NSEvent) {
        onOutsideTouch?()
    }

    /// Moves the slider's mask to `rect` (in this view's coordinates).
    private func setReveal(_ rect: NSRect, animated: Bool) {
        CATransaction.begin()
        CATransaction.setDisableActions(!animated)
        CATransaction.setAnimationDuration(Self.popDuration)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeOut))
        reveal.frame = rect.offsetBy(dx: -panelFrame.minX, dy: -panelFrame.minY)
        CATransaction.commit()
    }

    private func accessoryFrame(centerX: CGFloat) -> NSRect {
        NSRect(x: centerX - 28, y: 0, width: 56, height: BarMetrics.height)
    }
}

/// An icon or a short label, centred.
@MainActor
private final class AccessoryView: NSView {
    private let image = NSImageView()
    private let label = NSTextField(labelWithString: "")

    init() {
        super.init(frame: .zero)
        image.contentTintColor = .white
        image.imageScaling = .scaleNone
        label.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        label.textColor = NSColor.white.withAlphaComponent(0.85)
        label.alignment = .center
        for view in [image, label] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
            NSLayoutConstraint.activate([
                view.centerXAnchor.constraint(equalTo: centerXAnchor),
                view.centerYAnchor.constraint(equalTo: centerYAnchor),
            ])
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    /// The slider's value says it all.
    override func accessibilityChildren() -> [Any]? { [] }

    func show(_ accessory: PanelAccessory, small: Bool) {
        switch accessory {
        case .symbol(let name, let size):
            image.image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
                .withSymbolConfiguration(.init(pointSize: size, weight: .semibold))
            image.isHidden = false
            label.isHidden = true
        case .text(let text):
            if label.stringValue != text { label.stringValue = text }
            label.isHidden = false
            image.isHidden = true
        }
    }
}
