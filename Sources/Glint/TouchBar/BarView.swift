import AppKit

enum BarMetrics {
    /// Usable width of the Touch Bar to the right of the Esc key, in points.
    static let width: CGFloat = 1004
    static let height: CGFloat = 30
    static let gap: CGFloat = 8
    static let groupGap: CGFloat = 18
    static let buttonWidth: CGFloat = 56
    static let compactButtonWidth: CGFloat = 44
}

/// The whole Glint bar: a row of controls, plus the level panel that pops out of a
/// level button over it. Everything lives in a single Touch Bar item so Glint fully
/// controls layout and transitions.
@MainActor
final class BarView: NSView {
    let main = MainRowView()
    let panel = LevelPanelView()

    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: BarMetrics.width, height: BarMetrics.height))
        wantsLayer = true
        panel.isHidden = true
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

    var isShowingPanel: Bool { !panel.isHidden && panel.level != nil }

    /// Pops the panel for `level` out of `button`; the rest of the row fades away.
    /// The row stays in the view hierarchy (only transparent) so the touch that
    /// began on `button` keeps being delivered to it.
    func openPanel(_ level: Level, from button: NSView) {
        panel.isHidden = false
        panel.present(level, from: convert(button.bounds, from: button))
        NSAnimationContext.runAnimationGroup { context in
            context.duration = LevelPanelView.popDuration
            main.animator().alphaValue = 0
        }
    }

    func closePanel(animated: Bool = true) {
        guard isShowingPanel else { return }
        panel.dismiss(animated: animated) { [weak self] in
            // New touches should reach the row again once the panel is gone.
            self?.panel.isHidden = true
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = animated ? LevelPanelView.popDuration : 0
            main.animator().alphaValue = 1
        }
    }
}

/// App switcher and media on the left, the system strip on the right.
@MainActor
final class MainRowView: NSView {
    let appButton = GlassButton(symbol: "app.dashed", width: BarMetrics.compactButtonWidth)
    let previousButton = GlassButton(symbol: "backward.fill", width: BarMetrics.compactButtonWidth)
    let playPauseButton = GlassButton(symbol: "playpause.fill")
    let nextButton = GlassButton(symbol: "forward.fill", width: BarMetrics.compactButtonWidth)

    let keyboardButton = GlassButton(symbol: "light.max")
    let displayButton = GlassButton(symbol: "sun.max.fill")
    let volumeButton = GlassButton(symbol: "speaker.wave.2.fill")
    let muteButton = GlassButton(symbol: "speaker.slash.fill", width: BarMetrics.compactButtonWidth)
    let screenshotButton = GlassButton(symbol: "camera.fill", width: BarMetrics.compactButtonWidth)

    private var leftGroups: [[NSView]] { [[appButton], [previousButton, playPauseButton, nextButton]] }
    private var rightGroups: [[NSView]] { [[keyboardButton, displayButton, volumeButton, muteButton], [screenshotButton]] }

    init() {
        super.init(frame: .zero)
        for view in (leftGroups + rightGroups).flatMap({ $0 }) { addSubview(view) }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        var x: CGFloat = 0
        for (index, group) in leftGroups.enumerated() {
            if index > 0 { x += BarMetrics.groupGap - BarMetrics.gap }
            for view in group {
                let width = view.intrinsicContentSize.width
                view.frame = NSRect(x: x, y: 0, width: width, height: BarMetrics.height)
                x += width + BarMetrics.gap
            }
        }

        x = bounds.width
        for (index, group) in rightGroups.reversed().enumerated() {
            if index > 0 { x -= BarMetrics.groupGap - BarMetrics.gap }
            for view in group.reversed() {
                let width = view.intrinsicContentSize.width
                x -= width
                view.frame = NSRect(x: x, y: 0, width: width, height: BarMetrics.height)
                x -= BarMetrics.gap
            }
        }
    }
}

/// The level slider, modelled on the native Control Strip: a fixed-size panel whose
/// right edge sits against the button it pops out of — low icon, track, high icon —
/// and an ✕ in the button's own slot once the finger lifts.
@MainActor
final class LevelPanelView: NSView {
    let slider = GlassSlider(frame: .zero)
    let closeButton = GlassButton(symbol: "xmark", width: BarMetrics.compactButtonWidth)
    /// A touch on the bar outside the panel and the ✕.
    var onOutsideTouch: (() -> Void)?

