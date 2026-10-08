import AppKit

/// Track and artist in a glass capsule; tapping it toggles playback.
@MainActor
final class NowPlayingView: NSView {
    var onTap: (() -> Void)?

    private let glass = NSGlassEffectView()
    private let title = NSTextField(labelWithString: "")
    private let artist = NSTextField(labelWithString: "")
    private let width: CGFloat

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
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 14),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: content.trailingAnchor, constant: -14),
            stack.centerYAnchor.constraint(equalTo: content.centerYAnchor),
        ])
        glass.contentView = content
        addSubview(glass)
        update(title: nil, artist: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var intrinsicContentSize: NSSize { NSSize(width: width, height: BarMetrics.height) }

    func update(title: String?, artist: String?) {
        self.title.stringValue = title ?? "Not Playing"
        self.title.textColor = title == nil ? NSColor.white.withAlphaComponent(0.5) : .white
        self.artist.stringValue = artist ?? ""
        self.artist.isHidden = artist?.isEmpty ?? true
    }

    override func touchesBegan(with event: NSEvent) {
        glass.tintColor = NSColor.white.withAlphaComponent(0.28)
    }

    override func touchesEnded(with event: NSEvent) {
        glass.tintColor = nil
        onTap?()
    }

    override func touchesCancelled(with event: NSEvent) {
        glass.tintColor = nil
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
