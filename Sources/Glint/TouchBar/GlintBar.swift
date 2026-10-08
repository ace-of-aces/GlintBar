import AppKit

/// Owns the system-wide Glint Touch Bar: presenting it over every app,
/// stepping aside for an app's own controls, and the self-closing sliders.
@MainActor
final class GlintBar: NSObject, NSTouchBarDelegate {
    enum State { case glint, appControls }

    private(set) var state: State = .glint
    var onStateChange: (() -> Void)?

    private static let barItemID = NSTouchBarItem.Identifier("center.julian.glint.bar")
    private static let trayItemID = NSTouchBarItem.Identifier("center.julian.glint.tray")

    private let touchBar = NSTouchBar()
    private let barView = BarView()
    private let trayItem = NSCustomTouchBarItem(identifier: GlintBar.trayItemID)

    private var pollTimer: Timer?
    /// One view per item kind in use (spacers have none), created on demand.
    private var itemViews: [BarItemKind: NSView] = [:]
    private var frontmostApp: NSRunningApplication?

    // Level panel state.
    private var activeLevel: Level?
    /// When the open panel closes itself; nil while a finger is on it.
    private var closeDeadline: Date?
    private var panelTimer: Timer?
    /// A drag that hasn't reported anything for this long is treated as lost
    /// (its touch-up never arrived), so the panel can't get stuck open.
    private static let lostTouchTimeout: TimeInterval = 10

    override init() {
        super.init()
        touchBar.delegate = self
        touchBar.defaultItemIdentifiers = [Self.barItemID]

        // A plain button: the Control Strip draws its own slot background around it.
        let trayButton = NSButton(
            image: NSImage(systemSymbolName: "sparkles", accessibilityDescription: "Glint")!,
            target: self,
            action: #selector(trayTapped)
        )
        trayButton.isBordered = false
        trayItem.view = trayButton

        wirePanel()
        AudioController.shared.onChange = { [weak self] in self?.refresh() }
        NowPlayingMonitor.shared.onChange = { [weak self] in self?.refresh() }
        BarConfiguration.shared.onChange = { [weak self] in self?.applyLayout() }
        frontmostApp = NSWorkspace.shared.frontmostApplication
        applyLayout()
    }

    // MARK: - Lifecycle

    func start() {
        TouchBarPrivate.addTrayItem(trayItem)
        NowPlayingMonitor.shared.start()
        showGlint()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            // Brightness has no change notification we can use.
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    func stop() {
        pollTimer?.invalidate()
        NowPlayingMonitor.shared.stop()
        TouchBarPrivate.dismiss(touchBar)
        TouchBarPrivate.removeTrayItem(trayItem)
    }

    func showGlint() {
        state = .glint
        refresh()
        TouchBarPrivate.present(touchBar, placement: .fullWidth, trayItem: Self.trayItemID)
        onStateChange?()
    }

    /// Steps aside so the frontmost app's own Touch Bar shows; the sparkles
    /// button in the Control Strip brings Glint back.
    func showAppControls() {
        closePanel(animated: false)
        state = .appControls
        TouchBarPrivate.minimize(touchBar)
        // The Control Strip forgets the tray item after a full-width bar; put it back.
        TouchBarPrivate.addTrayItem(trayItem)
        onStateChange?()
    }

    /// Re-presents the bar after events that can knock it off (wake, Space switch, …).
    func reassert() {
        guard state == .glint else { return }
        TouchBarPrivate.present(touchBar, placement: .fullWidth, trayItem: Self.trayItemID)
    }

    @objc private func trayTapped() {
        showGlint()
    }

    func frontmostAppChanged(_ app: NSRunningApplication?) {
        frontmostApp = app
        updateAppButton()
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
    /// `appControls` and `glint`.
    func debug(_ command: String) {
        let parts = command.split(separator: ":").map(String.init)
        func button(for name: String) -> GlassButton {
            let kind: BarItemKind = switch name {
            case "keyboard": .keyboardBrightness
            case "display": .displayBrightness
            default: .volume
            }
            return itemViews[kind] as? GlassButton ?? GlassButton(symbol: "questionmark")
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
        case "customize": CustomizeWindowController.shared.show()
        case "cdrag":
            // cdrag:bar:<index> · cdrag:palette:<kind> · cdrag:to:<bar x> · cdrag:off · cdrag:drop
            let driver = CustomizeDebugDriver.shared
            switch parts.count > 1 ? parts[1] : "" {
            case "bar": driver.perform(.pickUpBarItem(index: Int(parts[2]) ?? 0))
            case "palette": BarItemKind(rawValue: parts[2]).map { driver.perform(.pickUpPaletteItem($0)) }
            case "to": driver.perform(.moveOverBar(x: CGFloat(Double(parts[2]) ?? 0)))
            case "off": driver.perform(.moveOffBar)
            default: driver.perform(.drop)
            }
        case "snapshot": CustomizeWindowController.shared.debugSnapshot(to: parts.count > 1 ? parts[1...].joined(separator: ":") : "/tmp/glint-customize.png")
        case "close": closePanel()
        case "appControls": showAppControls()
        case "glint": showGlint()
        default: NSLog("Glint: unknown debug command \(command)")
        }
    }
    #endif

    // MARK: - Wiring

    // MARK: - Items

    /// Shows the configured items, minus controls this Mac can't use right now
    /// (no keyboard backlight, lid closed, an output without volume control).
    private func applyLayout() {
        let kinds = visibleKinds
        var views: [BarItemKind: NSView] = [:]
        for kind in kinds where !kind.isSpacer {
            views[kind] = itemView(for: kind)
        }
        barView.main.setLayout(kinds, views: views)
        layoutKinds = kinds
        refresh()
    }

    private var layoutKinds: [BarItemKind] = []

    private var visibleKinds: [BarItemKind] {
        let configuration = BarConfiguration.shared
        return (configuration.previewKinds ?? configuration.kinds).filter { $0.level?.isAvailable ?? true }
    }

    private func itemView(for kind: BarItemKind) -> NSView {
        if let view = itemViews[kind] { return view }
        let view = makeItemView(kind)
        itemViews[kind] = view
        return view
    }

    private func makeItemView(_ kind: BarItemKind) -> NSView {
        switch kind {
        case .nowPlaying:
            let view = NowPlayingView(width: kind.width)
            view.onTap = Self.togglePlayback
            return view
        case .clock:
            return ClockView(width: kind.width)
        default:
            break
        }

        let button = GlassButton(symbol: kind.symbol ?? "app.dashed", width: kind.width)
        if let level = kind.level {
            wireLevelButton(button, level: level)
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
                self?.refresh()
            case .screenshot: SystemActions.screenshot()
            case .missionControl: SystemActions.missionControl()
            case .apps: SystemActions.apps()
            case .lockScreen: SystemActions.lockScreen()
            default: break
            }
        }
        if kind == .appControls {
            itemViews[kind] = button
            updateAppButton()
        }
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
            self.openPanel(level, from: button)
            self.barView.panel.slider.beginTracking(
                at: self.sliderX(x, from: button),
                relative: true,
                liquidDelay: .milliseconds(Int(LevelPanelView.popDuration * 1000))
            )
        }
        button.onTouchMoved = { [weak self, weak button] x in
            guard let self, let button else { return }
            self.barView.panel.slider.continueTracking(at: self.sliderX(x, from: button))
        }
        button.onTouchUp = { [weak self] in self?.barView.panel.slider.endTracking() }
    }

