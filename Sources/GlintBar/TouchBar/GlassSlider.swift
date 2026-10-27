import AppKit

/// A Touch Bar slider in the style of Liquid Glass sliders: a solid knob at rest
/// that turns into a larger, clear glass lens while it is dragged.
///
/// The track runs between `trackInset` from either edge; touches anywhere in the
/// view drive it. Touches can also be forwarded (`beginTracking` etc.) from the
/// view the finger first landed on, as level buttons do.
@MainActor
final class GlassSlider: NSView {
    var onChange: ((Float) -> Void)?
    var onTouchBegan: (() -> Void)?
    var onTouchEnded: (() -> Void)?

    private(set) var value: Float = 0
    private(set) var isTracking = false
    /// When the current touch last reported anything; lets the owner detect a lost touch.
    private(set) var lastTouchActivity = Date.distantPast

    var trackInset: CGFloat = 0 { didSet { needsLayout = true } }

    /// How VoiceOver reads `value`.
    var describeValue: (Float) -> String = GlassSlider.percentText

    /// `value` as a whole percentage, e.g. 45 %.
    nonisolated static func percentText(_ value: Float) -> String {
        Double(value).formatted(.percent.precision(.fractionLength(0)))
    }

    /// Finger-to-knob offset kept while dragging, so the knob never jumps under the finger.
    private var grabOffset: CGFloat = 0
    private var liquidTask: Task<Void, Never>?
    private var isMorphing = false

    private let track = CALayer()
    private let fill = CALayer()
    private let solidKnob = NSView()
    private let glassKnob = NSGlassEffectView()

    /// The blue of Apple's own sliders, in its dark-appearance variant (the Touch Bar is always dark).
    static let fillColor: CGColor = {
        var color = NSColor.systemBlue.cgColor
        NSAppearance(named: .darkAqua)?.performAsCurrentDrawingAppearance {
            color = NSColor.systemBlue.cgColor
        }
        return color
    }()

    private static let trackHeight: CGFloat = 6
    private static let restKnob = NSSize(width: 28, height: 20)
    private static let heldKnob = NSSize(width: 44, height: 28)
    private static let grabRadius: CGFloat = 30

    override init(frame: NSRect) {
        super.init(frame: frame)
        allowedTouchTypes = .direct
        wantsLayer = true

        track.backgroundColor = NSColor.white.withAlphaComponent(0.18).cgColor
        track.cornerRadius = Self.trackHeight / 2
        fill.backgroundColor = Self.fillColor
        fill.cornerRadius = Self.trackHeight / 2
        layer?.addSublayer(track)
        layer?.addSublayer(fill)

        solidKnob.wantsLayer = true
        solidKnob.layer?.backgroundColor = NSColor.white.cgColor
        solidKnob.layer?.cornerRadius = Self.restKnob.height / 2
        solidKnob.layer?.shadowColor = NSColor.black.cgColor
        solidKnob.layer?.shadowOpacity = 0.35
        solidKnob.layer?.shadowRadius = 3
        solidKnob.layer?.shadowOffset = .zero
        addSubview(solidKnob)

        glassKnob.style = .clear
        glassKnob.alphaValue = 0
        addSubview(glassKnob)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        layoutParts()
    }

    // MARK: - Public API

    /// Sets the value from outside (e.g. the volume changed elsewhere). Ignored mid-drag.
    func setValue(_ newValue: Float) {
        guard !isTracking else { return }
        value = Self.clamp(newValue)
        layoutParts()
    }

    /// Starts a drag. `relative` keeps the knob where it is and moves it 1:1 with the
    /// finger from here on (used when the touch began on a button); otherwise a touch
    /// away from the knob jumps it there first. The knob turns liquid after `liquidDelay`.
    func beginTracking(at x: CGFloat, relative: Bool, liquidDelay: Duration = .zero) {
        if relative || abs(x - knobX) <= Self.grabRadius {
            grabOffset = knobX - x
        } else {
            grabOffset = 0
            move(knobTo: x)
        }
        isTracking = true
        lastTouchActivity = Date()
        onTouchBegan?()

        liquidTask?.cancel()
        liquidTask = Task { [weak self] in
            if liquidDelay > .zero { try? await Task.sleep(for: liquidDelay) }
            guard let self, !Task.isCancelled, self.isTracking else { return }
            self.setLiquid(true)
        }
    }

