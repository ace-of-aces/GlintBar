import AppKit
import SwiftUI

/// Hosts `CustomizeView` in a regular window. GlintBar is a menu bar app, so it
/// activates itself to bring the window forward.
@MainActor
final class CustomizeWindowController: NSWindowController, NSWindowDelegate {
    static let shared = CustomizeWindowController()

    private init() {
        let window = NSWindow(
            contentRect: .zero, styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: true)
        window.title = "Customize GlintBar"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    /// The palette's previews show live CPU, GPU, memory and storage figures.
    private static let resourcesClient = "customize"

    func show() {
        guard let window else { return }
        if !window.isVisible {
            if window.contentViewController == nil {
                let hosting = NSHostingController(rootView: CustomizeView { [weak self] in self?.close() })
                hosting.sizingOptions = .preferredContentSize
                window.contentViewController = hosting
            }
            SystemResources.shared.setNeeded(true, by: Self.resourcesClient)
            // Size to the SwiftUI content before centring: centring the still zero-sized
            // window would put its corner, not its middle, at the centre of the screen.
            if let content = window.contentViewController?.view {
                let size = content.fittingSize
                window.setContentSize(size)
                // Once shown, SwiftUI also makes room for the (transparent) title bar.
                let titleBar = window.frame.height - window.contentLayoutRect.height
                window.setContentSize(NSSize(width: size.width, height: size.height + titleBar))
            }
            center(window)
        }
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    /// Centres `window` in the visible area (menu bar and Dock excluded) of the screen
    /// the user is working on.
    private func center(_ window: NSWindow) {
        guard let screen = NSScreen.main ?? window.screen ?? NSScreen.screens.first else { return }
        let visible = screen.visibleFrame
        let size = window.frame.size
        window.setFrameOrigin(
            NSPoint(
                x: (visible.midX - size.width / 2).rounded(),
                y: max(visible.minY, (visible.midY - size.height / 2).rounded())
            ))
    }

    #if DEBUG
    /// Writes a PNG of the window, with any popover open over it, or with `popoverOnly` of
    /// just the popover, shadow and all. A process may capture its own windows without
    /// Screen Recording permission. (CGWindowListCreateImageFromArray is unavailable to Swift
    /// in current SDKs, hence the lookup.)
    func debugSnapshot(to path: String, popoverOnly: Bool = false) {
        typealias CreateImage = @convention(c) (CGRect, CFArray, UInt32) -> Unmanaged<CGImage>?
        guard let window,
            let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "CGWindowListCreateImageFromArray")
        else {
            return
        }
        let create = unsafeBitCast(symbol, to: CreateImage.self)
        // Popovers are child windows. The array holds bare window numbers, not objects;
        // front to back.
        let popovers = Array((window.childWindows ?? []).filter(\.isVisible).reversed())
        var windows = (popoverOnly ? popovers : popovers + [window]).map {
            UnsafeRawPointer(bitPattern: $0.windowNumber)
        }
        guard !windows.isEmpty, let list = CFArrayCreate(nil, &windows, windows.count, nil) else { return }
        // boundsIgnoreFraming = 1 << 0 (leaves out the shadow), bestResolution = 1 << 3
        let options: UInt32 = popoverOnly ? 1 << 3 : 1 << 0 | 1 << 3
        guard let image = create(.null, list, options)?.takeRetainedValue() else {
            NSLog("GlintBar: snapshot failed")
            return
        }
        let rep = NSBitmapImageRep(cgImage: image)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
    }
    #endif

    func windowWillClose(_ notification: Notification) {
        BarConfiguration.shared.previewItems = nil
        SystemResources.shared.setNeeded(false, by: Self.resourcesClient)
        // A closed window's SwiftUI views keep updating with what they observe (the meters
        // every two seconds), so they go once it has closed (the close may come from a
        // button among them) and come back with the window.
        DispatchQueue.main.async { [weak self] in
            guard let window = self?.window, !window.isVisible else { return }
            window.contentViewController = nil
        }
    }
}
