import AppKit

/// Everything that can be placed in the GlintBar.
enum BarItemKind: Hashable, Sendable {
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
    case battery
    case systemResources
    /// Launches an app. Without one it is the palette's "App" tile, which asks for
    /// an app before it goes into the bar.
    case app(URL?)
    case space
    case flexibleSpace

    /// How the item is saved, e.g. `volume` or `app:/Applications/Safari.app`. Spelled
    /// out rather than derived from the case names, so renaming a case can't lose it
    /// from anyone's saved layout.
    var rawValue: String {
        switch self {
        case .appControls: "appControls"
        case .previousTrack: "previousTrack"
        case .playPause: "playPause"
        case .nextTrack: "nextTrack"
        case .nowPlaying: "nowPlaying"
        case .keyboardBrightness: "keyboardBrightness"
        case .keyboardBrightnessDown: "keyboardBrightnessDown"
        case .keyboardBrightnessUp: "keyboardBrightnessUp"
        case .displayBrightness: "displayBrightness"
        case .displayBrightnessDown: "displayBrightnessDown"
        case .displayBrightnessUp: "displayBrightnessUp"
        case .nightShift: "nightShift"
        case .volume: "volume"
        case .volumeDown: "volumeDown"
        case .volumeUp: "volumeUp"
        case .mute: "mute"
        case .screenshot: "screenshot"
        case .missionControl: "missionControl"
        case .apps: "apps"
        case .spotlight: "spotlight"
        case .showDesktop: "showDesktop"
        case .inputSources: "inputSources"
        case .quickActions: "quickActions"
        case .lockScreen: "lockScreen"
        case .screenSaver: "screenSaver"
        case .sleep: "sleep"
        case .siri: "siri"
        case .clock: "clock"
        case .battery: "battery"
        case .systemResources: "systemResources"
        case .app(let url): Self.appPrefix + (url?.path ?? "")
        case .space: "space"
        case .flexibleSpace: "flexibleSpace"
        }
    }

    /// Reads back what `rawValue` saved. Anything the palette offers can be read back,
    /// so an item can't be added and then vanish at the next launch.
    init?(rawValue: String) {
        if rawValue.hasPrefix(Self.appPrefix) {
            let path = rawValue.dropFirst(Self.appPrefix.count)
            guard !path.isEmpty else { return nil }
            self = .launching(URL(fileURLWithPath: String(path)))
            return
        }
        guard let kind = PaletteSection.all.lazy.flatMap(\.kinds).first(where: { $0.appURL == nil && $0.rawValue == rawValue }) else { return nil }
        self = kind
    }

    private static let appPrefix = "app:"

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
        case .battery: "Battery"
        case .systemResources: "System Resources"
        case .app(let url?): FileManager.default.displayName(atPath: url.path)
        case .app(nil): "App"
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
        case .app(nil): "plus.app"
        case .appControls, .nowPlaying, .clock, .battery, .systemResources, .app, .space, .flexibleSpace: nil
        }
    }

    /// The app's icon, sized for a bar button.
    @MainActor static func icon(for app: URL) -> NSImage {
        buttonIcon(NSWorkspace.shared.icon(forFile: app.path))
    }

    /// `icon` at the size bar buttons show app icons, leaving `icon` itself as it was.
    @MainActor static func buttonIcon(_ icon: NSImage) -> NSImage {
        let sized = icon.copy() as! NSImage
        sized.size = NSSize(width: 22, height: 22)
        return sized
    }

    /// Width on the Touch Bar in points. Flexible spaces share whatever is left.
    var width: CGFloat {
        switch self {
        case .playPause, .keyboardBrightness, .displayBrightness, .volume: 56
        case .nowPlaying: 180
        case .clock: Self.clockWidth
        case .battery: 80
        case .systemResources: 206
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
        switch self {
        case .nightShift: NightShift.isAvailable
        case .battery: Battery.shared.isAvailable
        case .app(let url?): FileManager.default.fileExists(atPath: url.path)
        default: (level ?? step?.level)?.isAvailable ?? true
        }
    }

    /// A button launching `app`, with its URL in one canonical form so the same app
    /// always compares equal, however it was picked.
    static func launching(_ app: URL) -> BarItemKind {
        .app(URL(fileURLWithPath: app.standardizedFileURL.path, isDirectory: true))
    }

    /// The app an app button launches.
    var appURL: URL? {
        if case .app(let url) = self { url } else { nil }
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

/// Every item a bar can hold, grouped as the customization palette shows them.
struct PaletteSection {
    let title: String
    let kinds: [BarItemKind]

    static let all = [
        PaletteSection(title: "Media", kinds: [.previousTrack, .playPause, .nextTrack, .nowPlaying]),
        PaletteSection(title: "Sound", kinds: [.volume, .volumeDown, .volumeUp, .mute]),
        PaletteSection(title: "Light", kinds: [
            .displayBrightness, .displayBrightnessDown, .displayBrightnessUp,
            .keyboardBrightness, .keyboardBrightnessDown, .keyboardBrightnessUp, .nightShift,
        ]),
        PaletteSection(title: "Spacing", kinds: [.space, .flexibleSpace]),
        PaletteSection(title: "System", kinds: [
            .appControls, .siri, .spotlight, .missionControl, .apps, .showDesktop, .inputSources, .quickActions,
        ]),
        PaletteSection(title: "Your Apps", kinds: [.app(nil)]),
        PaletteSection(title: "Status", kinds: [.clock, .battery, .systemResources]),
        PaletteSection(title: "Session", kinds: [.screenshot, .screenSaver, .lockScreen, .sleep]),
    ]
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
