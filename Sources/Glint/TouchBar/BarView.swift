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

/// The whole Glint bar: a main row of controls and a slider row that replaces it
/// while a level is being adjusted. Both live in a single Touch Bar item so Glint
/// fully controls layout and transitions.
@MainActor
final class BarView: NSView {
    let main = MainRowView()
    let slider = SliderRowView()

    private(set) var isShowingSlider = false

    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: BarMetrics.width, height: BarMetrics.height))
        wantsLayer = true
        slider.alphaValue = 0
        slider.isHidden = true
        addSubview(main)
        addSubview(slider)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var intrinsicContentSize: NSSize { NSSize(width: BarMetrics.width, height: BarMetrics.height) }

    override func layout() {
        super.layout()
        main.frame = bounds
        if !isAnimating { slider.frame = bounds }
    }

    private var isAnimating = false

    func showSlider(_ visible: Bool, animated: Bool = true) {
        guard visible != isShowingSlider else { return }
        isShowingSlider = visible
        let incoming: NSView = visible ? slider : main
        let outgoing: NSView = visible ? main : slider
        let shift: CGFloat = visible ? 24 : -24

        guard animated else {
            incoming.isHidden = false
            incoming.alphaValue = 1
            outgoing.alphaValue = 0
            outgoing.isHidden = true
            return
        }

        isAnimating = true
        incoming.isHidden = false
        incoming.frame = bounds.offsetBy(dx: shift, dy: 0)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.22
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            incoming.animator().alphaValue = 1
            incoming.animator().frame = bounds
            outgoing.animator().alphaValue = 0
            outgoing.animator().frame = bounds.offsetBy(dx: -shift, dy: 0)
        } completionHandler: {
            MainActor.assumeIsolated {
                outgoing.isHidden = true
                outgoing.frame = self.bounds
                self.isAnimating = false
            }
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

    /// Transient readout shown in the free middle area while scrubbing a button.
    let readout = NSTextField(labelWithString: "")

    private var leftGroups: [[NSView]] { [[appButton], [previousButton, playPauseButton, nextButton]] }
    private var rightGroups: [[NSView]] { [[keyboardButton, displayButton, volumeButton, muteButton], [screenshotButton]] }

    init() {
        super.init(frame: .zero)
        for view in (leftGroups + rightGroups).flatMap({ $0 }) { addSubview(view) }
        readout.font = .monospacedDigitSystemFont(ofSize: 14, weight: .medium)
        readout.textColor = .white
        readout.alignment = .center
        readout.alphaValue = 0
        addSubview(readout)
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
        let leftEdge = x

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

        let readoutHeight = readout.intrinsicContentSize.height
        readout.frame = NSRect(x: leftEdge, y: (bounds.height - readoutHeight) / 2, width: x - leftEdge, height: readoutHeight)
    }

    func showReadout(_ text: String?) {
        if let text { readout.stringValue = text }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = text == nil ? 0.35 : 0.12
            readout.animator().alphaValue = text == nil ? 0 : 1
        }
    }
}

/// Close · level icon · slider · percentage.
@MainActor
final class SliderRowView: NSView {
    let closeButton = GlassButton(symbol: "xmark", width: BarMetrics.compactButtonWidth)
    let iconButton = GlassButton(symbol: "speaker.wave.2.fill")
    let slider = GlassSlider(frame: .zero)
    let valueLabel = NSTextField(labelWithString: "")

    init() {
        super.init(frame: .zero)
        valueLabel.font = .monospacedDigitSystemFont(ofSize: 14, weight: .medium)
        valueLabel.textColor = .white
        valueLabel.alignment = .right
        [closeButton, iconButton, slider, valueLabel].forEach(addSubview)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        let h = BarMetrics.height
        closeButton.frame = NSRect(x: 0, y: 0, width: closeButton.intrinsicContentSize.width, height: h)
        iconButton.frame = NSRect(x: closeButton.frame.maxX + BarMetrics.groupGap, y: 0, width: iconButton.intrinsicContentSize.width, height: h)
        let labelWidth: CGFloat = 52
        let labelHeight = valueLabel.intrinsicContentSize.height
        valueLabel.frame = NSRect(x: bounds.width - labelWidth - 6, y: (h - labelHeight) / 2, width: labelWidth, height: labelHeight)
        let sliderX = iconButton.frame.maxX + BarMetrics.gap
        slider.frame = NSRect(x: sliderX, y: 0, width: valueLabel.frame.minX - BarMetrics.gap - sliderX, height: h)
    }
}
