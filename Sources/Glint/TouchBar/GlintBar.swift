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

    private var activeLevel: Level?
    private var collapseTask: Task<Void, Never>?
    private var readoutTask: Task<Void, Never>?
    private var pollTimer: Timer?

    /// Points of horizontal travel for a full 0→1 sweep when scrubbing a button.
    private static let scrubDistance: CGFloat = 240

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

        wireMainRow()
        wireSliderRow()
        AudioController.shared.onChange = { [weak self] in self?.refresh() }
        updateAppButton(NSWorkspace.shared.frontmostApplication)
    }

    // MARK: - Lifecycle

    func start() {
        TouchBarPrivate.addTrayItem(trayItem)
        showGlint()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            // Brightness and playback state have no change notifications we can use.
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    func stop() {
        pollTimer?.invalidate()
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
        closeSlider(animated: false)
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
        updateAppButton(app)
    }

    func touchBar(_ touchBar: NSTouchBar, makeItemForIdentifier identifier: NSTouchBarItem.Identifier) -> NSTouchBarItem? {
        guard identifier == Self.barItemID else { return nil }
        let item = NSCustomTouchBarItem(identifier: identifier)
        item.view = barView
        return item
    }

    #if DEBUG
    func debug(_ command: String) {
        switch command {
        case "slider:volume": openSlider(.volume)
        case "slider:display": openSlider(.display)
        case "slider:keyboard": openSlider(.keyboard)
        case "close": closeSlider()
        case "appControls": showAppControls()
        case "glint": showGlint()
        default: NSLog("Glint: unknown debug command \(command)")
        }
    }
    #endif

    // MARK: - Wiring

    private func wireMainRow() {
        let row = barView.main
        row.appButton.onTap = { [weak self] in self?.showAppControls() }
        row.previousButton.onTap = { Media.send(.previousTrack) }
        row.playPauseButton.onTap = { [weak self] in
            Media.send(.togglePlayPause)
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(300))
                self?.refresh()
            }
        }
        row.nextButton.onTap = { Media.send(.nextTrack) }
        row.muteButton.onTap = { [weak self] in
            AudioController.shared.isMuted.toggle()
            self?.refresh()
        }
        row.screenshotButton.onTap = { SystemActions.screenshot() }

        for (button, level) in [(row.keyboardButton, Level.keyboard), (row.displayButton, .display), (row.volumeButton, .volume)] {
            button.onTap = { [weak self] in self?.openSlider(level) }
            button.onScrubBegan = { [weak self, weak button] in
                self?.readoutTask?.cancel()
                button?.setGauge(level.value)
                self?.showReadout(for: level)
            }
            button.onScrub = { [weak self, weak button] delta in
                level.set(level.value + Float(delta / Self.scrubDistance))
                button?.setGauge(level.value)
                self?.showReadout(for: level)
                self?.refresh()
            }
            button.onScrubEnded = { [weak self] in self?.hideReadoutSoon() }
        }
    }

    private func wireSliderRow() {
        let row = barView.slider
        row.closeButton.onTap = { [weak self] in self?.closeSlider() }
        row.iconButton.onTap = { [weak self] in
            guard self?.activeLevel == .volume else { return }
            AudioController.shared.isMuted.toggle()
            self?.refresh()
            self?.scheduleCollapse()
        }
        row.slider.onChange = { [weak self] value in
            self?.activeLevel?.set(value)
            self?.refresh()
        }
        row.slider.onTouchBegan = { [weak self] in self?.collapseTask?.cancel() }
        row.slider.onTouchEnded = { [weak self] in self?.scheduleCollapse() }
    }

    // MARK: - Sliders

    private func openSlider(_ level: Level) {
        activeLevel = level
        barView.slider.slider.value = level.value
        refresh()
        barView.showSlider(true)
        scheduleCollapse()
    }

    private func closeSlider(animated: Bool = true) {
        collapseTask?.cancel()
        activeLevel = nil
        barView.showSlider(false, animated: animated)
    }

    private func scheduleCollapse() {
        collapseTask?.cancel()
        let delay = Settings.autoCloseDelay
        guard delay > 0 else { return }
        collapseTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            self?.closeSlider()
        }
    }

    private func showReadout(for level: Level) {
        barView.main.showReadout("\(level.title)  \(Int((level.value * 100).rounded()))%")
    }

    private func hideReadoutSoon() {
        readoutTask?.cancel()
        readoutTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(0.8))
            guard !Task.isCancelled else { return }
            self?.barView.main.showReadout(nil)
        }
    }

    // MARK: - State → UI

    private func refresh() {
        let row = barView.main
        row.keyboardButton.isHidden = !Level.keyboard.isAvailable
        row.displayButton.isHidden = !Level.display.isAvailable
        row.keyboardButton.setSymbol(Level.keyboard.symbol)
        row.displayButton.setSymbol(Level.display.symbol)
        row.volumeButton.setSymbol(Level.volume.symbol)
        row.muteButton.isActive = AudioController.shared.isMuted

        Media.isPlaying { [weak self] playing in
            let symbol = switch playing {
            case true?: "pause.fill"
            case false?: "play.fill"
            case nil: "playpause.fill"
            }
            self?.barView.main.playPauseButton.setSymbol(symbol)
        }

        if let level = activeLevel {
            let sliderRow = barView.slider
            sliderRow.iconButton.setSymbol(level.symbol)
            sliderRow.iconButton.isActive = level == .volume && AudioController.shared.isMuted
            if !sliderRow.slider.isTracking { sliderRow.slider.value = level.value }
            sliderRow.valueLabel.stringValue = "\(Int((level.value * 100).rounded()))%"
        }
    }

    private func updateAppButton(_ app: NSRunningApplication?) {
        guard let icon = app?.icon else {
            barView.main.appButton.setSymbol("app.dashed")
            return
        }
        let sized = NSImage(size: NSSize(width: 22, height: 22), flipped: false) { rect in
            icon.draw(in: rect)
            return true
        }
        barView.main.appButton.setImage(sized)
    }
}
