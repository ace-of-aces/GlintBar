import AppKit

/// Track and artist in a glass capsule with a thin progress line along the bottom.
/// Tapping toggles playback; pressing and sliding, or pressing and holding, starts a
/// scrub, reported (with every move) in this view's coordinates.
@MainActor
final class NowPlayingView: NSView {
    var onTap: (() -> Void)?
    /// Whether a scrub may start (a track with a known length is playing).
    var canScrub: () -> Bool = { false }
    var onScrubBegan: ((CGFloat) -> Void)?
    var onScrubMoved: ((CGFloat) -> Void)?
    var onScrubEnded: (() -> Void)?

    private let glass = NSGlassEffectView()
    private let title = NSTextField(labelWithString: "")
    private let artist = NSTextField(labelWithString: "")
    private let progressTrack = CALayer()
    private let progressFill = CALayer()
    private let width: CGFloat

    private var touchStartX: CGFloat = 0
    private var isScrubbing = false
    private var holdTask: Task<Void, Never>?
    private static let slideThreshold: CGFloat = 8
    private static let holdDelay: Duration = .milliseconds(350)
    private static let progressInset: CGFloat = 15 // keeps the line on the capsule's straight edge

    init(width: CGFloat) {
        self.width = width
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: BarMetrics.height))
        allowedTouchTypes = .direct

        glass.cornerRadius = BarMetrics.height / 2
        glass.frame = bounds
        glass.autoresizingMask = [.width, .height]

        title.font = .systemFont(ofSize: 11.5, weight: .semibold)
        title.textColor = .white
        artist.font = .systemFont(ofSize: 10, weight: .regular)
        artist.textColor = NSColor.white.withAlphaComponent(0.65)
        let stack = NSStackView(views: [title, artist])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = -1
        for label in [title, artist] {
            label.lineBreakMode = .byTruncatingTail
            label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        }
        let content = NSView()
        content.wantsLayer = true
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 14),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: content.trailingAnchor, constant: -14),
            // Nudged up to leave room for the progress line.
            stack.centerYAnchor.constraint(equalTo: content.centerYAnchor, constant: -1.5),
        ])

        progressTrack.backgroundColor = NSColor.white.withAlphaComponent(0.18).cgColor
        progressFill.backgroundColor = GlassSlider.fillColor
        for line in [progressTrack, progressFill] {
            line.cornerRadius = 1
            content.layer?.addSublayer(line)
        }

        glass.contentView = content
        addSubview(glass)
        update(title: nil, artist: nil, progress: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var intrinsicContentSize: NSSize { NSSize(width: width, height: BarMetrics.height) }

    func update(title: String?, artist: String?, progress: Float?) {
        self.title.stringValue = title ?? "Not Playing"
        self.title.textColor = title == nil ? NSColor.white.withAlphaComponent(0.5) : .white
        self.artist.stringValue = artist ?? ""
        self.artist.isHidden = artist?.isEmpty ?? true

        let length = width - 2 * Self.progressInset
        let fraction = CGFloat(min(max(progress ?? 0, 0), 1))
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        progressTrack.frame = NSRect(x: Self.progressInset, y: 2.5, width: length, height: 2)
        progressFill.frame = NSRect(x: Self.progressInset, y: 2.5, width: length * fraction, height: 2)
        progressTrack.isHidden = progress == nil
        progressFill.isHidden = progress == nil
        CATransaction.commit()
    }

    // MARK: - Touches

    override func touchesBegan(with event: NSEvent) {
        guard let touch = event.touches(matching: .began, in: self).first else { return }
        touchStartX = touch.location(in: self).x
        isScrubbing = false
        glass.tintColor = NSColor.white.withAlphaComponent(0.28)
        holdTask = Task { [weak self] in
            try? await Task.sleep(for: Self.holdDelay)
            guard let self, !Task.isCancelled else { return }
            self.beginScrub()
        }
    }

    override func touchesMoved(with event: NSEvent) {
        guard let touch = event.touches(matching: .moved, in: self).first else { return }
        let x = touch.location(in: self).x
        if !isScrubbing, abs(x - touchStartX) > Self.slideThreshold { beginScrub() }
        if isScrubbing { onScrubMoved?(x) }
    }

    override func touchesEnded(with event: NSEvent) {
        let wasScrubbing = finishTouch()
        if wasScrubbing { onScrubEnded?() } else { onTap?() }
    }

    override func touchesCancelled(with event: NSEvent) {
        if finishTouch() { onScrubEnded?() }
    }

    private func beginScrub() {
        holdTask?.cancel()
        guard !isScrubbing, canScrub() else { return }
        isScrubbing = true
        glass.tintColor = nil
        // From where the finger landed, so the movement that started the scrub counts.
        onScrubBegan?(touchStartX)
    }

    /// Returns whether the touch was a scrub.
    private func finishTouch() -> Bool {
        holdTask?.cancel()
        glass.tintColor = nil
        defer { isScrubbing = false }
        return isScrubbing
    }
}

/// The time, as plain text.
@MainActor
final class ClockView: NSView {
    private let label = NSTextField(labelWithString: "")
    private let width: CGFloat
    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter
    }()

    static func text(for date: Date) -> String { formatter.string(from: date) }

    init(width: CGFloat) {
        self.width = width
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: BarMetrics.height))
        label.font = .monospacedDigitSystemFont(ofSize: 15, weight: .semibold)
        label.textColor = .white
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: centerXAnchor),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        update()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var intrinsicContentSize: NSSize { NSSize(width: width, height: BarMetrics.height) }

    func update() {
        let text = Self.text(for: Date())
        if label.stringValue != text { label.stringValue = text }
    }
}

/// The battery's charge as a percentage next to a battery glyph, like the menu bar.
@MainActor
final class BatteryView: NSView {
    private let label = NSTextField(labelWithString: "")
    private let glyph = NSImageView()
    private let width: CGFloat
    private var shown: Battery.State?

    static func text(for state: Battery.State) -> String {
        (Double(state.percent) / 100).formatted(.percent)
    }

    init(width: CGFloat) {
        self.width = width
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: BarMetrics.height))
        label.font = .monospacedDigitSystemFont(ofSize: 13, weight: .semibold)
        label.textColor = .white
        glyph.imageScaling = .scaleNone
        let stack = NSStackView(views: [label, glyph])
        stack.spacing = 5
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        update()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var intrinsicContentSize: NSSize { NSSize(width: width, height: BarMetrics.height) }

    func update() {
        guard let state = Battery.shared.state, state != shown else { return }
        shown = state
        label.stringValue = Self.text(for: state)
        glyph.image = BatteryGlyph.image(for: state)
    }
}
