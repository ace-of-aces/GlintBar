import AppKit
import CoreGraphics
import GlintPrivate

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

    var symbol: String {
        switch self {
        case .keyboard:
            return value < 0.01 ? "light.min" : "light.max"
        case .display:
            return value < 0.35 ? "sun.min.fill" : "sun.max.fill"
        case .volume:
            let v = value
            if v == 0 { return "speaker.slash.fill" }
            if v < 0.34 { return "speaker.wave.1.fill" }
            if v < 0.67 { return "speaker.wave.2.fill" }
            return "speaker.wave.3.fill"
        }
    }

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
    /// The internal panel, or nil in clamshell mode.
    static var builtInDisplay: CGDirectDisplayID? {
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

    private static func open(_ path: String) {
        NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: path), configuration: .init())
    }
}
