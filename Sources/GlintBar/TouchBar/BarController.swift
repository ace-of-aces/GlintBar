import AppKit

/// Owns GlintBar's system-wide Touch Bar: presenting it over every app, stepping aside
/// for an app's own controls, and keeping its items up to date. The sliders that pop out
/// of items are `SliderPanelController`'s.
@MainActor
final class BarController: NSObject, NSTouchBarDelegate {
    enum State { case glint, appControls }

    private(set) var state: State = .glint
    var onStateChange: (() -> Void)?

    /// False while the screens sleep or another user's session is in front. Nobody can see
    /// the bar then, so nothing on it is kept up to date.
    var isDisplayActive = true {
        didSet {
            guard isDisplayActive != oldValue else { return }
            if isDisplayActive { catchUp() }
            updateActivity()
        }
    }

    private static let barItemID = NSTouchBarItem.Identifier("center.julian.glintbar.bar")
    private static let trayItemID = NSTouchBarItem.Identifier("center.julian.glintbar.tray")

    private let touchBar = NSTouchBar()
    let barView = BarView()
    let panel: SliderPanelController
    private let trayItem = NSCustomTouchBarItem(identifier: BarController.trayItemID)
    private let trayGlyph = TrayGlyphView()

    private var isStarted = false
    /// Picks up what has no change notification (see `poll()`) while the bar can be seen.
    private var pollTimer: Timer?
    /// Turns the clock over on the minute.
    private var clockTimer: Timer?
    /// Moves the Now Playing line along while something plays.
    private var progressTimer: Timer?
    /// The views of the items on the bar (spacers have none).
    private(set) var itemViews: [BarItemKind: NSView] = [:]
    private var layoutKinds: [BarItemKind] = []
    private var frontmostApp: NSRunningApplication?