    private func wirePanel() {
        let panel = barView.panel
        panel.closeButton.onTap = { [weak self] in self?.closePanel() }
        panel.onOutsideTouch = { [weak self] in self?.closePanel() }
        panel.slider.onChange = { [weak self] value in
            self?.activeLevel?.set(value)
            self?.refresh()
        }
        panel.slider.onTouchBegan = { [weak self] in self?.closeDeadline = nil }
        panel.slider.onTouchEnded = { [weak self] in
            guard let self, self.activeLevel != nil else { return }
            let delay = Settings.autoCloseDelay
            guard delay > 0 else {
                self.closePanel()
                return
            }
            self.closeDeadline = Date() + delay
            self.barView.panel.showCloseButton()
        }
    }

    /// Converts an x position in `view` to the slider's coordinate space.
    private func sliderX(_ x: CGFloat, from view: NSView) -> CGFloat {
        barView.panel.slider.convert(NSPoint(x: x, y: 0), from: view).x
    }

    // MARK: - Level panel

    private func openPanel(_ level: Level, from button: GlassButton) {
        activeLevel = level
        closeDeadline = nil
        barView.openPanel(level, from: button)
        refresh()

        // Closing is driven by a deadline checked several times a second rather than a
        // one-shot timer, so a missed or reordered touch event can't leave it open.
        panelTimer?.invalidate()
        panelTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.panelTick() }
        }
    }

    private func panelTick() {
        let slider = barView.panel.slider
        if slider.isTracking {
            if Date().timeIntervalSince(slider.lastTouchActivity) > Self.lostTouchTimeout {
                slider.endTracking() // sets the deadline via onTouchEnded
            } else {
                closeDeadline = nil
            }
            return
        }
        let deadline = closeDeadline ?? Date() + Settings.autoCloseDelay
        closeDeadline = deadline
        if Date() >= deadline { closePanel() }
    }

    private func closePanel(animated: Bool = true) {
        guard activeLevel != nil else { return }
        activeLevel = nil
        panelTimer?.invalidate()
        panelTimer = nil
        closeDeadline = nil
        barView.panel.slider.endTracking()
        barView.closePanel(animated: animated)
    }

    // MARK: - State → UI

    private func refresh() {
        if visibleKinds != layoutKinds {
            applyLayout() // calls back into refresh()
            return
        }
        for level in Level.allCases {
            let kind: BarItemKind = switch level {
            case .keyboard: .keyboardBrightness
            case .display: .displayBrightness
            case .volume: .volume
            }
            (itemViews[kind] as? GlassButton)?.setSymbol(level.symbol)
        }
        (itemViews[.mute] as? GlassButton)?.isActive = AudioController.shared.isMuted

        let nowPlaying = NowPlayingMonitor.shared
        let playSymbol = switch nowPlaying.isPlaying {
        case true?: "pause.fill"
        case false?: "play.fill"
        case nil: "playpause.fill"
        }
        (itemViews[.playPause] as? GlassButton)?.setSymbol(playSymbol)
        (itemViews[.nowPlaying] as? NowPlayingView)?.update(title: nowPlaying.title, artist: nowPlaying.artist)
        (itemViews[.clock] as? ClockView)?.update()

        if let level = activeLevel {
            barView.panel.slider.setValue(level.value)
        }
    }

    private func updateAppButton() {
        guard let button = itemViews[.appControls] as? GlassButton else { return }
        guard let icon = frontmostApp?.icon else {
            button.setSymbol("app.dashed")
            return
        }
        let sized = NSImage(size: NSSize(width: 22, height: 22), flipped: false) { rect in
            icon.draw(in: rect)
            return true
        }
        button.setImage(sized)
    }
}
