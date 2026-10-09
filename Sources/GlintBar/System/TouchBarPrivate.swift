import AppKit
import GlintBarPrivate

/// Swift face of the private system-modal Touch Bar API (see GlintBarPrivate.h).
@MainActor
enum TouchBarPrivate {
    static var isAvailable: Bool { GLSystemModalAvailable() }

    /// Shows `touchBar` above every app's Touch Bar until it is minimized or dismissed.
    static func present(_ touchBar: NSTouchBar, placement: SystemModalPlacement, trayItem: NSTouchBarItem.Identifier?) {
        GLPresentSystemModal(touchBar, placement, trayItem)
    }

    /// Hides `touchBar` but keeps its tray item in the Control Strip so it can come back.
    static func minimize(_ touchBar: NSTouchBar) {
        GLMinimizeSystemModal(touchBar)
    }

    static func dismiss(_ touchBar: NSTouchBar) {
        GLDismissSystemModal(touchBar)
    }

    static func addTrayItem(_ item: NSTouchBarItem) {
        GLAddSystemTrayItem(item)
        GLSetControlStripPresence(item.identifier, true)
    }

    static func removeTrayItem(_ item: NSTouchBarItem) {
        GLSetControlStripPresence(item.identifier, false)
        GLRemoveSystemTrayItem(item)
    }
}
