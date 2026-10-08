import Foundation
import ServiceManagement

enum Settings {
    private static let autoCloseKey = "autoCloseDelay"

    /// Seconds a slider stays up after the finger lifts.
    static var autoCloseDelay: Double {
        get {
            let stored = UserDefaults.standard.object(forKey: autoCloseKey) as? Double ?? 1.5
            return stored > 0 ? stored : 1.5
        }
        set { UserDefaults.standard.set(newValue, forKey: autoCloseKey) }
    }

    static let autoCloseChoices: [Double] = [1, 1.5, 2.5, 4]

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
