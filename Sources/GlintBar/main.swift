import AppKit

let app = NSApplication.shared

// Only one GlintBar may own the Touch Bar.
if let bundleID = Bundle.main.bundleIdentifier,
   NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).count > 1 {
    exit(0)
}

// Writing to the now-playing helper's pipe after it exited must fail, not kill us.
signal(SIGPIPE, SIG_IGN)

let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
