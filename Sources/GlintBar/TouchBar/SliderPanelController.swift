import AppKit

/// The slider that pops out of a level button or Now Playing: opening it under the finger,
/// what moving it does, and closing it again on its own.
@MainActor
final class SliderPanelController {
    enum Content: Equatable {
        case level(Level)
        /// Scrubbing through the current track.
        case media

        /// The item the panel pops out of.
        @MainActor var anchor: BarItemKind {
            switch self {
            case .level(let level): level.kind
            case .media: .nowPlaying
            }
        }
    }

    private enum State {
        case closed
        /// A finger is on the slider, or on the item it popped out of.
        case held(Content)
        /// The finger lifted: the ✕ shows until the panel closes itself.
        case lingering(Content)

        var content: Content? {
            switch self {
            case .closed: nil
            case .held(let content), .lingering(let content): content
            }
        }
    }

    /// Called on every move of a level's slider, with the value just set.
    var onLevelChange: ((Level, Float) -> Void)?

    /// What the panel shows, if it's open.
    var content: Content? { state.content }

    /// Whether a finger is on the slider (or on the item it popped out of).
    var isTracking: Bool { slider.isTracking }

    private let barView: BarView
    private var slider: GlassSlider { barView.panel.slider }
    private var state = State.closed
    /// Closes a lingering panel, or watches a held one for a lost touch.
    private var timer: Timer?
    /// A drag that hasn't reported anything for this long is treated as lost
    /// (its touch-up never arrived), so the panel can't get stuck open.
    private static let lostTouchTimeout: TimeInterval = 10

    init(barView: BarView) {
        self.barView = barView
        let panel = barView.panel
        panel.closeButton.onTap = { [weak self] in self?.close() }
        panel.onOutsideTouch = { [weak self] in self?.close() }
        panel.slider.onChange = { [weak self] value in self?.sliderMoved(to: value) }
        panel.slider.onTouchBegan = { [weak self] in self?.touchBegan() }
        panel.slider.onTouchEnded = { [weak self] in self?.touchEnded() }
    }

    // MARK: - Touches from the item it pops out of

    /// Opens the panel from `anchor` for a finger that just landed on it at `x` (in
    /// `anchor`'s coordinates). The same touch keeps dragging the knob, relative to where
    /// it is, so nothing jumps.
    func beginTouch(_ content: Content, at x: CGFloat, on anchor: NSView) {
        open(content, from: anchor)
        slider.beginTracking(
            at: sliderX(x, from: anchor),
            relative: true,
            liquidDelay: .milliseconds(Int(SliderPanelView.popDuration * 1000))
        )
    }

    func moveTouch(to x: CGFloat, on anchor: NSView) {
        slider.continueTracking(at: sliderX(x, from: anchor))
    }

    func endTouch() {
        slider.endTracking()
    }

    /// Converts an x position in `view` to the slider's coordinate space.
    private func sliderX(_ x: CGFloat, from view: NSView) -> CGFloat {
        slider.convert(NSPoint(x: x, y: 0), from: view).x
    }

    // MARK: - Showing what changed elsewhere

    /// Sets the knob from outside (the level changed elsewhere). Ignored mid-drag.
    func setValue(_ value: Float) {
        slider.setValue(value)
    }

    /// Keeps the scrubber with the track while it's open and not held, and closes it once
    /// there's nothing to scrub.
    func followPlayback() {
        guard content == .media else { return }
        let nowPlaying = NowPlayingMonitor.shared
        guard nowPlaying.canSeek else {
            close() // the track ended or the player went away
            return
        }
        guard !slider.isTracking else { return }
        slider.setValue(nowPlaying.progress ?? 0)
        updateTimeLabels(position: nowPlaying.position() ?? 0)
    }

    // MARK: - Opening and closing

