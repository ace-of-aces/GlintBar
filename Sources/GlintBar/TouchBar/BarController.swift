import AppKit

/// Owns GlintBar's system-wide Touch Bar: presenting it over every app,
/// stepping aside for an app's own controls, and the self-closing sliders.
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
    private let barView = BarView()
    private let trayItem = NSCustomTouchBarItem(identifier: BarController.trayItemID)
    private let trayGlyph = TrayGlyphView()

    private var isStarted = false
    /// Picks up what has no change notification (brightness, Night Shift, the clock,
    /// items coming and going) while the bar can be seen.
    private var pollTimer: Timer?
    /// Moves the Now Playing line along while something plays.
    private var progressTimer: Timer?
    /// The views of the items on the bar (spacers have none).
    private var itemViews: [BarItemKind: NSView] = [:]
    private var layoutKinds: [BarItemKind] = []
    private var frontmostApp: NSRunningApplication?

    // Slider panel state.
    private enum PanelContent: Equatable {
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
    private enum PanelState {
        case closed
        /// A finger is on the slider, or on the item it popped out of.
        case held(PanelContent)
        /// The finger lifted: the ✕ shows until the panel closes itself.
        case lingering(PanelContent)

        var content: PanelContent? {
            switch self {
            case .closed: nil
            case .held(let content), .lingering(let content): content
            }
        }
    }
    private var panelState = PanelState.closed
    /// Closes a lingering panel, or watches a held one for a lost touch.
    private var panelTimer: Timer?
    /// A drag that hasn't reported anything for this long is treated as lost
    /// (its touch-up never arrived), so the panel can't get stuck open.
    private static let lostTouchTimeout: TimeInterval = 10

    override init() {
        super.init()
        touchBar.delegate = self
        touchBar.defaultItemIdentifiers = [Self.barItemID]

        // No background of its own: the Control Strip draws its slot around it.
        trayGlyph.onTap = { [weak self] in self?.showGlint() }
        trayItem.view = trayGlyph

        wirePanel()
        AudioController.shared.onChange = { [weak self] in self?.audioChanged() }
        NowPlayingMonitor.shared.onChange = { [weak self] in self?.nowPlayingChanged() }
        Battery.shared.onChange = { [weak self] in self?.batteryChanged() }
        SystemResources.shared.onChange = { [weak self] in
            (self?.itemViews[.systemResources] as? SystemResourcesView)?.update(SystemResources.shared.usage)
        }
        BarConfiguration.shared.onChange = { [weak self] in self?.applyLayout() }
        frontmostApp = NSWorkspace.shared.frontmostApplication
        applyLayout()
    }

    // MARK: - Lifecycle

    func start() {
        TouchBarPrivate.addTrayItem(trayItem)
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
        closePanel(animated: false)
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

    func touchBar(_ touchBar: NSTouchBar, makeItemForIdentifier identifier: NSTouchBarItem.Identifier) -> NSTouchBarItem? {
        guard identifier == Self.barItemID else { return nil }
        let item = NSCustomTouchBarItem(identifier: identifier)
        item.view = barView
        return item
    }

    #if DEBUG
    private var debugButton: GlassButton?

    /// Simulates a finger on a level button with bar x positions — `down:volume`
    /// (or `down:volume:850`), `move:700`, `up`, `tap:display` — plus `close`,
    /// `appControls` and `glint`; `press:<item>` taps any button item, e.g. `press:volumeUp`.
    func debug(_ command: String) {
        let parts = command.split(separator: ":").map(String.init)
        func button(for name: String) -> GlassButton {
            let level = Level.allCases.first { "\($0)" == name } ?? .volume
            return itemViews[level.kind] as? GlassButton ?? GlassButton(symbol: "questionmark")
        }
        func local(_ barX: String?, in button: GlassButton) -> CGFloat {
            guard let barX, let x = Double(barX) else { return button.bounds.midX }
            return button.convert(NSPoint(x: x, y: 0), from: barView).x
        }
        switch parts.first {
        case "down", "tap":
            let target = button(for: parts.count > 1 ? parts[1] : "volume")
            debugButton = target
            target.onTouchDown?(local(parts.count > 2 ? parts[2] : nil, in: target))
            if parts.first == "tap" { target.onTouchUp?() }
        case "move":
            guard let target = debugButton else { return }
            target.onTouchMoved?(local(parts.count > 1 ? parts[1] : nil, in: target))
        case "up":
            debugButton?.onTouchUp?()
        case "scrub":
            // scrub:down · scrub:move:<bar x> · scrub:up — a finger on the Now Playing widget.
            guard let view = itemViews[.nowPlaying] as? NowPlayingView else { return }
            let x = parts.count > 2 ? view.convert(NSPoint(x: Double(parts[2]) ?? 0, y: 0), from: barView).x : view.bounds.midX
            switch parts.count > 1 ? parts[1] : "" {
            case "down": view.onScrubBegan?(x)
            case "move": view.onScrubMoved?(x)
            default: view.onScrubEnded?()
            }
        case "press":
            guard parts.count > 1, let kind = BarItemKind(rawValue: parts[1]) else { return }
            ((itemViews[kind] ?? makeItemView(kind)) as? GlassButton)?.onTap?()
        case "battery":
            // battery:<percent>[:charging|:power] fakes the battery; battery:real undoes it.
            let percent = parts.count > 1 ? Int(parts[1]) : nil
            let power = parts.count > 2 ? parts[2] : ""
            Battery.shared.debugOverride(percent.map {
                Battery.State(percent: $0, isCharging: power == "charging", isOnPower: power == "charging" || power == "power")
            })
        case "resources":
            // resources:<cpu>:<gpu>:<memory>:<storage> in percent fakes the readings; resources:real undoes it.
            let percents = parts.dropFirst().map { Double($0).map { $0 / 100 } }
            SystemResources.shared.debugOverride(percents.count == 4 ? SystemResources.Usage(
                cpu: percents[0], gpu: percents[1], memory: percents[2], storage: percents[3]
            ) : nil)
        case "customize": CustomizeWindowController.shared.show()
        case "cdrag":
            // cdrag:bar:<index> · cdrag:palette:<kind> · cdrag:to:<bar x> · cdrag:off · cdrag:drop
            let driver = CustomizeDebugDriver.shared
            switch parts.count > 1 ? parts[1] : "" {
            case "bar": driver.perform(.pickUpBarItem(index: Int(parts[2]) ?? 0))
            case "palette": (parts[2] == "app" ? .app(nil) : BarItemKind(rawValue: parts[2])).map { driver.perform(.pickUpPaletteItem($0)) }
            case "to": driver.perform(.moveOverBar(x: CGFloat(Double(parts[2]) ?? 0)))
            case "off": driver.perform(.moveOffBar)
            default: driver.perform(.drop)
            }
        case "snapshot": CustomizeWindowController.shared.debugSnapshot(to: parts.count > 1 ? parts[1...].joined(separator: ":") : "/tmp/glint-customize.png")
        case "close": closePanel()
        case "appControls": showAppControls()
        case "glint": showGlint()
        default: NSLog("GlintBar: unknown debug command \(command)")
        }
    }
    #endif

    // MARK: - Doing only what can be seen

    private var isVisible: Bool { isStarted && state == .glint && isDisplayActive }

    /// Starts or stops the timers and sampling that only matter while the bar can be seen.
    private func updateActivity() {
        let visible = isVisible
        SystemResources.shared.setNeeded(visible && layoutKinds.contains(.systemResources), by: "bar")
        setTimer(&pollTimer, running: visible, interval: 1.5) { $0.poll() }
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

    /// What has no change notification of its own.
    private func poll() {
        DisplayBrightness.updateBuiltInDisplay()
        AudioController.shared.updateVolumeControl()
        updateAvailability()
        updateLevels([.keyboard, .display])
        updateNightShift()
        (itemViews[.clock] as? ClockView)?.update()
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
        if let content = panelState.content, views[content.anchor] == nil { closePanel(animated: false) }
        updateAll()
        updateActivity()
    }

    /// Re-applies the layout when an item came or went (lid closed, output changed, …).
    private func updateAvailability() {
        if visibleKinds != layoutKinds { applyLayout() }
    }

    private var visibleKinds: [BarItemKind] {
        let configuration = BarConfiguration.shared
        return (configuration.previewKinds ?? configuration.kinds).filter(\.isAvailable)
    }

    private func makeItemView(_ kind: BarItemKind) -> NSView {
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
            button.onTap = { [weak self] in
                step.level.step(step.direction)
                self?.updateLevels([step.level])
            }
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

    private static func togglePlayback() {
        Media.send(.togglePlayPause)
        NowPlayingMonitor.shared.assumeToggled()
    }

    /// Like the native Control Strip: touching a level button pops its slider out of
    /// it straight away, and the same touch keeps dragging the knob (relative to where
    /// it is, so nothing jumps).
    private func wireLevelButton(_ button: GlassButton, level: Level) {
        button.onTouchDown = { [weak self, weak button] x in
            guard let self, let button else { return }
            self.openPanel(.level(level), from: button)
            self.beginPanelTracking(at: x, from: button)
        }
        button.onTouchMoved = { [weak self, weak button] x in
            guard let self, let button else { return }
            self.barView.panel.slider.continueTracking(at: self.sliderX(x, from: button))
        }
        button.onTouchUp = { [weak self] in self?.barView.panel.slider.endTracking() }
    }

    /// Pressing and sliding (or holding) on Now Playing pops a scrubber out of it; the
    /// song jumps to the new position when the finger lifts.
    private func wireScrubbing(_ view: NowPlayingView) {
        view.canScrub = { NowPlayingMonitor.shared.canSeek }
        view.onScrubBegan = { [weak self, weak view] x in
            guard let self, let view else { return }
            self.openPanel(.media, from: view)
            self.beginPanelTracking(at: x, from: view)
        }
        view.onScrubMoved = { [weak self, weak view] x in
            guard let self, let view else { return }
            self.barView.panel.slider.continueTracking(at: self.sliderX(x, from: view))
        }
        view.onScrubEnded = { [weak self] in self?.barView.panel.slider.endTracking() }
    }

    private func beginPanelTracking(at x: CGFloat, from view: NSView) {
        barView.panel.slider.beginTracking(
            at: sliderX(x, from: view),
            relative: true,
            liquidDelay: .milliseconds(Int(SliderPanelView.popDuration * 1000))
        )
    }

    private func wirePanel() {
        let panel = barView.panel
        panel.closeButton.onTap = { [weak self] in self?.closePanel() }
        panel.onOutsideTouch = { [weak self] in self?.closePanel() }
        panel.slider.onChange = { [weak self] value in
            guard let self else { return }
            switch self.panelState.content {
            case .level(let level)?:
                level.set(value)
                // Shown from the value just set: reading it back would ask another process
                // on every move. Volume changes also come back through AudioController.
                (self.itemViews[level.kind] as? GlassButton)?.setSymbol(level.symbol(for: value))
            case .media?:
                // Only show where the song would jump to; seek once the finger lifts.
                self.updateTimeLabels(position: Double(value) * (NowPlayingMonitor.shared.duration ?? 0))
            case nil:
                break
            }
        }
        panel.slider.onTouchBegan = { [weak self] in self?.panelTouchBegan() }
        panel.slider.onTouchEnded = { [weak self] in self?.panelTouchEnded() }
    }

    /// Converts an x position in `view` to the slider's coordinate space.
    private func sliderX(_ x: CGFloat, from view: NSView) -> CGFloat {
        barView.panel.slider.convert(NSPoint(x: x, y: 0), from: view).x
    }

    // MARK: - Slider panel

    private func openPanel(_ content: PanelContent, from anchor: NSView) {
        switch content {
        case .level(let level):
            barView.openPanel(
                from: anchor, placement: .besideAnchor,
                leading: .symbol(level.lowSymbol, size: 13), trailing: .symbol(level.highSymbol, size: 15),
                value: level.value
            )
        case .media:
            let nowPlaying = NowPlayingMonitor.shared
            let position = nowPlaying.position() ?? 0
            barView.openPanel(
                from: anchor, placement: .overAnchor,
                leading: .text(Self.timeText(position)),
                trailing: .text("-" + Self.timeText((nowPlaying.duration ?? 0) - position)),
                value: nowPlaying.progress ?? 0
            )
        }
        // The touch that opened it is on it.
        panelState = .held(content)
        watchForLostTouch()
    }

    private func panelTouchBegan() {
        guard let content = panelState.content else { return }
        panelState = .held(content)
        watchForLostTouch()
    }

    private func panelTouchEnded() {
        guard let content = panelState.content else { return }
        if content == .media, let duration = NowPlayingMonitor.shared.duration {
            NowPlayingMonitor.shared.seek(to: Double(barView.panel.slider.value) * duration)
        }
        let delay = Settings.autoCloseDelay
        guard delay > 0 else {
            closePanel()
            return
        }
        panelState = .lingering(content)
        barView.panel.showCloseButton()
        schedulePanelTimer(after: delay) { $0.closePanel() }
    }

    /// While held, checks back when the touch would count as lost, and ends it if nothing
    /// was heard from it since.
    private func watchForLostTouch() {
        let slider = barView.panel.slider
        let idle = slider.isTracking ? Date().timeIntervalSince(slider.lastTouchActivity) : 0
        schedulePanelTimer(after: max(Self.lostTouchTimeout - idle, 0.1)) { bar in
            guard case .held = bar.panelState else { return }
            if !slider.isTracking {
                bar.panelTouchEnded() // tracking ended without a word; close as if it had
            } else if Date().timeIntervalSince(slider.lastTouchActivity) >= Self.lostTouchTimeout {
                slider.endTracking() // reports the touch-up that never came
            } else {
                bar.watchForLostTouch()
            }
        }
    }

    private func schedulePanelTimer(after delay: TimeInterval, _ action: @escaping @MainActor @Sendable (BarController) -> Void) {
        panelTimer?.invalidate()
        panelTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { if let self { action(self) } }
        }
    }

    private func closePanel(animated: Bool = true) {
        guard panelState.content != nil else { return }
        panelState = .closed
        panelTimer?.invalidate()
        panelTimer = nil
        barView.panel.slider.endTracking() // reports nothing now that it's closed
        barView.closePanel(animated: animated)
    }

    private func updateTimeLabels(position: Double) {
        let duration = NowPlayingMonitor.shared.duration ?? 0
        barView.panel.setAccessories(
            leading: .text(Self.timeText(position)),
            trailing: .text("-" + Self.timeText(duration - position))
        )
    }

    /// 3:07, or 1:02:33 past an hour.
    private static func timeText(_ seconds: Double) -> String {
        let total = max(Int(seconds.rounded(.down)), 0)
        let hours = total / 3600, minutes = total % 3600 / 60, secs = total % 60
        return hours > 0 ? String(format: "%d:%02d:%02d", hours, minutes, secs) : String(format: "%d:%02d", minutes, secs)
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
            let isOpen = panelState.content == .level(level)
            guard button != nil || isOpen else { continue }
            // Mid-drag the button already shows the dragged value.
            if isOpen, barView.panel.slider.isTracking { continue }
            let value = level.value
            button?.setSymbol(level.symbol(for: value))
            if isOpen { barView.panel.slider.setValue(value) }
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
        let playSymbol = switch NowPlayingMonitor.shared.isPlaying {
        case true?: "pause.fill"
        case false?: "play.fill"
        case nil: "playpause.fill"
        }
        (itemViews[.playPause] as? GlassButton)?.setSymbol(playSymbol)
        updatePlaybackProgress()
    }

    /// The Now Playing widget's line, and the scrubber while it's open and not held.
    private func updatePlaybackProgress() {
        let nowPlaying = NowPlayingMonitor.shared
        (itemViews[.nowPlaying] as? NowPlayingView)?.update(title: nowPlaying.title, artist: nowPlaying.artist, progress: nowPlaying.progress)
        guard panelState.content == .media else { return }
        guard nowPlaying.canSeek else {
            closePanel() // the track ended or the player went away
            return
        }
        let slider = barView.panel.slider
        guard !slider.isTracking else { return }
        slider.setValue(nowPlaying.progress ?? 0)
        updateTimeLabels(position: nowPlaying.position() ?? 0)
    }

    private func showFrontmostApp(on button: GlassButton) {
        guard let icon = frontmostApp?.icon else {
            button.setSymbol("app.dashed")
            return
        }
        button.setImage(BarItemKind.buttonIcon(icon))
    }
}