    private(set) var level: Level?
    private let background = NSGlassEffectView()
    private let lowIcon = NSImageView()
    private let highIcon = NSImageView()
    private var panelFrame = NSRect.zero
    private var buttonFrame = NSRect.zero
    /// Bumped on every present/dismiss so stale animation callbacks are ignored.
    private var generation = 0
    /// Clips the slider to the growing panel, so the track emerges from the button.
    private let reveal = CALayer()

    // Native geometry, measured on the Touch Bar: a 357 pt panel, icons centred
    // 35 pt in from its ends and a 202 pt track between them.
    static let panelWidth: CGFloat = 357
    static let iconInset: CGFloat = 35
    static let trackInset: CGFloat = 77.5
    static let popDuration: TimeInterval = 0.2
    private static let buttonGap: CGFloat = 4

    init() {
        super.init(frame: .zero)
        allowedTouchTypes = .direct
        background.cornerRadius = BarMetrics.height / 2
        for icon in [lowIcon, highIcon] {
            icon.contentTintColor = .white
            icon.imageScaling = .scaleNone
        }
        slider.trackInset = Self.trackInset
        closeButton.alphaValue = 0
        [background, lowIcon, highIcon, slider, closeButton].forEach(addSubview)
        reveal.backgroundColor = NSColor.black.cgColor
        reveal.cornerRadius = BarMetrics.height / 2
        slider.wantsLayer = true
        slider.layer?.mask = reveal
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func present(_ level: Level, from buttonFrame: NSRect) {
        self.level = level
        self.buttonFrame = buttonFrame
        panelFrame = NSRect(
            x: max(buttonFrame.minX - Self.buttonGap - Self.panelWidth, 0),
            y: 0, width: Self.panelWidth, height: BarMetrics.height
        )
        lowIcon.image = Self.symbol(level.lowSymbol, size: 13)
        highIcon.image = Self.symbol(level.highSymbol, size: 15)
        slider.frame = panelFrame
        slider.setValue(level.value)
        let closeWidth = closeButton.intrinsicContentSize.width
        closeButton.frame = NSRect(x: buttonFrame.midX - closeWidth / 2, y: 0, width: closeWidth, height: BarMetrics.height)
        closeButton.alphaValue = 0

        // Start collapsed into the button, then grow out of it.
        background.frame = buttonFrame
        lowIcon.frame = iconFrame(centerX: buttonFrame.midX)
        highIcon.frame = iconFrame(centerX: buttonFrame.midX)
        [lowIcon, highIcon].forEach { $0.alphaValue = 0 }
        slider.alphaValue = 1
        background.alphaValue = 1
        setReveal(buttonFrame, animated: false)

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
                    self.lowIcon.animator().frame = self.iconFrame(centerX: self.panelFrame.minX + Self.iconInset)
                    self.highIcon.animator().frame = self.iconFrame(centerX: self.panelFrame.maxX - Self.iconInset)
                    self.lowIcon.animator().alphaValue = 1
                    self.highIcon.animator().alphaValue = 1
                }
            }
        }
    }

    /// Collapses back into the button. `completion` runs unless the panel was
    /// presented again in the meantime.
    func dismiss(animated: Bool, completion: @escaping @MainActor () -> Void) {
        level = nil
        generation += 1
        let current = generation
        setReveal(buttonFrame, animated: animated)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = animated ? Self.popDuration : 0
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            background.animator().frame = buttonFrame
            background.animator().alphaValue = 0
            lowIcon.animator().frame = iconFrame(centerX: buttonFrame.midX)
            highIcon.animator().frame = iconFrame(centerX: buttonFrame.midX)
            [lowIcon, highIcon, slider, closeButton].forEach { $0.animator().alphaValue = 0 }
        } completionHandler: {
            MainActor.assumeIsolated {
                if current == self.generation { completion() }
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

    private func iconFrame(centerX: CGFloat) -> NSRect {
        NSRect(x: centerX - 14, y: 0, width: 28, height: BarMetrics.height)
    }

    private static func symbol(_ name: String, size: CGFloat) -> NSImage? {
        NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: size, weight: .semibold))
    }
}
