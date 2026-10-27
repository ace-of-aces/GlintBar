import SwiftUI
import UniformTypeIdentifiers

/// Drag-and-drop editor for the GlintBar: a true-to-size replica of the Touch Bar
/// above a palette of every item. Drag items in, along, or out of the bar.
struct CustomizeView: View {
    var onDone: () -> Void = {}

    private let configuration = BarConfiguration.shared
    @State var drag: DragSession?
    @State var barFrame = CGRect.zero
    @State var tileFrames: [BarItemKind: CGRect] = [:]
    @State private var hovered: BarItem.ID?
    /// Apps are being dragged in from Finder.
    @State private var isTargetedByFinder = false

    private nonisolated static let space = "customize"
    private let barSize = CGSize(width: BarMetrics.width, height: BarMetrics.height)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.bottom, 24)
            palette
            touchBar
                .padding(.top, 30)
                .padding(.bottom, 10)
            hint
            Divider()
                .padding(.vertical, 20)
            footer
        }
        .padding(.horizontal, 30)
        .padding(.top, 38)
        .padding(.bottom, 24)
        .coordinateSpace(.named(Self.space))
        .overlay(alignment: .topLeading) { ghost }
        .onChange(of: hardwarePreview) { _, kinds in configuration.previewKinds = kinds }
        #if DEBUG
        .onChange(of: CustomizeDebugDriver.shared.generation) { runDebugSteps() }
        #endif
    }

    // MARK: - Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Customize GlintBar")
                .font(.title2.weight(.semibold))
            Text("Drag and drop items into the bar. Your GlintBar updates as you go.")
                .foregroundStyle(.secondary)
        }
    }

    private static let escWidth: CGFloat = 64
    private static let escSpacing: CGFloat = 17
    private static let bezelPadding: CGFloat = 8
    private static let touchBarWidth = escWidth + escSpacing + BarMetrics.width + 2 * bezelPadding

    /// The bar as it sits above the keyboard: Esc, then GlintBar's 1004 pt.
    private var touchBar: some View {
        HStack(spacing: Self.escSpacing) {
            Text("esc")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white.opacity(0.5))
                .frame(width: Self.escWidth, height: BarMetrics.height)
                .background(Color(white: 0.16), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            bar
        }
        .padding(Self.bezelPadding)
        .background(.black, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(.white.opacity(dropIsBlocked ? 0 : (isAdding || isTargetedByFinder ? 0.35 : 0.08)), lineWidth: 1)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(.red.opacity(dropIsBlocked ? 0.7 : 0), lineWidth: 1.5)
        }
        .animation(.easeOut(duration: 0.15), value: isAdding || isTargetedByFinder)
        .animation(.easeOut(duration: 0.15), value: dropIsBlocked)
        .frame(maxWidth: .infinity)
    }

    private var bar: some View {
        let entries = displayedEntries
        return ZStack(alignment: .topLeading) {
            Color.clear
            ForEach(entries) { entry in
                barItem(entry)
            }
        }
        .frame(width: barSize.width, height: barSize.height)
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(Self.space)) } action: { barFrame = $0 }
        .dropDestination(for: URL.self) { urls, location in
            let apps = urls.filter { UTType(filenameExtension: $0.pathExtension)?.conforms(to: .application) ?? false }
            guard !apps.isEmpty else { return false }
            let frames = BarLayout.frames(for: configuration.kinds, in: barSize)
            addApps(apps, at: frames.firstIndex { $0.midX > location.x })
            return true
        } isTargeted: { isTargetedByFinder = $0 }
        .animation(.spring(duration: 0.32, bounce: 0.15), value: entries.map(\.layoutKey))
    }

    private func barItem(_ entry: Entry) -> some View {
        let item = entry.item
        let showsRemove = hovered == item.id && drag == nil
        return ItemPreview(kind: item.kind, width: entry.frame.width)
            .opacity(entry.isHidden ? 0 : (entry.isPlaceholder ? 0.3 : 1))
            .overlay(alignment: .topLeading) {
                Button {
                    remove(item)
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .font(.system(size: 15))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, Color(white: 0.38))
                        .shadow(radius: 1.5)
                }
                .buttonStyle(.plain)
                .offset(x: -7, y: -8)
                .opacity(showsRemove ? 1 : 0)
                .scaleEffect(showsRemove ? 1 : 0.6)
                .animation(.spring(duration: 0.2), value: showsRemove)
                .allowsHitTesting(showsRemove)
            }
            .contentShape(Rectangle())
            .onHover { inside in
                if inside { hovered = item.id } else if hovered == item.id { hovered = nil }
            }
            .contextMenu {
                if item.kind.appURL != nil {
                    Button("Change App…", systemImage: "arrow.left.arrow.right") { changeApp(of: item) }
                }
                Button("Remove \(item.kind.title)", systemImage: "minus.circle") { remove(item) }
            }
            .onTapGesture(count: 2) { changeApp(of: item) }
            .gesture(dragGesture(item: item, source: .bar) {
                CGPoint(x: barFrame.minX + entry.frame.midX, y: barFrame.midY)
            })
            .allowsHitTesting(!entry.isPlaceholder)
            .position(x: entry.frame.midX, y: entry.frame.midY)
    }

    @ViewBuilder private var hint: some View {
        Group {
            switch (drag, dropOutcome) {
            case (let drag?, .blocked?):
                Label("There’s no room for \(drag.item.kind.title). Remove something first.", systemImage: "exclamationmark.circle")
                    .foregroundStyle(.red)
            case (let drag?, .remove?):
                Label("Release to remove \(drag.item.kind.title).", systemImage: "minus.circle")
                    .foregroundStyle(.secondary)
            default:
                Text("Drag items into the GlintBar, drag them along it to rearrange, and drag them out to remove them. Drop apps from Finder to add them.")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.callout)
        .frame(maxWidth: .infinity)
        .animation(nil, value: drag?.location)
    }

    /// Sections side by side, wrapping onto new rows within the width of the bar below.
    private var palette: some View {
        FlowLayout(horizontalSpacing: 56, verticalSpacing: 24) {
            ForEach(PaletteSection.all, id: \.title) { section in
                paletteSection(section)
            }
        }
        .frame(width: Self.touchBarWidth, alignment: .leading)
    }

    private func paletteSection(_ section: PaletteSection) -> some View {
        VStack(alignment: .paletteTile, spacing: 10) {
            Text(section.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            HStack(alignment: .top, spacing: 14) {
                ForEach(section.kinds, id: \.self) { kind in
                    tile(kind, alignsTitle: kind == section.kinds.first)
                }
            }
        }
    }

    /// `alignsTitle` lines the section title up with this tile's black box,
    /// which sits centered when the caption or minimum width is wider.
    private func tile(_ kind: BarItemKind, alignsTitle: Bool = false) -> some View {
        let isUsed = kind.isUnique && configuration.contains(kind)
        let isUnavailable = !kind.isAvailable
        let previewWidth = kind == .flexibleSpace ? 92 : kind.width
        let boxWidth = previewWidth + 20
        return VStack(spacing: 7) {
            ItemPreview(kind: kind, width: previewWidth)
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(Self.space)) } action: { tileFrames[kind] = $0 }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(.black, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            Text(kind.title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .fixedSize()
        }
        .frame(minWidth: 86)
        .modifier(PaletteTileGuide(boxWidth: alignsTitle ? boxWidth : nil))
        .opacity(isUsed || isUnavailable ? 0.38 : 1)
        .help(isUsed ? "Already in the GlintBar"
            : isUnavailable ? "Not available on this Mac right now"
            : kind == .app(nil) ? "Click to choose apps to add, or drag into the GlintBar and pick one. You can also drop apps from Finder onto the bar."
            : "Drag into the GlintBar, or click to add it at the end")
        .contentShape(Rectangle())
        .onTapGesture {
            if kind == .app(nil) {
                AppPicker.chooseApps { addApps($0) }
            } else if !isUsed {
                append(kind)
            }
        }
        .gesture(
            dragGesture(item: BarItem(kind), source: .palette) {
                let frame = tileFrames[kind] ?? .zero
                return CGPoint(x: frame.midX, y: frame.midY)
            },
            including: isUsed ? .none : .all
        )
    }

    private var footer: some View {
        HStack {
            Button("Restore Defaults") {
                withAnimation(.spring(duration: 0.35)) { configuration.restoreDefaults() }
            }
            .disabled(configuration.isDefault)
            Spacer()
            Button("Done", action: onDone)
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.glassProminent)
        }
        .controlSize(.large)
    }

    /// The item following the pointer while dragging.
    @ViewBuilder private var ghost: some View {
        if let drag {
            let kind = drag.item.kind
            let outcome = outcome(of: drag)
            let badge = ghostBadge(outcome, source: drag.source)
            ItemPreview(kind: kind, width: kind == .flexibleSpace ? 92 : kind.width)
                .padding(6)
                .background(.black.opacity(0.92), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                .overlay(alignment: .topTrailing) {
                    if let badge {
                        Image(systemName: badge.symbol)
                            .font(.system(size: 17))
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, badge.color)
                            .offset(x: 7, y: -7)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                .scaleEffect(1.08)
                .opacity(outcome == .remove ? 0.55 : 1)
                .shadow(color: .black.opacity(0.35), radius: 12, y: 6)
                .position(x: drag.location.x - drag.grabOffset.width, y: drag.location.y - drag.grabOffset.height)
                .allowsHitTesting(false)
                .animation(.spring(duration: 0.2), value: badge?.symbol)
        }
    }

    // MARK: - Dragging

    struct DragSession {
        enum Source { case bar, palette }
        var item: BarItem
        var source: Source
        /// Pointer location in the window's coordinate space.
        var location: CGPoint
        /// Pointer offset from the item's centre, so the item doesn't jump under it.
        var grabOffset: CGSize
    }

    private func dragGesture(item: BarItem, source: DragSession.Source, center: @escaping () -> CGPoint) -> some Gesture {
        DragGesture(minimumDistance: 3, coordinateSpace: .named(Self.space))
            .onChanged { value in
                if drag == nil {
                    let origin = center()
                    hovered = nil
                    drag = DragSession(
                        item: item,
                        source: source,
                        location: value.location,
                        grabOffset: CGSize(width: value.startLocation.x - origin.x, height: value.startLocation.y - origin.y)
                    )
                } else {
                    drag?.location = value.location
                }
            }
            .onEnded { _ in finishDrag() }
    }

    func finishDrag() {
        guard let drag else { return }
        let outcome = outcome(of: drag)
        if drag.item.kind == .app(nil) {
            // The palette's App tile: leave its slot open while the user picks the app.
            if case .insert(let index) = outcome { AppPicker.chooseApps { addApps($0, at: index) } }
            withAnimation(.spring(duration: 0.32, bounce: 0.15)) { self.drag = nil }
            configuration.previewKinds = nil
            return
        }
        withAnimation(.spring(duration: 0.32, bounce: 0.15)) {
            switch outcome {
            case .insert(let index):
                var items = baseItems(for: drag)
                items.insert(drag.item, at: index)
                configuration.setItems(items)
            case .remove:
                configuration.remove(drag.item.id)
            case .blocked, .cancel:
                break
            }
            self.drag = nil
        }
        configuration.previewKinds = nil
    }

    /// What letting go of the dragged item would do.
    enum DropOutcome: Equatable {
        case insert(at: Int)
        /// Over the bar, but there's no room for it.
        case blocked
        /// A bar item dragged off the bar.
        case remove
        /// A palette item dragged off the bar.
        case cancel
    }

    private func outcome(of drag: DragSession) -> DropOutcome {
        // The bar's hit area for drops; generous vertically so it's easy to aim for.
        guard barFrame.insetBy(dx: -16, dy: -40).contains(drag.location) else {
            return drag.source == .bar ? .remove : .cancel
        }
        let base = baseItems(for: drag).map(\.kind)
        guard BarLayout.fits(base + [drag.item.kind], in: barSize.width) else { return .blocked }
        let centerX = drag.location.x - drag.grabOffset.width - barFrame.minX
        let frames = BarLayout.frames(for: base, in: barSize)
        return .insert(at: frames.firstIndex { $0.midX > centerX } ?? base.count)
    }

    private var dropOutcome: DropOutcome? { drag.map(outcome(of:)) }

    /// The bar's items without the one being dragged.
    private func baseItems(for drag: DragSession) -> [BarItem] {
        configuration.items.filter { $0.id != drag.item.id }
    }

    private var isAdding: Bool {
        if case .insert? = dropOutcome { true } else { false }
    }

    private var dropIsBlocked: Bool { dropOutcome == .blocked }

    private func ghostBadge(_ outcome: DropOutcome, source: DragSession.Source) -> (symbol: String, color: Color)? {
        switch outcome {
        case .blocked: ("nosign", .red)
        case .remove: ("minus.circle.fill", Color(white: 0.38))
        case .insert where source == .palette: ("plus.circle.fill", .green)
        case .insert, .cancel: nil
        }
    }

    // MARK: - Displayed bar

    struct Entry: Identifiable {
        let item: BarItem
        var frame: CGRect
        var isPlaceholder = false
        /// The dragged item while it's off the bar: kept (invisibly) so its view and
        /// gesture survive.
        var isHidden = false
        var id: BarItem.ID { item.id }
        var layoutKey: String { "\(item.id)\(frame.minX)\(frame.width)" }
    }

    /// The bar as it would look if the current drag ended now.
    var displayedEntries: [Entry] {
        var entries = configuration.items.map { Entry(item: $0, frame: .zero) }
        if let drag {
            let original = entries.firstIndex { $0.id == drag.item.id }
            entries.removeAll { $0.id == drag.item.id }
            if case .insert(let index) = outcome(of: drag) {
                entries.insert(Entry(item: drag.item, frame: .zero, isPlaceholder: true), at: index)
            } else if let original {
                entries.insert(Entry(item: drag.item, frame: .zero, isHidden: true), at: original)
            }
        }
        let visible = entries.filter { !$0.isHidden }
        let frames = BarLayout.frames(for: visible.map(\.item.kind), in: barSize)
        var x: CGFloat = 0
        var next = frames.makeIterator()
        for index in entries.indices {
            if entries[index].isHidden {
                entries[index].frame = CGRect(x: x, y: 0, width: 0, height: barSize.height)
            } else if let frame = next.next() {
                entries[index].frame = frame
                x = frame.maxX
            }
        }
        return entries
    }

    /// What the real Touch Bar shows during a drag: the would-be result.
    private var hardwarePreview: [BarItemKind]? {
        guard drag != nil else { return nil }
        return displayedEntries.filter { !$0.isHidden }.map(\.item.kind)
    }

    // MARK: - Editing

    private func remove(_ item: BarItem) {
        withAnimation(.spring(duration: 0.32, bounce: 0.15)) {
            configuration.remove(item.id)
            hovered = nil
        }
    }

    /// Adds a button for each of `apps` at `index` (the end if nil), skipping apps
    /// already in the bar; beeps for any that are skipped or don't fit.
    private func addApps(_ apps: [URL], at index: Int? = nil) {
        var items = configuration.items
        var position = min(index ?? items.count, items.count)
        var added = 0
        for app in apps {
            let kind = BarItemKind.launching(app)
            guard !items.contains(where: { $0.kind == kind }),
                  BarLayout.fits(items.map(\.kind) + [kind], in: barSize.width) else { continue }
            items.insert(BarItem(kind), at: position)
            position += 1
            added += 1
        }
        if added < apps.count { NSSound.beep() }
        guard added > 0 else { return }
        withAnimation(.spring(duration: 0.32, bounce: 0.15)) {
            configuration.setItems(items)
        }
    }

    /// Lets the user pick a different app for an app button, in place.
    private func changeApp(of item: BarItem) {
        guard let current = item.kind.appURL else { return }
        AppPicker.chooseReplacement(for: current) { app in
            let kind = BarItemKind.launching(app)
            guard kind != item.kind else { return }
            guard !configuration.contains(kind) else {
                NSSound.beep()
                return
            }
            configuration.setItems(configuration.items.map { $0.id == item.id ? BarItem(kind, id: item.id) : $0 })
        }
    }

    private func append(_ kind: BarItemKind) {
        guard configuration.canAdd(kind, width: barSize.width) else {
            NSSound.beep()
            return
        }
        withAnimation(.spring(duration: 0.32, bounce: 0.15)) {
            configuration.setItems(configuration.items + [BarItem(kind)])
        }
    }
}

private extension HorizontalAlignment {
    private enum PaletteTile: AlignmentID {
        static func defaultValue(in d: ViewDimensions) -> CGFloat { d[.leading] }
    }

    /// The leading edge of a section's first tile box, which its title aligns to.
    static let paletteTile = HorizontalAlignment(PaletteTile.self)
}

/// Sets the `.paletteTile` guide on a section's first tile only: an `HStack`
/// averages the guides its children set explicitly.
private struct PaletteTileGuide: ViewModifier {
    let boxWidth: CGFloat?

    func body(content: Content) -> some View {
        if let boxWidth {
            content.alignmentGuide(.paletteTile) { max(0, ($0.width - boxWidth) / 2) }
        } else {
            content
        }
    }
}

/// Lays subviews out left to right, starting a new row when the next one
/// wouldn't fit the proposed width.
private struct FlowLayout: Layout {
    var horizontalSpacing: CGFloat
    var verticalSpacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let frames = frames(for: subviews, width: proposal.width ?? .infinity)
        let union = frames.reduce(CGRect.zero) { $0.union($1) }
        return CGSize(width: union.maxX, height: union.maxY)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for (subview, frame) in zip(subviews, frames(for: subviews, width: bounds.width)) {
            subview.place(at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY), proposal: ProposedViewSize(frame.size))
        }
    }

    private func frames(for subviews: Subviews, width: CGFloat) -> [CGRect] {
        var frames: [CGRect] = []
        var origin = CGPoint.zero
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if origin.x > 0, origin.x + size.width > width {
                origin = CGPoint(x: 0, y: origin.y + rowHeight + verticalSpacing)
                rowHeight = 0
            }
            frames.append(CGRect(origin: origin, size: size))
            origin.x += size.width + horizontalSpacing
            rowHeight = max(rowHeight, size.height)
        }
        return frames
    }
}

