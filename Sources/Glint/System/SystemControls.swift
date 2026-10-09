import AppKit
import Carbon
import CoreGraphics
import GlintPrivate
import IOKit.pwr_mgt

/// A continuous system value Glint can show as a slider.
@MainActor
enum Level: CaseIterable {
    case keyboard
    case display
    case volume

    var isAvailable: Bool {
        switch self {
        case .keyboard: GLKeyboardBacklightAvailable()
        case .display: DisplayBrightness.builtInDisplay != nil
        case .volume: AudioController.shared.canChangeVolume
        }
    }

    var value: Float {
        switch self {
        case .keyboard: GLKeyboardBrightnessGet()
        case .display: DisplayBrightness.value ?? 0
        case .volume: AudioController.shared.isMuted ? 0 : AudioController.shared.volume
        }
    }

    func set(_ value: Float) {
        let value = min(max(value, 0), 1)
        switch self {
        case .keyboard: GLKeyboardBrightnessSet(value)
        case .display: DisplayBrightness.set(value)
        case .volume: AudioController.shared.volume = value
        }
    }

    /// The bar item showing this level as a slider.
    var kind: BarItemKind {
        switch self {
        case .keyboard: .keyboardBrightness
        case .display: .displayBrightness
        case .volume: .volume
        }
    }

    /// The button's icon at `value`. Takes the value rather than reading it, since reading
    /// asks another process.
    func symbol(for value: Float) -> String {
        switch self {
        case .keyboard:
            return value < 0.01 ? "light.min" : "light.max"
        case .display:
            return value < 0.35 ? "sun.min.fill" : "sun.max.fill"
        case .volume:
            if value == 0 { return "speaker.slash.fill" }
            if value < 0.34 { return "speaker.wave.1.fill" }
            if value < 0.67 { return "speaker.wave.2.fill" }
            return "speaker.wave.3.fill"
        }
    }

    /// Moves one notch up or down on the 16-step scale of the keyboard's level keys.
    /// Volume steps from the level it had before muting, so turning it up unmutes.
    func step(_ direction: Float) {
        let current = self == .volume ? AudioController.shared.volume : value
        set(((current * Self.steps).rounded() + direction) / Self.steps)
    }

    private static let steps: Float = 16

    /// Icons at the low and high ends of the slider.
    var lowSymbol: String {
        switch self {
        case .keyboard: "light.min"
        case .display: "sun.min.fill"
        case .volume: "speaker.fill"
        }
    }

    var highSymbol: String {
        switch self {
        case .keyboard: "light.max"
        case .display: "sun.max.fill"
        case .volume: "speaker.wave.3.fill"
        }
    }
}

@MainActor
enum DisplayBrightness {
    /// The internal panel, or nil in clamshell mode. Finding it asks the window server, so
    /// it's kept; `updateBuiltInDisplay()` looks again.
    private(set) static var builtInDisplay = findBuiltInDisplay()

    static func updateBuiltInDisplay() {
        builtInDisplay = findBuiltInDisplay()
    }

    private static func findBuiltInDisplay() -> CGDirectDisplayID? {
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(0, nil, &count) == .success, count > 0 else { return nil }
        var displays = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetOnlineDisplayList(count, &displays, &count) == .success else { return nil }
        return displays.first { CGDisplayIsBuiltin($0) != 0 }
    }

    static var value: Float? {
        guard let display = builtInDisplay else { return nil }
        var value: Float = 0
        return GLDisplayBrightnessGet(display, &value) ? value : nil
    }

    static func set(_ value: Float) {
        guard let display = builtInDisplay else { return }
        GLDisplayBrightnessSet(display, value)
    }
}

@MainActor
enum NightShift {
    static var isAvailable: Bool { GLNightShiftAvailable() }
    static var isOn: Bool { GLNightShiftIsOn() }

    static func toggle() {
        GLNightShiftSetOn(!isOn)
    }
}

@MainActor
enum Media {
    static func send(_ command: MediaCommand) {
        GLMediaSendCommand(command)
    }
}

@MainActor
enum SystemActions {
    static func screenshot() {
        open("/System/Applications/Utilities/Screenshot.app")
    }

    static func missionControl() {
        open("/System/Applications/Mission Control.app")
    }

    static func apps() {
        open("/System/Applications/Apps.app")
    }

    static func siri() {
        open("/System/Applications/Siri.app")
    }

    static func lockScreen() {
        GLLockScreen()
    }

    /// Opens or closes the Spotlight panel, as the Control Strip's button does.
    static func spotlight() {
        postDistributed("com.apple.spotlight.toggle")
    }

    /// Shows the system's Quick Actions popover on the Touch Bar.
    static func quickActions() {
        postDistributed("com.apple.ServicesTouchBar.showPopover")
    }

    static func showDesktop() {
        GLDockSendNotification("com.apple.showdesktop.awake")
    }

    static func screenSaver() {
        open("/System/Library/CoreServices/ScreenSaverEngine.app")
    }

    static func sleep() {
        let port = IOPMFindPowerManagement(kIOMainPortDefault)
        guard port != 0 else { return }
        IOPMSleepSystem(port)
        IOServiceClose(port)
    }

    /// Switches to the next keyboard input source, wrapping around.
    static func nextInputSource() {
        let filter = [
            kTISPropertyInputSourceCategory as String: kTISCategoryKeyboardInputSource as String,
            kTISPropertyInputSourceIsSelectCapable as String: true,
        ] as CFDictionary
        let list = TISCreateInputSourceList(filter, false)?.takeRetainedValue() as? [TISInputSource] ?? []
        let sources = list.filter { source in
            let type = property(kTISPropertyInputSourceType, of: source) as? String
            return type == kTISTypeKeyboardLayout as String || type == kTISTypeKeyboardInputMode as String
        }
        guard !sources.isEmpty else { return }
        let currentID = TISCopyCurrentKeyboardInputSource().map {
            property(kTISPropertyInputSourceID, of: $0.takeRetainedValue()) as? String
        } ?? nil
        let index = sources.firstIndex { property(kTISPropertyInputSourceID, of: $0) as? String == currentID }
        let next = sources[((index ?? -1) + 1) % sources.count]
        TISSelectInputSource(next)
    }

    private static func property(_ key: CFString, of source: TISInputSource) -> AnyObject? {
        guard let pointer = TISGetInputSourceProperty(source, key) else { return nil }
        return Unmanaged<AnyObject>.fromOpaque(pointer).takeUnretainedValue()
    }

    private static func postDistributed(_ name: String) {
        DistributedNotificationCenter.default().postNotificationName(.init(name), object: nil, userInfo: nil, deliverImmediately: true)
    }

    /// Opens `app`, or brings it to the front if it's already running.
    static func launch(_ app: URL) {
        NSWorkspace.shared.openApplication(at: app, configuration: .init())
    }

    private static func open(_ path: String) {
        launch(URL(fileURLWithPath: path))
    }
}
