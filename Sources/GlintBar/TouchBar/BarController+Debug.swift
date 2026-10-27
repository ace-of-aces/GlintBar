#if DEBUG
import AppKit

extension BarController {
    /// The button a simulated finger is on.
    private static var debugButton: GlassButton?

    /// Simulates a finger on a level button with bar x positions — `down:volume`
    /// (or `down:volume:850`), `move:700`, `up`, `tap:display` — plus `close`,
    /// `appControls` and `glint`; `press:<item>` taps any button item, e.g. `press:volumeUp`.
    func debug(_ command: String) {
        let parts = command.split(separator: ":").map(String.init)
        func button(for name: String) -> GlassButton {
            let level = Level.allCases.first { "\($0)" == name } ?? .volume
            return itemViews[level.kind] as? GlassButton ?? GlassButton(symbol: "questionmark")
        }
        func local(_ barX: String?, in button: GlassButton) -> CGFloat {
            guard let barX, let x = Double(barX) else { return button.bounds.midX }
            return button.convert(NSPoint(x: x, y: 0), from: barView).x
        }
        switch parts.first {
        case "down", "tap":
            let target = button(for: parts.count > 1 ? parts[1] : "volume")
            Self.debugButton = target
            target.onTouchDown?(local(parts.count > 2 ? parts[2] : nil, in: target))
            if parts.first == "tap" { target.onTouchUp?() }
        case "move":
            guard let target = Self.debugButton else { return }
            target.onTouchMoved?(local(parts.count > 1 ? parts[1] : nil, in: target))
        case "up":
            Self.debugButton?.onTouchUp?()
        case "scrub":
            // scrub:down · scrub:move:<bar x> · scrub:up — a finger on the Now Playing widget.
            guard let view = itemViews[.nowPlaying] as? NowPlayingView else { return }
            let x =
                parts.count > 2
                ? view.convert(NSPoint(x: Double(parts[2]) ?? 0, y: 0), from: barView).x : view.bounds.midX
            switch parts.count > 1 ? parts[1] : "" {
            case "down": view.onScrubBegan?(x)
            case "move": view.onScrubMoved?(x)
            default: view.onScrubEnded?()
            }
        case "press":
            guard parts.count > 1, let kind = BarItemKind(rawValue: parts[1]) else { return }
            ((itemViews[kind] ?? makeItemView(kind)) as? GlassButton)?.onTap?()
        case "battery":
            // battery:<percent>[:charging|:power] fakes the battery; battery:real undoes it.
            let percent = parts.count > 1 ? Int(parts[1]) : nil
            let power = parts.count > 2 ? parts[2] : ""
            Battery.shared.debugOverride(
                percent.map {
                    Battery.State(
                        percent: $0, isCharging: power == "charging", isOnPower: power == "charging" || power == "power"
                    )
                })
        case "resources":
            // resources:<cpu>:<gpu>:<memory>:<storage> in percent fakes the readings; resources:real undoes it.
            let percents = parts.dropFirst().map { Double($0).map { $0 / 100 } }
            SystemResources.shared.debugOverride(
                percents.count == 4
                    ? SystemResources.Usage(
                        cpu: percents[0], gpu: percents[1], memory: percents[2], storage: percents[3]
                    ) : nil)
        case "customize": CustomizeWindowController.shared.show()
        case "cdrag":
            // cdrag:bar:<index> · cdrag:palette:<kind> · cdrag:to:<bar x> · cdrag:off · cdrag:drop
            let driver = CustomizeDebugDriver.shared
            switch parts.count > 1 ? parts[1] : "" {
            case "bar": driver.perform(.pickUpBarItem(index: Int(parts[2]) ?? 0))
            case "palette":
                (parts[2] == "app" ? .app(nil) : BarItemKind(rawValue: parts[2])).map {
                    driver.perform(.pickUpPaletteItem($0))
                }
            case "to": driver.perform(.moveOverBar(x: CGFloat(Double(parts[2]) ?? 0)))
            case "off": driver.perform(.moveOffBar)
            default: driver.perform(.drop)
            }
        case "snapshot":
            CustomizeWindowController.shared.debugSnapshot(
                to: parts.count > 1 ? parts[1...].joined(separator: ":") : "/tmp/glint-customize.png")
        case "close": panel.close()
        case "appControls": showAppControls()
        case "glint": showGlint()
        default: NSLog("GlintBar: unknown debug command \(command)")
        }
    }
}
#endif
