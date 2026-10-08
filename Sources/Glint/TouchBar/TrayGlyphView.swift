import AppKit

/// Glint's button in the Control Strip: the Lens glyph, a glass knob on a slider track.
/// `playGlint()` runs a highlight once around the rim of the lens, then twinkles the star.
@MainActor
final class TrayGlyphView: NSView {
    var onTap: (() -> Void)?

    private typealias Glyph = LensGlyph.TouchBar

    /// Holds the glyph in its own coordinates (points, y down, like the SVG).
    private let glyph = CALayer()
    private let sweep = CAShapeLayer()
    private let star = CAShapeLayer()
    private var shapeLayers: [CALayer] = []

    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: Glyph.size.width + 4, height: BarMetrics.height))
        allowedTouchTypes = .direct
        wantsLayer = true
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel("Show Glint")

        glyph.bounds = CGRect(origin: .zero, size: Glyph.size)
        glyph.isGeometryFlipped = true
        buildGlyph()
        layer?.addSublayer(glyph)
        updateContentsScale()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var intrinsicContentSize: NSSize { NSSize(width: Glyph.size.width + 4, height: BarMetrics.height) }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        glyph.position = CGPoint(x: bounds.midX, y: bounds.midY)
        CATransaction.commit()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        updateContentsScale()
    }

    // MARK: - Glint

    /// Plays the glint once (skipped when Reduce Motion is on).
    func playGlint() {
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
        let now = CACurrentMediaTime()

        let turn = CABasicAnimation(keyPath: "transform.rotation.z")
        turn.fromValue = 0
        turn.toValue = 2 * CGFloat.pi
        turn.duration = 1.43
        turn.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        let fade = CAKeyframeAnimation(keyPath: "opacity")
        fade.values = [0, 1, 1, 0]
        fade.keyTimes = [0, 0.14, 0.81, 1]
        fade.duration = 1.76
        let sweepGroup = CAAnimationGroup()
        sweepGroup.animations = [turn, fade]
        sweepGroup.duration = 1.76
        sweepGroup.beginTime = now
        sweep.add(sweepGroup, forKey: "glint")

        // The star twinkles as the highlight comes back around to it.
        let grow = CAKeyframeAnimation(keyPath: "transform.scale")
        grow.values = [1, 1.8, 1]
        let spin = CAKeyframeAnimation(keyPath: "transform.rotation.z")
        spin.values = [0, CGFloat.pi / 4, CGFloat.pi / 2]
        for animation in [grow, spin] {
            animation.keyTimes = [0, 0.4, 1]
            animation.timingFunctions = [
                CAMediaTimingFunction(name: .easeOut), CAMediaTimingFunction(name: .easeInEaseOut),
            ]
        }
        let twinkle = CAAnimationGroup()
        twinkle.animations = [grow, spin]
        twinkle.duration = 0.84
        twinkle.beginTime = now + 1.26
        star.add(twinkle, forKey: "glint")
    }

    // MARK: - Touches

    override func touchesBegan(with event: NSEvent) {
        setPressed(true)
    }

    override func touchesEnded(with event: NSEvent) {
        setPressed(false)
        let x = event.touches(matching: .ended, in: self).first?.location(in: self).x ?? bounds.midX
        if x > -12, x < bounds.width + 12 { onTap?() }
    }

    override func touchesCancelled(with event: NSEvent) {
        setPressed(false)
    }

    private func setPressed(_ pressed: Bool) {
        glyph.opacity = pressed ? 0.5 : 1
    }

    // MARK: - Drawing

    private func buildGlyph() {
        func shape(_ path: CGPath, alpha: CGFloat) -> CAShapeLayer {
            let layer = CAShapeLayer()
            layer.frame = glyph.bounds
            layer.path = path
            layer.fillColor = NSColor.white.withAlphaComponent(alpha).cgColor
            return layer
        }

        // The track runs through the knob; under the glass it swells.
        shapeLayers = [
            shape(Glyph.track.subtracting(Glyph.glass), alpha: 0.35),
            shape(Glyph.fill.subtracting(Glyph.glass), alpha: 1),
            shape(Glyph.swollenTrack.intersection(Glyph.glass), alpha: 0.35),
            shape(Glyph.swollenFill.intersection(Glyph.glass), alpha: 1),
            shape(LensGlyph.circle(Glyph.knob, Glyph.radius), alpha: 0.06),
            rim(),
        ]

        sweep.frame = glyph.bounds
        sweep.anchorPoint = CGPoint(x: Glyph.knob.x / Glyph.size.width, y: Glyph.knob.y / Glyph.size.height)
        sweep.position = Glyph.knob
        let arc = CGMutablePath()
        let start = -150 * CGFloat.pi / 180
        arc.addArc(
            center: Glyph.knob, radius: Glyph.radius, startAngle: start, endAngle: start + 0.14 * 2 * .pi,
            clockwise: false)
        sweep.path = arc
        sweep.fillColor = nil
        sweep.strokeColor = NSColor.white.cgColor
        sweep.lineWidth = 1.4
        sweep.lineCap = .round
        sweep.shadowColor = NSColor.white.cgColor
        sweep.shadowOpacity = 1
        sweep.shadowRadius = 1.2
        sweep.shadowOffset = .zero
        sweep.opacity = 0

        star.frame = glyph.bounds
        star.anchorPoint = CGPoint(x: Glyph.star.x / Glyph.size.width, y: Glyph.star.y / Glyph.size.height)
        star.position = Glyph.star
        star.path = Glyph.starPath
        star.fillColor = NSColor.white.cgColor

        shapeLayers += [sweep, star]
        shapeLayers.forEach(glyph.addSublayer)
    }

    /// The rim of the lens: brightest at the top left where the light comes from.
    private func rim() -> CALayer {
        let box = CGRect(
            x: Glyph.knob.x - Glyph.radius, y: Glyph.knob.y - Glyph.radius,
            width: 2 * Glyph.radius, height: 2 * Glyph.radius
        ).insetBy(dx: -1, dy: -1)
        let gradient = CAGradientLayer()
        gradient.frame = box
        gradient.colors = [1, 0.35, 0.8].map { NSColor.white.withAlphaComponent($0).cgColor }
        gradient.locations = [0, 0.55, 1]
        gradient.startPoint = CGPoint(x: 0, y: 0)
        gradient.endPoint = CGPoint(x: 1, y: 1)

        let mask = CAShapeLayer()
        mask.frame = gradient.bounds
        var toBox = CGAffineTransform(translationX: -box.minX, y: -box.minY)
        mask.path = LensGlyph.circle(Glyph.knob, Glyph.radius)
            .copy(strokingWithWidth: Glyph.rimWidth, lineCap: .butt, lineJoin: .miter, miterLimit: 10)
            .copy(using: &toBox)
        gradient.mask = mask
        return gradient
    }

    private func updateContentsScale() {
        let scale = window?.backingScaleFactor ?? 2
        for layer in shapeLayers {
            layer.contentsScale = scale
            layer.mask?.contentsScale = scale
        }
    }
}
