import AppKit

/// A battery like the one in the menu bar: an outline filled to the charge, with a bolt
/// cut into it while charging. Green while charging, red when low, white otherwise.
enum BatteryGlyph {
    static let size = NSSize(width: 27, height: 13)

    static func image(for state: Battery.State) -> NSImage {
        NSImage(size: size, flipped: false) { _ in
            draw(state)
            return true
        }
    }

    private static func draw(_ state: Battery.State) {
        let body = NSRect(x: 0.75, y: 0.75, width: 23, height: 11.5)
        let outline = NSBezierPath(roundedRect: body, xRadius: 3.5, yRadius: 3.5)
        outline.lineWidth = 1.5
        NSColor.white.withAlphaComponent(0.45).setStroke()
        outline.stroke()

        let nub = NSBezierPath(roundedRect: NSRect(x: 24.75, y: 4.25, width: 1.75, height: 4.5), xRadius: 0.9, yRadius: 0.9)
        NSColor.white.withAlphaComponent(0.45).setFill()
        nub.fill()

        // At least a sliver, so an almost empty battery still shows its colour.
        let inner = body.insetBy(dx: 2, dy: 2)
        let fillWidth = max(inner.width * CGFloat(state.percent) / 100, 2)
        let fill = NSBezierPath(roundedRect: NSRect(x: inner.minX, y: inner.minY, width: fillWidth, height: inner.height), xRadius: 1.75, yRadius: 1.75)
        fillColor(for: state).setFill()
        fill.fill()

        guard state.isCharging, let bolt = boltImage(pointSize: 8) else { return }
        let center = NSPoint(x: body.midX, y: body.midY)
        // Knock a slightly bigger bolt out of everything first, so the bolt stands apart
        // from the fill and outline.
        if let knockout = boltImage(pointSize: 10.5) {
            knockout.draw(in: centered(knockout.size, at: center), from: .zero, operation: .destinationOut, fraction: 1)
        }
        bolt.draw(in: centered(bolt.size, at: center), from: .zero, operation: .sourceOver, fraction: 1)
    }

    private static func fillColor(for state: Battery.State) -> NSColor {
        if state.isCharging { return .systemGreen }
        if state.isLow { return .systemRed }
        return .white
    }

    private static func boltImage(pointSize: CGFloat) -> NSImage? {
        let config = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .black)
            .applying(.init(paletteColors: [.white]))
        return NSImage(systemSymbolName: "bolt.fill", accessibilityDescription: nil)?.withSymbolConfiguration(config)
    }

    private static func centered(_ size: NSSize, at center: NSPoint) -> NSRect {
        NSRect(x: center.x - size.width / 2, y: center.y - size.height / 2, width: size.width, height: size.height)
    }
}
