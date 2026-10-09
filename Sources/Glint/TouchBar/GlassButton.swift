import AppKit

/// A Liquid Glass capsule for the Touch Bar.
///
/// Tapping calls `onTap`. Setting `onTouchDown` instead turns the button into a handle:
/// the whole touch (down, every move, up) is reported in this view's coordinates the
/// moment the finger lands, which is how level buttons open a slider under the finger.
@MainActor
final class GlassButton: NSView {
    var onTap: (() -> Void)?
    var onTouchDown: ((CGFloat) -> Void)?
    var onTouchMoved: ((CGFloat) -> Void)?
    var onTouchUp: (() -> Void)?

    /// When true the glass is tinted to show an "on" state (e.g. muted).
    var isActive = false { didSet { if isActive != oldValue { updateTint() } } }

    /// Calls `onTap` as soon as the finger lands, then repeatedly while it stays down,
    /// like the keyboard's volume and brightness keys.
    var repeatsWhileHeld = false

    private let glass = NSGlassEffectView()
    private let content = NSView()
    private let imageView = NSImageView()
    private let width: CGFloat
    /// The SF Symbol shown, so setting the same one again is free.
    private var symbol: String?

    private var touchStartX: CGFloat = 0
    private var isPressed = false
    private var repeatTask: Task<Void, Never>?
    private static let repeatDelay: Duration = .milliseconds(400)
    private static let repeatInterval: Duration = .milliseconds(90)

    init(symbol: String, width: CGFloat = 44) {
        self.width = width
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: BarMetrics.height))
        allowedTouchTypes = .direct
        wantsLayer = true

        glass.cornerRadius = BarMetrics.height / 2
        glass.frame = bounds
        glass.autoresizingMask = [.width, .height]

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
        guard name != symbol else { return }
        symbol = name
        let config = NSImage.SymbolConfiguration(pointSize: 15, weight: .semibold)
        imageView.image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(config)
    }

    func setImage(_ image: NSImage?) {
        symbol = nil
        imageView.image = image
    }

    // MARK: - Touches

    override func touchesBegan(with event: NSEvent) {
        guard let touch = event.touches(matching: .began, in: self).first else { return }
        touchStartX = touch.location(in: self).x
        if let onTouchDown {
            onTouchDown(touchStartX)
        } else {
            setPressed(true)
            if repeatsWhileHeld { startRepeating() }
        }
    }

    override func touchesMoved(with event: NSEvent) {
        guard let onTouchMoved, let touch = event.touches(matching: .moved, in: self).first else { return }
        onTouchMoved(touch.location(in: self).x)
    }

    override func touchesEnded(with event: NSEvent) {
        if let onTouchUp {
            onTouchUp()
            return
        }
        setPressed(false)
        if repeatsWhileHeld {
            stopRepeating()
            return
        }
        if touchEndedInside(event, fallbackX: touchStartX) { onTap?() }
    }

    override func touchesCancelled(with event: NSEvent) {
        if let onTouchUp {
            onTouchUp()
        } else {
            setPressed(false)
            stopRepeating()
        }
    }

    private func startRepeating() {
        onTap?()
        repeatTask?.cancel()
        repeatTask = Task { [weak self] in
            try? await Task.sleep(for: Self.repeatDelay)
            while let self, !Task.isCancelled {
                self.onTap?()
                try? await Task.sleep(for: Self.repeatInterval)
            }
        }
    }

    private func stopRepeating() {
        repeatTask?.cancel()
        repeatTask = nil
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

extension NSView {
    /// Whether the touch that ended with `event` lifted on this view, give or take a little,
    /// and so counts as a tap. `fallbackX` stands in if the event doesn't say where.
    func touchEndedInside(_ event: NSEvent, fallbackX: CGFloat) -> Bool {
        let x = event.touches(matching: .ended, in: self).first?.location(in: self).x ?? fallbackX
        return x > -12 && x < bounds.width + 12
    }
}
