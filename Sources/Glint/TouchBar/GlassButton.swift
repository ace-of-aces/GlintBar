import AppKit

/// A Liquid Glass capsule for the Touch Bar.
///
/// Tapping calls `onTap`. When `onScrub` is set, pressing and sliding horizontally
/// adjusts a value in place (like the native volume button) and shows a level gauge
/// inside the glass while the finger is down.
@MainActor
final class GlassButton: NSView {
    var onTap: (() -> Void)?
    var onScrubBegan: (() -> Void)?
    /// Horizontal movement since the last call, in points.
    var onScrub: ((CGFloat) -> Void)?
    var onScrubEnded: (() -> Void)?

    /// When true the glass is tinted to show an "on" state (e.g. muted).
    var isActive = false { didSet { updateTint() } }

    private let glass = NSGlassEffectView()
    private let content = NSView()
    private let imageView = NSImageView()
    private let gauge = CALayer()
    private let width: CGFloat

    private var touchStartX: CGFloat = 0
    private var lastTouchX: CGFloat = 0
    private var isPressed = false
    private var isScrubbing = false
    private static let scrubThreshold: CGFloat = 6

    init(symbol: String, width: CGFloat = BarMetrics.buttonWidth) {
        self.width = width
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: BarMetrics.height))
        allowedTouchTypes = .direct
        wantsLayer = true

        glass.cornerRadius = BarMetrics.height / 2
        glass.frame = bounds
        glass.autoresizingMask = [.width, .height]

        content.wantsLayer = true
        gauge.backgroundColor = NSColor.white.withAlphaComponent(0.22).cgColor
        gauge.opacity = 0
        content.layer?.addSublayer(gauge)

        imageView.imageScaling = .scaleProportionallyDown
        imageView.contentTintColor = .white
        imageView.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(imageView)
        NSLayoutConstraint.activate([
            imageView.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            imageView.centerYAnchor.constraint(equalTo: content.centerYAnchor),
            imageView.heightAnchor.constraint(lessThanOrEqualToConstant: BarMetrics.height - 6),
        ])

        glass.contentView = content
        addSubview(glass)
        setSymbol(symbol)
        updateTint()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var intrinsicContentSize: NSSize { NSSize(width: width, height: BarMetrics.height) }

    func setSymbol(_ name: String) {
        let config = NSImage.SymbolConfiguration(pointSize: 15, weight: .semibold)
        imageView.image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(config)
    }

    func setImage(_ image: NSImage?) {
        imageView.image = image
    }

    /// Fill level of the in-button gauge, 0...1. Only visible while scrubbing.
    func setGauge(_ level: Float) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        gauge.frame = NSRect(x: 0, y: 0, width: bounds.width * CGFloat(min(max(level, 0), 1)), height: bounds.height)
        CATransaction.commit()
    }

    // MARK: - Touches

    override func touchesBegan(with event: NSEvent) {
        guard let touch = event.touches(matching: .began, in: self).first else { return }
        touchStartX = touch.location(in: self).x
        lastTouchX = touchStartX
        isScrubbing = false
        setPressed(true)
    }

    override func touchesMoved(with event: NSEvent) {
        guard let touch = event.touches(matching: .moved, in: self).first else { return }
        let x = touch.location(in: self).x
        if !isScrubbing, onScrub != nil, abs(x - touchStartX) > Self.scrubThreshold {
            isScrubbing = true
            lastTouchX = x
            onScrubBegan?()
            setGaugeVisible(true)
        }
        if isScrubbing {
            onScrub?(x - lastTouchX)
            lastTouchX = x
        }
    }

    override func touchesEnded(with event: NSEvent) {
        let wasScrubbing = isScrubbing
        let endX = event.touches(matching: .ended, in: self).first?.location(in: self).x ?? touchStartX
        finishTouch()
        if wasScrubbing {
            onScrubEnded?()
        } else if endX > -12, endX < bounds.width + 12 {
            onTap?()
        }
    }

    override func touchesCancelled(with event: NSEvent) {
        let wasScrubbing = isScrubbing
        finishTouch()
        if wasScrubbing { onScrubEnded?() }
    }

    private func finishTouch() {
        isScrubbing = false
        setPressed(false)
        setGaugeVisible(false)
    }

    // MARK: - Appearance

    private func setPressed(_ pressed: Bool) {
        isPressed = pressed
        updateTint()
        // A small "inflate" on press, in the spirit of Liquid Glass controls.
        let scale: CGFloat = pressed ? 1.06 : 1
        let transform = CATransform3DTranslate(
            CATransform3DMakeScale(scale, scale, 1),
            bounds.width * (1 - scale) / (2 * scale),
            bounds.height * (1 - scale) / (2 * scale),
            0
        )
        let animation = CABasicAnimation(keyPath: "transform")
        animation.fromValue = layer?.presentation()?.transform ?? layer?.transform
        animation.toValue = transform
        animation.duration = pressed ? 0.08 : 0.22
        animation.timingFunction = CAMediaTimingFunction(name: .easeOut)
        layer?.add(animation, forKey: "press")
        layer?.transform = transform
    }

    private func setGaugeVisible(_ visible: Bool) {
        gauge.opacity = visible ? 1 : 0
    }

    private func updateTint() {
        if isPressed {
            glass.tintColor = NSColor.white.withAlphaComponent(0.28)
        } else if isActive {
            glass.tintColor = NSColor.systemOrange.withAlphaComponent(0.55)
        } else {
            glass.tintColor = nil
        }
    }
}
