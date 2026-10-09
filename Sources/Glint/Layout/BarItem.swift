import CoreGraphics
import Foundation

/// Everything that can be placed in the Glint bar.
enum BarItemKind: String, CaseIterable, Codable, Sendable {
    case appControls
    case previousTrack
    case playPause
    case nextTrack
    case nowPlaying
    case keyboardBrightness
    case keyboardBrightnessDown
    case keyboardBrightnessUp
    case displayBrightness
    case displayBrightnessDown
    case displayBrightnessUp
    case nightShift
    case volume
    case volumeDown
    case volumeUp
    case mute
    case screenshot
    case missionControl
    case apps
    case spotlight
    case showDesktop
    case inputSources
    case quickActions
    case lockScreen
    case screenSaver
    case sleep
    case siri
    case clock
    case space
    case flexibleSpace

    var title: String {
        switch self {
        case .appControls: "App Controls"
        case .previousTrack: "Previous"
        case .playPause: "Play/Pause"
        case .nextTrack: "Next"
        case .nowPlaying: "Now Playing"
        case .keyboardBrightness: "Keyboard Brightness Slider"
        case .keyboardBrightnessDown: "Backlight Down"
        case .keyboardBrightnessUp: "Backlight Up"
        case .displayBrightness: "Brightness Slider"
        case .displayBrightnessDown: "Brightness Down"
        case .displayBrightnessUp: "Brightness Up"
        case .nightShift: "Night Shift"
        case .volume: "Volume Slider"
        case .volumeDown: "Volume Down"
        case .volumeUp: "Volume Up"
        case .mute: "Mute"
        case .screenshot: "Screenshot"
        case .missionControl: "Mission Control"
        case .apps: "Apps"
        case .spotlight: "Spotlight"
        case .showDesktop: "Show Desktop"
        case .inputSources: "Input Sources"
        case .quickActions: "Quick Actions"
        case .lockScreen: "Lock Screen"
        case .screenSaver: "Screen Saver"
        case .sleep: "Sleep"
        case .siri: "Siri"
        case .clock: "Clock"
        case .space: "Space"
        case .flexibleSpace: "Flexible Space"
        }
    }

    /// The SF Symbol a button shows by default (state may swap it at runtime).
    var symbol: String? {
        switch self {
        case .previousTrack: "backward.fill"
        case .playPause: "playpause.fill"
        case .nextTrack: "forward.fill"
        case .keyboardBrightness: "light.max"
        case .keyboardBrightnessDown: "light.min"
        case .keyboardBrightnessUp: "light.max"
        case .displayBrightness: "sun.max.fill"
        case .displayBrightnessDown: "sun.min.fill"
        case .displayBrightnessUp: "sun.max.fill"
        case .nightShift: "sun.horizon.fill"
        case .volume: "speaker.wave.2.fill"
        case .volumeDown: "speaker.wave.1.fill"
        case .volumeUp: "speaker.wave.3.fill"
        case .mute: "speaker.slash.fill"
        case .screenshot: "camera.fill"
        case .missionControl: "rectangle.3.group.fill"
        case .apps: "square.grid.3x3.fill"
        case .spotlight: "magnifyingglass"
        case .showDesktop: "menubar.dock.rectangle"
        case .inputSources: "globe"
        case .quickActions: "wand.and.sparkles"
        case .lockScreen: "lock.fill"
        case .screenSaver: "tv"
        case .sleep: "powersleep"
        case .siri: "siri"
        case .appControls, .nowPlaying, .clock, .space, .flexibleSpace: nil
        }
    }

    /// Width on the Touch Bar in points. Flexible spaces share whatever is left.
    var width: CGFloat {
        switch self {
        case .playPause, .keyboardBrightness, .displayBrightness, .volume: 56
        case .nowPlaying: 180
        case .clock: Self.clockWidth
        case .space: 18
        case .flexibleSpace: 0
        default: 44
        }
    }

    /// Room for "12:34", or "12:34 PM" where the locale uses a 12-hour clock.
    private static let clockWidth: CGFloat = {
        let format = DateFormatter.dateFormat(fromTemplate: "j", options: 0, locale: .current) ?? ""
        return format.contains("a") ? 84 : 56
    }()

    var isSpacer: Bool { self == .space || self == .flexibleSpace }

    /// Spacers can be used any number of times; everything else at most once.
    var isUnique: Bool { !isSpacer }

    /// The slider a button opens, if it is a level control.
    var level: Level? {
        switch self {
        case .keyboardBrightness: .keyboard
        case .displayBrightness: .display
        case .volume: .volume
        default: nil
        }
    }

    /// The level a button nudges by one step, and in which direction.
    var step: (level: Level, direction: Float)? {
        switch self {
        case .keyboardBrightnessDown: (.keyboard, -1)
        case .keyboardBrightnessUp: (.keyboard, 1)
        case .displayBrightnessDown: (.display, -1)
        case .displayBrightnessUp: (.display, 1)
        case .volumeDown: (.volume, -1)
        case .volumeUp: (.volume, 1)
        default: nil
        }
    }

    /// Whether this Mac can use the item right now (no keyboard backlight, lid closed,
    /// an output without volume control, no Night Shift).
    @MainActor var isAvailable: Bool {
        if self == .nightShift { return NightShift.isAvailable }
        return (level ?? step?.level)?.isAvailable ?? true
    }
}

struct BarItem: Identifiable, Hashable, Sendable {
    let id: UUID
    let kind: BarItemKind

    init(_ kind: BarItemKind, id: UUID = UUID()) {
        self.id = id
        self.kind = kind
    }
}

/// Positions items along the bar. Shared by the real Touch Bar and the customization
/// preview so the two always agree.
enum BarLayout {
    static let gap: CGFloat = 8

    /// Gap between two neighbours: spacers bring their own spacing.
    static func gap(between a: BarItemKind, and b: BarItemKind) -> CGFloat {
        a.isSpacer || b.isSpacer ? 0 : gap
    }

    /// Width taken by everything but flexible spaces.
    static func fixedWidth(of kinds: [BarItemKind]) -> CGFloat {
        let widths = kinds.reduce(0) { $0 + $1.width }
        let gaps = zip(kinds, kinds.dropFirst()).reduce(0) { $0 + gap(between: $1.0, and: $1.1) }
        return widths + gaps
    }

    static func fits(_ kinds: [BarItemKind], in width: CGFloat) -> Bool {
        fixedWidth(of: kinds) <= width + 0.5
    }

    /// One frame per item, left to right, in a bar of the given size.
    static func frames(for kinds: [BarItemKind], in size: CGSize) -> [CGRect] {
        let flexibleCount = kinds.filter { $0 == .flexibleSpace }.count
        let flexibleWidth = flexibleCount > 0 ? max(size.width - fixedWidth(of: kinds), 0) / CGFloat(flexibleCount) : 0
        var frames: [CGRect] = []
        var x: CGFloat = 0
        for (index, kind) in kinds.enumerated() {
            if index > 0 { x += gap(between: kinds[index - 1], and: kind) }
            let width = kind == .flexibleSpace ? flexibleWidth : kind.width
            frames.append(CGRect(x: x, y: 0, width: width, height: size.height))
            x += width
        }
        return frames
    }
}
