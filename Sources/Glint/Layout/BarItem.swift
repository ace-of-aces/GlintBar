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
    case displayBrightness
    case volume
    case mute
    case screenshot
    case missionControl
    case apps
    case lockScreen
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
        case .keyboardBrightness: "Keyboard Brightness"
        case .displayBrightness: "Brightness"
        case .volume: "Volume"
        case .mute: "Mute"
        case .screenshot: "Screenshot"
        case .missionControl: "Mission Control"
        case .apps: "Apps"
        case .lockScreen: "Lock Screen"
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
        case .displayBrightness: "sun.max.fill"
        case .volume: "speaker.wave.2.fill"
        case .mute: "speaker.slash.fill"
        case .screenshot: "camera.fill"
        case .missionControl: "rectangle.3.group.fill"
        case .apps: "square.grid.3x3.fill"
        case .lockScreen: "lock.fill"
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
