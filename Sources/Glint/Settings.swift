import Foundation
import ServiceManagement

enum Settings {
    private static let autoCloseKey = "autoCloseDelay"

    /// Seconds of inactivity before an open slider closes itself; 0 keeps it open.
    static var autoCloseDelay: Double {
        get { UserDefaults.standard.object(forKey: autoCloseKey) as? Double ?? 2.5 }
        set { UserDefaults.standard.set(newValue, forKey: autoCloseKey) }
    }

    static let autoCloseChoices: [Double] = [1.5, 2.5, 4, 0]

    /// Login items only work from a real .app bundle, not `swift run`.
    static var canLaunchAtLogin: Bool {
        Bundle.main.bundleURL.pathExtension == "app"
    }

    static var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            do {
                if newValue {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                NSLog("Glint: couldn't update login item: \(error)")
            }
        }
    }
}
