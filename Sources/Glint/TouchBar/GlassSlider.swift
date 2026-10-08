import AppKit

/// A Touch Bar slider with a Liquid Glass knob that swells while it is held,
/// letting the filled track shine through it.
@MainActor
final class GlassSlider: NSView {
    var onChange: ((Float) -> Void)?
    var onTouchBegan: (() -> Void)?
    var onTouchEnded: (() -> Void)?

    var value: Float = 0 {
        didSet {
            value = min(max(value, 0), 1)
            if !isTracking { needsLayout = true }
        }
    }

    private let track = CALayer()
    private let fill = CALayer()
    private let knob = NSGlassEffectView()
    private(set) var isTracking = false

    private static let trackHeight: CGFloat = 6
    private static let knobSize = NSSize(width: 38, height: 22)
    private static let knobHeldSize = NSSize(width: 54, height: 28)

    override init(frame: NSRect) {
        super.init(frame: frame)
        allowedTouchTypes = .direct
        wantsLayer = true

        track.backgroundColor = NSColor.white.withAlphaComponent(0.16).cgColor
        track.cornerRadius = Self.trackHeight / 2
        fill.backgroundColor = NSColor.white.cgColor
        fill.cornerRadius = Self.trackHeight / 2
        layer?.addSublayer(track)
        layer?.addSublayer(fill)

        knob.style = .clear
        knob.cornerRadius = Self.knobSize.height / 2
        addSubview(knob)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        layoutParts(animated: false)
    }

    private var knobTravel: (min: CGFloat, max: CGFloat) {
        let inset = Self.knobHeldSize.width / 2
        return (inset, bounds.width - inset)
    }

    private func layoutParts(animated: Bool) {
        let travel = knobTravel
        let centerX = travel.min + (travel.max - travel.min) * CGFloat(value)
        let size = isTracking ? Self.knobHeldSize : Self.knobSize

        CATransaction.begin()
        CATransaction.setDisableActions(!animated)
        let trackY = (bounds.height - Self.trackHeight) / 2
        track.frame = NSRect(x: travel.min, y: trackY, width: travel.max - travel.min, height: Self.trackHeight)
        fill.frame = NSRect(x: travel.min, y: trackY, width: centerX - travel.min, height: Self.trackHeight)
        CATransaction.commit()

        let knobFrame = NSRect(x: centerX - size.width / 2, y: (bounds.height - size.height) / 2, width: size.width, height: size.height)
        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.18
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                knob.animator().frame = knobFrame
            }
        } else {
            knob.frame = knobFrame
        }
        knob.cornerRadius = size.height / 2
    }

    // MARK: - Touches

    override func touchesBegan(with event: NSEvent) {
        guard let touch = event.touches(matching: .began, in: self).first else { return }
        isTracking = true
        onTouchBegan?()
        followTouch(to: touch.location(in: self).x)
        layoutParts(animated: true)
    }

    override func touchesMoved(with event: NSEvent) {
        guard let touch = event.touches(matching: .moved, in: self).first else { return }
        followTouch(to: touch.location(in: self).x)
        layoutParts(animated: false)
    }

    override func touchesEnded(with event: NSEvent) { endTracking() }
    override func touchesCancelled(with event: NSEvent) { endTracking() }

    private func followTouch(to x: CGFloat) {
        let travel = knobTravel
        let newValue = Float((x - travel.min) / max(travel.max - travel.min, 1))
        value = newValue
        onChange?(value)
    }

    private func endTracking() {
        guard isTracking else { return }
        isTracking = false
        layoutParts(animated: true)
        onTouchEnded?()
    }
}