    func continueTracking(at x: CGFloat) {
        guard isTracking else { return }
        lastTouchActivity = Date()
        move(knobTo: x + grabOffset)
    }

    func endTracking() {
        guard isTracking else { return }
        isTracking = false
        liquidTask?.cancel()
        setLiquid(false)
        onTouchEnded?()
    }

    // MARK: - Accessibility

    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { .slider }
    override func accessibilityValue() -> Any? { describeValue(value) }

    override func accessibilityPerformIncrement() -> Bool { nudge(by: 1) }
    override func accessibilityPerformDecrement() -> Bool { nudge(by: -1) }

    /// Moves the knob a 16th of the track, reported like a short drag.
    private func nudge(by notches: Float) -> Bool {
        guard !isTracking else { return false }
        onTouchBegan?()
        let newValue = Self.clamp(value + notches / 16)
        if newValue != value {
            value = newValue
            layoutParts()
            onChange?(value)
        }
        onTouchEnded?()
        return true
    }

    // MARK: - Touches landing on the slider itself

    override func touchesBegan(with event: NSEvent) {
        guard let touch = event.touches(matching: .began, in: self).first else { return }
        beginTracking(at: touch.location(in: self).x, relative: false)
    }

    override func touchesMoved(with event: NSEvent) {
        guard let touch = event.touches(matching: .moved, in: self).first else { return }
        continueTracking(at: touch.location(in: self).x)
    }

    override func touchesEnded(with event: NSEvent) { endTracking() }
    override func touchesCancelled(with event: NSEvent) { endTracking() }

    // MARK: - Geometry

    private var trackStart: CGFloat { trackInset }
    private var trackLength: CGFloat { max(bounds.width - 2 * trackInset, 1) }
    private var knobX: CGFloat { trackStart + CGFloat(value) * trackLength }

    private func move(knobTo x: CGFloat) {
        let newValue = Self.clamp(Float((x - trackStart) / trackLength))
        let changed = newValue != value
        value = newValue
        layoutParts()
        if changed { onChange?(value) }
    }

    private func layoutParts() {
        let trackY = (bounds.height - Self.trackHeight) / 2

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        track.frame = NSRect(x: trackStart, y: trackY, width: trackLength, height: Self.trackHeight)
        fill.frame = NSRect(x: trackStart, y: trackY, width: knobX - trackStart, height: Self.trackHeight)
        CATransaction.commit()

        solidKnob.frame = knobFrame(Self.restKnob)
        if isMorphing {
            // Keep the size animation running, just follow the finger.
            glassKnob.setFrameOrigin(NSPoint(x: knobX - glassKnob.frame.width / 2, y: glassKnob.frame.minY))
        } else {
            let size = glassKnob.alphaValue > 0 ? Self.heldKnob : Self.restKnob
            glassKnob.frame = knobFrame(size)
            // Runs on every move; the glass only needs reshaping when the size changed.
            if glassKnob.cornerRadius != size.height / 2 { glassKnob.cornerRadius = size.height / 2 }
        }
    }

    private func knobFrame(_ size: NSSize) -> NSRect {
        NSRect(x: knobX - size.width / 2, y: (bounds.height - size.height) / 2, width: size.width, height: size.height)
    }

    /// Solid at rest, a swollen clear-glass lens while held.
    private func setLiquid(_ liquid: Bool) {
        let size = liquid ? Self.heldKnob : Self.restKnob
        isMorphing = true
        glassKnob.cornerRadius = size.height / 2
        NSAnimationContext.runAnimationGroup { context in
            context.duration = liquid ? 0.14 : 0.28
            context.timingFunction = CAMediaTimingFunction(name: liquid ? .easeOut : .easeInEaseOut)
            glassKnob.animator().frame = knobFrame(size)
            glassKnob.animator().alphaValue = liquid ? 1 : 0
            solidKnob.animator().alphaValue = liquid ? 0 : 1
        } completionHandler: {
            MainActor.assumeIsolated {
                self.isMorphing = false
                self.layoutParts()
            }
        }
    }

    private static func clamp(_ value: Float) -> Float { min(max(value, 0), 1) }
}
