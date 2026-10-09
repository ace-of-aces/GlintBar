import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let bar = GlintBar()
    private var statusItem: NSStatusItem?
    private var reassertTask: Task<Void, Never>?

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard TouchBarPrivate.isAvailable else {
            let alert = NSAlert()
            alert.messageText = "Glint can't control the Touch Bar"
            alert.informativeText =
                "This version of macOS doesn't provide the Touch Bar interfaces Glint needs."
            alert.runModal()
            NSApp.terminate(nil)
            return
        }

        setUpStatusItem()
        observeSystemEvents()
        bar.onStateChange = { [weak self] in self?.updateStatusIcon() }
        bar.start()
        #if DEBUG
            listenForDebugCommands()
        #endif
    }

    #if DEBUG
        /// Lets the bar be driven without touching it, e.g.:
        /// osascript -l JavaScript -e 'ObjC.import("Foundation"); $.NSDistributedNotificationCenter.defaultCenter
        ///   .postNotificationNameObjectUserInfoDeliverImmediately("center.julian.Glint.debug", "slider:volume", $(), true)'
        private func listenForDebugCommands() {
            DistributedNotificationCenter.default().addObserver(
                forName: .init("center.julian.Glint.debug"), object: nil, queue: .main
            ) { [weak self] note in
                let command = note.object as? String ?? ""
                MainActor.assumeIsolated { self?.bar.debug(command) }
            }
        }
    #endif

    /// Opening Glint.app again while it runs (Finder, Spotlight, `open`) shows the customizer.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool)
        -> Bool
    {
        customize()
        return false
    }

    func applicationWillTerminate(_ notification: Notification) {
        bar.stop()
    }

    // MARK: - Keeping the bar on top

    private func observeSystemEvents() {
        let center = NSWorkspace.shared.notificationCenter
        let reassertOn: [Notification.Name] = [
            NSWorkspace.didWakeNotification,
            NSWorkspace.screensDidWakeNotification,
            NSWorkspace.sessionDidBecomeActiveNotification,
            NSWorkspace.activeSpaceDidChangeNotification,
        ]
        for name in reassertOn {
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.scheduleReassert() }
            }
        }
        center.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            MainActor.assumeIsolated { self?.bar.frontmostAppChanged(app) }
        }
    }

    /// Coalesces bursts of system events and gives the Touch Bar server a moment to settle.
    private func scheduleReassert() {
        reassertTask?.cancel()
        reassertTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            self?.bar.reassert()
        }
    }

    // MARK: - Menu bar

    private func setUpStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        statusItem = item
        updateStatusIcon()
    }

    private func updateStatusIcon() {
        statusItem?.button?.image = EclipseGlyph.menuBarImage(glintShowing: bar.state == .glint)
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        if bar.state == .glint {
            menu.addItem(
                withTitle: "Show App Controls", action: #selector(showAppControls),
                keyEquivalent: ""
            ).target = self
        } else {
            menu.addItem(withTitle: "Show Glint", action: #selector(showGlint), keyEquivalent: "")
                .target = self
        }
        menu.addItem(.separator())

        menu.addItem(
            withTitle: "Customize Glint Bar", action: #selector(customize), keyEquivalent: ","
        ).target = self

        let autoClose = NSMenuItem(title: "Hide Sliders After", action: nil, keyEquivalent: "")
        let choices = NSMenu()
        for delay in Settings.autoCloseChoices {
            let title = delay == 0 ? "No Delay" : "\(delay.formatted()) s"
            let choice = NSMenuItem(
                title: title, action: #selector(setAutoClose(_:)), keyEquivalent: "")
            choice.target = self
            choice.representedObject = delay
            choice.state = Settings.autoCloseDelay == delay ? .on : .off
            choices.addItem(choice)
        }
        autoClose.submenu = choices
        menu.addItem(autoClose)

        let login = NSMenuItem(
            title: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        login.target = self
        login.state = Settings.launchAtLogin ? .on : .off
        if !Settings.canLaunchAtLogin {
            login.action = nil
            login.toolTip = "Available when Glint runs from Glint.app"
        }
        menu.addItem(login)

        menu.addItem(.separator())
        menu.addItem(
            withTitle: "Quit Glint", action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q")
    }

    @objc private func showGlint() { bar.showGlint() }

    @objc private func customize() {
        // Show Glint's own bar so changes are visible on the Touch Bar while editing.
        if bar.state != .glint { bar.showGlint() }
        CustomizeWindowController.shared.show()
    }
    @objc private func showAppControls() { bar.showAppControls() }

    @objc private func setAutoClose(_ sender: NSMenuItem) {
        if let delay = sender.representedObject as? Double { Settings.autoCloseDelay = delay }
    }

    @objc private func toggleLaunchAtLogin() {
        Settings.launchAtLogin.toggle()
    }
}
