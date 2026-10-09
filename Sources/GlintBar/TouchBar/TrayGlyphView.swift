import AppKit

/// GlintBar's button in the Control Strip: the Eclipse glyph, a black bar edged in light with a
/// diamond on its rim. `playGlint()` runs light along the bar's top edge into the diamond,
/// which flares.
@MainActor
final class TrayGlyphView: NSView {
    var onTap: (() -> Void)?

    private typealias Glyph = EclipseGlyph.TouchBar

    /// Holds the glyph in its own coordinates (points, y down, like the SVG).
    private let glyph = CALayer()
    private let sweep = CAShapeLayer()
    /// The halo and the star, scaled together around the diamond's center.
    private let diamond = CALayer()
    private var drawnLayers: [CALayer] = []

    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: Glyph.size.width + 4, height: BarMetrics.height))
        allowedTouchTypes = .direct
        wantsLayer = true
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel("Show GlintBar")

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

        let run = CABasicAnimation(keyPath: "transform.translation.x")
        run.fromValue = 0
        run.toValue = Glyph.sweepDistance
        run.duration = 1.26
        run.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        let fade = CAKeyframeAnimation(keyPath: "opacity")
        fade.values = [0, 1, 1, 0]
        fade.keyTimes = [0, 0.17, 0.83, 1]
        let sweepGroup = CAAnimationGroup()
        sweepGroup.animations = [run, fade]
        sweepGroup.duration = 1.51
        fade.duration = sweepGroup.duration
        sweepGroup.beginTime = now
        sweep.add(sweepGroup, forKey: "glint")

        // The diamond dims while the light travels, then flares as it arrives.
        let scale = CAKeyframeAnimation(keyPath: "transform.scale")
        scale.values = [1, 0.55, 0.55, 1.4, 1]
        let brightness = CAKeyframeAnimation(keyPath: "opacity")
        brightness.values = [1, 0.55, 0.55, 1, 1]
        for animation in [scale, brightness] {
            animation.keyTimes = [0, 0.13, 0.57, 0.74, 1]
        }
        let flare = CAAnimationGroup()
        flare.animations = [scale, brightness]
        flare.duration = 1.93
        flare.beginTime = now
        diamond.add(flare, forKey: "glint")
    }

    // MARK: - Touches

    override func touchesBegan(with event: NSEvent) {
        setPressed(true)
    }

    override func touchesEnded(with event: NSEvent) {
        setPressed(false)
        if touchEndedInside(event, fallbackX: bounds.midX) { onTap?() }
    }

    override func touchesCancelled(with event: NSEvent) {
        setPressed(false)
    }

    private func setPressed(_ pressed: Bool) {
        glyph.opacity = pressed ? 0.5 : 1
    }

    // MARK: - Drawing

    private func buildGlyph() {
        // A soft glow just outside the rim, built from wider and wider faint strokes so it
        // fades out like a blur at any scale.
        let glow = CALayer()
        glow.frame = glyph.bounds
        let glowColor = NSColor(srgbRed: 0.95, green: 0.82, blue: 0.61, alpha: 0.055).cgColor
        for step in 0..<8 {
            let ring = CAShapeLayer()
            ring.frame = glyph.bounds
            ring.path = Glyph.glowPath
            ring.fillColor = nil
            ring.strokeColor = glowColor
            ring.lineWidth = 1.6 + CGFloat(step) * 0.75
            glow.addSublayer(ring)
        }

        let bar = CAShapeLayer()
        bar.frame = glyph.bounds
        bar.path = Glyph.barPath
        bar.fillColor = NSColor.black.cgColor
        bar.strokeColor = NSColor(srgbRed: 1, green: 0.965, blue: 0.9, alpha: 1).cgColor
        bar.lineWidth = 1.1

        sweep.frame = glyph.bounds
        sweep.path = Glyph.sweepPath
        sweep.fillColor = NSColor.white.cgColor
        sweep.shadowColor = NSColor.white.cgColor
        sweep.shadowOpacity = 1
        sweep.shadowRadius = 0.6
        sweep.shadowOffset = .zero
        sweep.opacity = 0

        diamond.frame = glyph.bounds
        diamond.anchorPoint = CGPoint(x: Glyph.diamond.x / Glyph.size.width, y: Glyph.diamond.y / Glyph.size.height)
        diamond.position = Glyph.diamond

        let halo = CAGradientLayer()
        halo.type = .radial
        halo.frame = CGRect(
            x: Glyph.diamond.x - Glyph.haloRadius, y: Glyph.diamond.y - Glyph.haloRadius,
            width: 2 * Glyph.haloRadius, height: 2 * Glyph.haloRadius)
        halo.colors = [
            NSColor.white.cgColor,
            NSColor(srgbRed: 1, green: 0.953, blue: 0.863, alpha: 0.45).cgColor,
            NSColor(srgbRed: 0.957, green: 0.851, blue: 0.651, alpha: 0).cgColor,
        ]
        halo.locations = [0, 0.25, 1]
        halo.startPoint = CGPoint(x: 0.5, y: 0.5)
        halo.endPoint = CGPoint(x: 1, y: 1)

        let star = CAShapeLayer()
        star.frame = glyph.bounds
        star.path = Glyph.diamondPath
        star.fillColor = NSColor.white.cgColor

        diamond.addSublayer(halo)
        diamond.addSublayer(star)
        drawnLayers = (glow.sublayers ?? []) + [bar, sweep, halo, star]
        [glow, bar, sweep, diamond].forEach(glyph.addSublayer)
    }

    private func updateContentsScale() {
        let scale = window?.backingScaleFactor ?? 2
        drawnLayers.forEach { $0.contentsScale = scale }
    }
}