#if DEBUG
/// Drives `CustomizeView`'s drag logic from debug commands (see `BarController.debug`),
/// so drag and drop can be exercised and snapshotted without a mouse.
@MainActor
@Observable
final class CustomizeDebugDriver {
    enum Step {
        case pickUpBarItem(index: Int)
        case pickUpPaletteItem(BarItemKind)
        /// x in bar coordinates.
        case moveOverBar(x: CGFloat)
        case moveOffBar
        case drop
    }

    static let shared = CustomizeDebugDriver()
    private(set) var pending: [Step] = []
    private(set) var generation = 0

    func perform(_ step: Step) {
        pending.append(step)
        generation += 1
    }

    func takeSteps() -> [Step] {
        defer { pending = [] }
        return pending
    }
}

extension CustomizeView {
    func runDebugSteps() {
        for step in CustomizeDebugDriver.shared.takeSteps() {
            switch step {
            case .pickUpBarItem(let index):
                let entries = displayedEntries
                guard entries.indices.contains(index) else { continue }
                let center = CGPoint(x: barFrame.minX + entries[index].frame.midX, y: barFrame.midY)
                drag = DragSession(item: entries[index].item, source: .bar, location: center, grabOffset: .zero)
            case .pickUpPaletteItem(let kind):
                let frame = tileFrames[kind] ?? .zero
                drag = DragSession(item: BarItem(kind), source: .palette, location: CGPoint(x: frame.midX, y: frame.midY), grabOffset: .zero)
            case .moveOverBar(let x):
                drag?.location = CGPoint(x: barFrame.minX + x, y: barFrame.midY)
            case .moveOffBar:
                drag?.location = CGPoint(x: barFrame.midX, y: barFrame.maxY + 160)
            case .drop:
                finishDrag()
            }
        }
    }
}
#endif