    private func open(_ content: Content, from anchor: NSView) {
        switch content {
        case .level(let level):
            slider.setAccessibilityLabel(level.title)
            slider.describeValue = GlassSlider.percentText
            barView.openPanel(
                from: anchor, placement: .besideAnchor,
                leading: .symbol(level.lowSymbol, size: 13), trailing: .symbol(level.highSymbol, size: 15),
                value: level.value
            )
        case .media:
            let nowPlaying = NowPlayingMonitor.shared
            let position = nowPlaying.position() ?? 0
            slider.setAccessibilityLabel("Playback Position")
            // E.g. "1:23 of 3:45".
            slider.describeValue = { value in
                let duration = NowPlayingMonitor.shared.duration ?? 0
                return "\(Self.timeText(Double(value) * duration)) of \(Self.timeText(duration))"
            }
            barView.openPanel(
                from: anchor, placement: .overAnchor,
                leading: .text(Self.timeText(position)),
                trailing: .text("-" + Self.timeText((nowPlaying.duration ?? 0) - position)),
                value: nowPlaying.progress ?? 0
            )
        }
        // The touch that opened it is on it.
        state = .held(content)
        watchForLostTouch()
    }

    func close(animated: Bool = true) {
        guard content != nil else { return }
        state = .closed
        timer?.invalidate()
        timer = nil
        slider.endTracking() // reports nothing now that it's closed
        barView.closePanel(animated: animated)
    }

    // MARK: - The slider

    private func sliderMoved(to value: Float) {
        switch content {
        case .level(let level)?:
            level.set(value)
            // Shown from the value just set: reading it back would ask another process
            // on every move. Volume changes also come back through AudioController.
            onLevelChange?(level, value)
        case .media?:
            // Only show where the song would jump to; seek once the finger lifts.
            updateTimeLabels(position: Double(value) * (NowPlayingMonitor.shared.duration ?? 0))
        case nil:
            break
        }
    }

    private func touchBegan() {
        guard let content else { return }
        state = .held(content)
        watchForLostTouch()
    }

    private func touchEnded() {
        guard let content else { return }
        if content == .media, let duration = NowPlayingMonitor.shared.duration {
            NowPlayingMonitor.shared.seek(to: Double(slider.value) * duration)
        }
        let delay = Settings.autoCloseDelay
        guard delay > 0 else {
            close()
            return
        }
        state = .lingering(content)
        barView.panel.showCloseButton()
        schedule(after: delay) { $0.close() }
    }

    /// While held, checks back when the touch would count as lost, and ends it if nothing
    /// was heard from it since.
    private func watchForLostTouch() {
        let slider = slider
        let idle = slider.isTracking ? Date().timeIntervalSince(slider.lastTouchActivity) : 0
        schedule(after: max(Self.lostTouchTimeout - idle, 0.1)) { panel in
            guard case .held = panel.state else { return }
            if !slider.isTracking {
                panel.touchEnded() // tracking ended without a word; close as if it had
            } else if Date().timeIntervalSince(slider.lastTouchActivity) >= Self.lostTouchTimeout {
                slider.endTracking() // reports the touch-up that never came
            } else {
                panel.watchForLostTouch()
            }
        }
    }

    private func schedule(
        after delay: TimeInterval, _ action: @escaping @MainActor @Sendable (SliderPanelController) -> Void
    ) {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { if let self { action(self) } }
        }
    }

    // MARK: - Time labels

    private func updateTimeLabels(position: Double) {
        let duration = NowPlayingMonitor.shared.duration ?? 0
        barView.panel.setAccessories(
            leading: .text(Self.timeText(position)),
            trailing: .text("-" + Self.timeText(duration - position))
        )
    }

    /// 3:07, or 1:02:33 past an hour.
    nonisolated static func timeText(_ seconds: Double) -> String {
        let total = max(Int(seconds.rounded(.down)), 0)
        let hours = total / 3600
        let minutes = total % 3600 / 60
        let secs = total % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, secs) : String(format: "%d:%02d", minutes, secs)
    }
}
