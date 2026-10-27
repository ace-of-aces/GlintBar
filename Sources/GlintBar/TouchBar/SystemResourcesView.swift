import AppKit
import SwiftUI

/// The four meters: what they measure, in what colour, in order.
enum ResourceMeter: CaseIterable {
    case cpu, gpu, memory, storage

    var label: String {
        switch self {
        case .cpu: "CPU"
        case .gpu: "GPU"
        case .memory: "RAM"
        case .storage: "SSD"
        }
    }

    /// The meter's name for VoiceOver.
    var spokenLabel: String {
        switch self {
        case .cpu: "CPU"
        case .gpu: "GPU"
        case .memory: "Memory"
        case .storage: "Storage"
        }
    }

    var color: NSColor {
        switch self {
        case .cpu: .systemBlue
        case .gpu: .systemPurple
        case .memory: .systemGreen
        case .storage: .systemOrange
        }
    }

    func value(in usage: SystemResources.Usage) -> Double? {
        switch self {
        case .cpu: usage.cpu
        case .gpu: usage.gpu
        case .memory: usage.memory
        case .storage: usage.storage
        }
    }

    // Shared geometry, so the Touch Bar and the preview match.
    static let width: CGFloat = 44
    /// Without a capsule around them, a wider gap keeps the meters apart.
    static let spacing: CGFloat = 10
    @MainActor static let labelFont = NSFont.systemFont(ofSize: 8.5, weight: .semibold)
    @MainActor static let valueFont = NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .semibold)
    @MainActor static let percentFont = NSFont.systemFont(ofSize: 7.5, weight: .semibold)
}

/// The meters on the Touch Bar, as plain as the clock: per meter a label, a percentage
/// and a bar.
@MainActor
final class SystemResourcesView: NSView {
    private let meters = ResourceMeter.allCases.map { MeterView($0) }
    private let width: CGFloat
    private var usage = SystemResources.Usage()

    init(width: CGFloat) {
        self.width = width
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: BarMetrics.height))
        meters.forEach(addSubview)
        update(SystemResources.shared.usage)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var intrinsicContentSize: NSSize { NSSize(width: width, height: BarMetrics.height) }

    override func layout() {
        super.layout()
        let total = CGFloat(meters.count) * ResourceMeter.width + CGFloat(meters.count - 1) * ResourceMeter.spacing
        var x = ((bounds.width - total) / 2).rounded()
        for meter in meters {
            meter.frame = NSRect(x: x, y: 0, width: ResourceMeter.width, height: bounds.height)
            x += ResourceMeter.width + ResourceMeter.spacing
        }
    }

    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { .staticText }
    override func accessibilityLabel() -> String? { "System Resources" }
    override func accessibilityChildren() -> [Any]? { [] }

    /// E.g. "CPU 12 %, GPU 3 %, Memory 61 %, Storage 70 %", leaving out what isn't known yet.
    override func accessibilityValue() -> Any? {
        ResourceMeter.allCases.compactMap { meter in
            meter.value(in: usage).map { "\(meter.spokenLabel) \(GlassSlider.percentText(Float($0)))" }
        }.joined(separator: ", ")
    }

    func update(_ usage: SystemResources.Usage) {
        self.usage = usage
        for meter in meters { meter.show(meter.meter.value(in: usage)) }
    }
}

@MainActor
private final class MeterView: NSView {
    let meter: ResourceMeter
    private let label = NSTextField(labelWithString: "")
    private let value = NSTextField(labelWithString: "")
    private let track = CALayer()
    private let fill = CALayer()
    private var fraction: CGFloat = 0
    /// The digits shown ("42", or "–" while unknown).
    private var digits: String?

    /// The text row's baseline and the bar, measured from the bottom.
    private static let baseline: CGFloat = 14.5
    private static let barY: CGFloat = 8
    private static let barHeight: CGFloat = 3

    init(_ meter: ResourceMeter) {
        self.meter = meter
        super.init(frame: .zero)
        wantsLayer = true
        label.stringValue = meter.label
        label.font = ResourceMeter.labelFont
        label.textColor = NSColor.white.withAlphaComponent(0.55)
        track.backgroundColor = NSColor.white.withAlphaComponent(0.18).cgColor
        fill.backgroundColor = meter.color.cgColor
        for bar in [track, fill] {
            bar.cornerRadius = Self.barHeight / 2
            layer?.addSublayer(bar)
        }
        addSubview(label)
        addSubview(value)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        for field in [label, value] { field.sizeToFit() }
        label.setFrameOrigin(NSPoint(x: -2, y: Self.baseline - label.baselineOffsetFromBottom))
        value.setFrameOrigin(NSPoint(x: bounds.width - value.frame.width + 2, y: Self.baseline - value.baselineOffsetFromBottom))
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        track.frame = NSRect(x: 0, y: Self.barY, width: bounds.width, height: Self.barHeight)
        CATransaction.commit()
        layoutFill(animated: false)
    }

    func show(_ newValue: Double?) {
        // Storage and memory rarely move by a whole percent between samples.
        let newDigits = newValue.map { "\(Int(($0 * 100).rounded()))" } ?? "–"
        if newDigits != digits {
            digits = newDigits
            let text = NSMutableAttributedString(string: newDigits, attributes: [.font: ResourceMeter.valueFont])
            if newValue != nil {
                text.append(NSAttributedString(string: "%", attributes: [.font: ResourceMeter.percentFont]))
            }
            text.addAttribute(.foregroundColor, value: NSColor.white, range: NSRange(location: 0, length: text.length))
            value.attributedStringValue = text
            needsLayout = true
        }
        fraction = CGFloat(min(max(newValue ?? 0, 0), 1))
        layoutFill(animated: true)
    }

    private func layoutFill(animated: Bool) {
        CATransaction.begin()
        CATransaction.setDisableActions(!animated)
        CATransaction.setAnimationDuration(0.4)
        fill.frame = NSRect(x: 0, y: Self.barY, width: bounds.width * fraction, height: Self.barHeight)
        CATransaction.commit()
    }
}

/// The same meters in SwiftUI, for the customization window.
struct ResourceMetersPreview: View {
    var usage: SystemResources.Usage

    var body: some View {
        HStack(spacing: ResourceMeter.spacing) {
            ForEach(ResourceMeter.allCases, id: \.self) { meter in
                cell(meter, value: meter.value(in: usage))
            }
        }
    }

    private func cell(_ meter: ResourceMeter, value: Double?) -> some View {
        VStack(spacing: 3.5) {
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Text(meter.label)
                    .font(Font(ResourceMeter.labelFont))
                    .foregroundStyle(.white.opacity(0.55))
                    .fixedSize()
                Spacer(minLength: 0)
                Group {
                    if let value {
                        let sign = Text("%").font(Font(ResourceMeter.percentFont))
                        Text("\(Int((value * 100).rounded()))\(sign)")
                    } else {
                        Text("–")
                    }
                }
                .font(Font(ResourceMeter.valueFont))
                .foregroundStyle(.white)
                .fixedSize()
            }
            Capsule()
                .fill(.white.opacity(0.18))
                .overlay(alignment: .leading) {
                    GeometryReader { proxy in
                        Capsule()
                            .fill(Color(nsColor: meter.color))
                            .frame(width: proxy.size.width * (value ?? 0))
                    }
                }
                .frame(height: 3)
        }
        .frame(width: ResourceMeter.width)
        .offset(y: -0.5)
    }
}