    override init() {
        panel = SliderPanelController(barView: barView)
        super.init()
        touchBar.delegate = self
        touchBar.defaultItemIdentifiers = [Self.barItemID]

        // No background of its own: the Control Strip draws its slot around it.
        trayGlyph.onTap = { [weak self] in self?.showGlint() }
        trayItem.view = trayGlyph

        panel.onLevelChange = { [weak self] level, value in
            (self?.itemViews[level.kind] as? GlassButton)?.showLevel(level, value: value)
        }
        AudioController.shared.onChange = { [weak self] in self?.audioChanged() }
        NowPlayingMonitor.shared.onChange = { [weak self] in self?.nowPlayingChanged() }
        Battery.shared.onChange = { [weak self] in self?.batteryChanged() }
        SystemResources.shared.onChange = { [weak self] in
            (self?.itemViews[.systemResources] as? SystemResourcesView)?.update(SystemResources.shared.usage)
        }
        BarConfiguration.shared.onChange = { [weak self] in self?.applyLayout() }
        DisplayBrightness.onChange = { [weak self] in self?.whileVisible { $0.updateLevels([.display]) } }
        DisplayBrightness.onDisplaysChange = { [weak self] in
            self?.whileVisible {
                $0.updateAvailability()
                $0.updateLevels([.display])
            }
        }
        NightShift.onChange = { [weak self] in self?.whileVisible { $0.updateNightShift() } }
        for name in [Notification.Name.NSSystemClockDidChange, .NSSystemTimeZoneDidChange] {
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.clockChanged() }
            }
        }
        frontmostApp = NSWorkspace.shared.frontmostApplication
        applyLayout()
    }

    // MARK: - Lifecycle

    func start() {
        TouchBarPrivate.addTrayItem(trayItem)
        DisplayBrightness.startObserving()
        NightShift.startObserving()
        NowPlayingMonitor.shared.start()
        Battery.shared.start()
        isStarted = true
        showGlint()
    }

    func stop() {
        isStarted = false
        updateActivity()
        NowPlayingMonitor.shared.stop()
        Battery.shared.stop()
        TouchBarPrivate.dismiss(touchBar)
        TouchBarPrivate.removeTrayItem(trayItem)
    }

    func showGlint() {
        state = .glint
        catchUp()
        TouchBarPrivate.present(touchBar, placement: .fullWidth, trayItem: Self.trayItemID)
        updateActivity()
        onStateChange?()
    }

    /// Steps aside so the frontmost app's own Touch Bar shows; the eclipse
    /// button in the Control Strip brings GlintBar back.
    func showAppControls() {
        panel.close(animated: false)
        state = .appControls
        updateActivity()
        TouchBarPrivate.minimize(touchBar)
        // The Control Strip forgets the tray item after a full-width bar; put it back.
        TouchBarPrivate.addTrayItem(trayItem)
        onStateChange?()
        // Glint once the button has settled into the Control Strip, so the way back is easy to spot.
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(450))
            guard let self, self.state == .appControls else { return }
            self.trayGlyph.playGlint()
        }
    }

    /// Re-presents the bar after events that can knock it off (wake, Space switch, …).
    func reassert() {
        guard state == .glint else { return }
        TouchBarPrivate.present(touchBar, placement: .fullWidth, trayItem: Self.trayItemID)
    }

    func frontmostAppChanged(_ app: NSRunningApplication?) {
        frontmostApp = app
        if let button = itemViews[.appControls] as? GlassButton { showFrontmostApp(on: button) }
    }

    func touchBar(_ touchBar: NSTouchBar, makeItemForIdentifier identifier: NSTouchBarItem.Identifier)
        -> NSTouchBarItem?
    {
        guard identifier == Self.barItemID else { return nil }
        let item = NSCustomTouchBarItem(identifier: identifier)
        item.view = barView
        return item
    }

    // MARK: - Doing only what can be seen

    private var isVisible: Bool { isStarted && state == .glint && isDisplayActive }

    /// Starts or stops the timers and sampling that only matter while the bar can be seen.
    private func updateActivity() {
        let visible = isVisible
        SystemResources.shared.setNeeded(visible && layoutKinds.contains(.systemResources), by: "bar")
        setTimer(&pollTimer, running: visible && needsPolling, interval: 1.5) { $0.poll() }
        setClockRunning(visible && layoutKinds.contains(.clock))
        NowPlayingMonitor.shared.isWatched =
            visible && (layoutKinds.contains(.nowPlaying) || layoutKinds.contains(.playPause))
        // A paused track's position doesn't move.
        let isPlaying = NowPlayingMonitor.shared.isPlaying == true
        setTimer(&progressTimer, running: visible && isPlaying && layoutKinds.contains(.nowPlaying), interval: 0.5) {
            $0.updatePlaybackProgress()
        }
    }

    private func setTimer(
        _ timer: inout Timer?, running: Bool, interval: TimeInterval,
        action: @escaping @MainActor @Sendable (BarController) -> Void
    ) {
        guard running != (timer != nil) else { return }
        timer?.invalidate()
        timer = nil
        guard running else { return }
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { if let self { action(self) } }
        }
        timer?.tolerance = interval / 10
    }

    /// What has no change notification of its own: the keyboard backlight (CoreBrightness
    /// doesn't report it to other processes), whether the output's volume can be changed,
    /// and apps that were removed from under their buttons.
    private func poll() {
        AudioController.shared.updateVolumeControl()
        updateAvailability()
        updateLevels([.keyboard])
    }

    /// Whether the configured items include any `poll()` keeps up to date. Hidden items
    /// count too: polling is how they come back.
    private var needsPolling: Bool {
        configuredKinds.contains { kind in
            guard kind.appURL == nil else { return true }
            let level = kind.level ?? kind.step?.level
            return level == .keyboard || level == .volume
        }
    }

    /// Runs `update` only while the bar can be seen; `catchUp()` covers the time out of sight.
    private func whileVisible(_ update: (BarController) -> Void) {
        if isVisible { update(self) }
    }

    private func setClockRunning(_ running: Bool) {
        guard running != (clockTimer != nil) else { return }
        clockTimer?.invalidate()
        clockTimer = nil
        if running { scheduleClockTick() }
    }

    private func scheduleClockTick() {
        clockTimer?.invalidate()
        let minute = (Date().timeIntervalSinceReferenceDate / 60).rounded(.down) * 60
        // Just past the turn, so the new minute is what's read.
        let timer = Timer(fire: Date(timeIntervalSinceReferenceDate: minute + 60.05), interval: 0, repeats: false) {
            [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                (self.itemViews[.clock] as? ClockView)?.update()
                self.scheduleClockTick()
            }
        }
        timer.tolerance = 0.1
        RunLoop.main.add(timer, forMode: .default)
        clockTimer = timer
    }

    /// The clock was set, or the time zone changed: the next minute is somewhere else.
    private func clockChanged() {
        guard clockTimer != nil else { return }
        (itemViews[.clock] as? ClockView)?.update()
        scheduleClockTick()
    }

    /// Brings everything up to date after a time out of sight.
    private func catchUp() {
        DisplayBrightness.updateBuiltInDisplay()
        AudioController.shared.updateVolumeControl()
        updateAvailability()
        updateAll()
    }

    // MARK: - Items

    /// Shows the configured items, minus controls this Mac can't use right now.
    private func applyLayout() {
        let kinds = visibleKinds
        var views: [BarItemKind: NSView] = [:]
        for kind in kinds where !kind.isSpacer {
            views[kind] = itemViews[kind] ?? makeItemView(kind)
        }
        // Views of items that left go with them, so nothing keeps updating them.
        itemViews = views
        layoutKinds = kinds
        barView.main.setLayout(kinds, views: views)
        if let content = panel.content, views[content.anchor] == nil { panel.close(animated: false) }
        updateAll()
        updateActivity()
    }

    /// Re-applies the layout when an item came or went (lid closed, output changed, …).
    private func updateAvailability() {
        if visibleKinds != layoutKinds { applyLayout() }
    }

    private var visibleKinds: [BarItemKind] {
        configuredKinds.filter(\.isAvailable)
    }

    /// What the bar would show if everything were available.
    private var configuredKinds: [BarItemKind] {
        let configuration = BarConfiguration.shared
        return configuration.previewKinds ?? configuration.kinds
    }

    func makeItemView(_ kind: BarItemKind) -> NSView {
        let view = makeUnlabeledItemView(kind)
        if let button = view as? GlassButton { button.setAccessibilityLabel(kind.level?.title ?? kind.title) }
        return view
    }

    private func makeUnlabeledItemView(_ kind: BarItemKind) -> NSView {
        switch kind {
        case .nowPlaying:
            let view = NowPlayingView(width: kind.width)
            view.onTap = Self.togglePlayback
            wireScrubbing(view)
            return view
        case .clock:
            return ClockView(width: kind.width)
        case .battery:
            return BatteryView(width: kind.width)
        case .systemResources:
            return SystemResourcesView(width: kind.width)
        case .app(let url?):
            let button = GlassButton(symbol: "app.dashed", width: kind.width)
            button.setImage(BarItemKind.icon(for: url))
            button.onTap = { SystemActions.launch(url) }
            return button
        default:
            break
        }

        let button = GlassButton(symbol: kind.symbol ?? "app.dashed", width: kind.width)
        if let level = kind.level {
            wireLevelButton(button, level: level)
            return button
        }
        if let step = kind.step {
            button.repeatsWhileHeld = true
            button.onTap = { [weak self] in self?.step(step.level, by: step.direction) }
            return button
        }
        button.onTap = { [weak self] in
            switch kind {
            case .appControls: self?.showAppControls()
            case .previousTrack: Media.send(.previousTrack)
            case .playPause: Self.togglePlayback()
            case .nextTrack: Media.send(.nextTrack)
            case .mute:
                AudioController.shared.isMuted.toggle()
                self?.updateAudio()
            case .screenshot: SystemActions.screenshot()
            case .missionControl: SystemActions.missionControl()
            case .apps: SystemActions.apps()
            case .spotlight: SystemActions.spotlight()
            case .showDesktop: SystemActions.showDesktop()
            case .inputSources: SystemActions.nextInputSource()
            case .quickActions: SystemActions.quickActions()
            case .lockScreen: SystemActions.lockScreen()
            case .screenSaver: SystemActions.screenSaver()
            case .sleep: SystemActions.sleep()
            case .siri: SystemActions.siri()
            case .nightShift:
                NightShift.toggle()
                self?.updateNightShift()
            default: break
            }
        }
        if kind == .appControls { showFrontmostApp(on: button) }
        return button
    }

    private func step(_ level: Level, by direction: Float) {
        level.step(direction)
        updateLevels([level])
    }

    private static func togglePlayback() {
        Media.send(.togglePlayPause)
        NowPlayingMonitor.shared.assumeToggled()
    }

    /// Like the native Control Strip: touching a level button pops its slider out of
    /// it straight away, and the same touch keeps dragging the knob (relative to where
    /// it is, so nothing jumps).
    private func wireLevelButton(_ button: GlassButton, level: Level) {
        button.onIncrement = { [weak self] in self?.step(level, by: 1) }
        button.onDecrement = { [weak self] in self?.step(level, by: -1) }
        button.onTouchDown = { [weak self, weak button] x in
            guard let self, let button else { return }
            self.panel.beginTouch(.level(level), at: x, on: button)
        }
        button.onTouchMoved = { [weak self, weak button] x in
            guard let self, let button else { return }
            self.panel.moveTouch(to: x, on: button)
        }
        button.onTouchUp = { [weak self] in self?.panel.endTouch() }
    }

    /// Pressing and sliding (or holding) on Now Playing pops a scrubber out of it; the
    /// song jumps to the new position when the finger lifts.
    private func wireScrubbing(_ view: NowPlayingView) {
        view.canScrub = { NowPlayingMonitor.shared.canSeek }
        view.onScrubBegan = { [weak self, weak view] x in
            guard let self, let view else { return }
            self.panel.beginTouch(.media, at: x, on: view)
        }
        view.onScrubMoved = { [weak self, weak view] x in
            guard let self, let view else { return }
            self.panel.moveTouch(to: x, on: view)
        }
        view.onScrubEnded = { [weak self] in self?.panel.endTouch() }
    }

    // MARK: - State → UI
    //
    // Each change updates only what it affects: most readings are a round trip to another
    // process (the audio server, CoreBrightness, the window server).

    private func updateAll() {
        updateLevels(Level.allCases)
        updateMute()
        updateNightShift()
        updateNowPlaying()
        (itemViews[.clock] as? ClockView)?.update()
        (itemViews[.battery] as? BatteryView)?.update()
    }

    private func audioChanged() {
        updateAvailability() // the new output may have no volume control
        updateAudio()
    }

    private func nowPlayingChanged() {
        updateNowPlaying()
        updateActivity() // the line only moves while something plays
    }

    private func batteryChanged() {
        updateAvailability()
        (itemViews[.battery] as? BatteryView)?.update()
    }

    /// Level buttons' icons, and the open slider unless a finger is on it.
    private func updateLevels(_ levels: [Level]) {
        for level in levels {
            let button = itemViews[level.kind] as? GlassButton
            let isOpen = panel.content == .level(level)
            guard button != nil || isOpen else { continue }
            // Mid-drag the button already shows the dragged value.
            if isOpen, panel.isTracking { continue }
            let value = level.value
            button?.showLevel(level, value: value)
            if isOpen { panel.setValue(value) }
        }
    }

    private func updateAudio() {
        updateLevels([.volume])
        updateMute()
    }

    private func updateMute() {
        (itemViews[.mute] as? GlassButton)?.isActive = AudioController.shared.isMuted
    }

    private func updateNightShift() {
        (itemViews[.nightShift] as? GlassButton)?.isActive = NightShift.isOn
    }

    private func updateNowPlaying() {
        let playSymbol =
            switch NowPlayingMonitor.shared.isPlaying {
            case true?: "pause.fill"
            case false?: "play.fill"
            case nil: "playpause.fill"
            }
        let playPause = itemViews[.playPause] as? GlassButton
        playPause?.setSymbol(playSymbol)
        playPause?.setAccessibilityValue(NowPlayingMonitor.shared.isPlaying.map { $0 ? "Playing" : "Paused" })
        updatePlaybackProgress()
    }

    /// The Now Playing widget's line, and the scrubber while it's open.
    private func updatePlaybackProgress() {
        let nowPlaying = NowPlayingMonitor.shared
        (itemViews[.nowPlaying] as? NowPlayingView)?.update(
            title: nowPlaying.title, artist: nowPlaying.artist, progress: nowPlaying.progress)
        panel.followPlayback()
    }

    private func showFrontmostApp(on button: GlassButton) {
        button.setAccessibilityValue(frontmostApp?.localizedName)
        guard let icon = frontmostApp?.icon else {
            button.setSymbol("app.dashed")
            return
        }
        button.setImage(BarItemKind.buttonIcon(icon))
    }
}

extension GlassButton {
    /// A level button's icon and spoken value at `value`.
    fileprivate func showLevel(_ level: Level, value: Float) {
        setSymbol(level.symbol(for: value))
        setAccessibilityValue(GlassSlider.percentText(value))
    }
}
