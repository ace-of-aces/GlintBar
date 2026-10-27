import Foundation
import ServiceManagement

enum Settings {
    private static let autoCloseKey = "sliderCloseDelay"

    /// Seconds a slider stays up after the finger lifts; 0 closes it right away.
    static var autoCloseDelay: Double {
        get { UserDefaults.standard.object(forKey: autoCloseKey) as? Double ?? 0.5 }
        set { UserDefaults.standard.set(newValue, forKey: autoCloseKey) }
    }

    static let autoCloseChoices: [Double] = [0, 0.5, 1, 1.5, 2.5, 4]

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
                NSLog("GlintBar: couldn't update login item: \(error)")
            }
        }
    }
}
