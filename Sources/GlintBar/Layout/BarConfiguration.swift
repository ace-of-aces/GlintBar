import Foundation
import Observation

/// The user's arrangement of the GlintBar, saved in user defaults.
@MainActor
@Observable
final class BarConfiguration {
    static let shared = BarConfiguration()

    /// Matches the original fixed layout.
    static let defaultKinds: [BarItemKind] = [
        .appControls, .space, .previousTrack, .playPause, .nextTrack,
        .flexibleSpace(nil),
        .keyboardBrightness, .displayBrightness, .volume, .space, .screenshot, .siri,
    ]

    private(set) var items: [BarItem]

    /// A transient arrangement shown on the Touch Bar while an item is being dragged
    /// in the customization window. Never saved. The items keep their ids, so the bar
    /// can tell which flexible space is which.
    var previewItems: [BarItem]? {
        didSet { if previewItems != oldValue { onChange?() } }
    }

    /// Called after every change, for observers outside SwiftUI (the Touch Bar itself).
    @ObservationIgnored var onChange: (() -> Void)?

    private static let key = "barLayout"

    private init() {
        let stored = UserDefaults.standard.stringArray(forKey: Self.key)?.compactMap(BarItemKind.init(rawValue:))
        items = (stored ?? Self.defaultKinds).map { BarItem($0) }
    }

    var kinds: [BarItemKind] { items.map(\.kind) }

    func contains(_ kind: BarItemKind) -> Bool {
        items.contains { $0.kind == kind }
    }

    /// Whether `kind` can be added: unique items only once, and only if it still fits.
    func canAdd(_ kind: BarItemKind, width: CGFloat) -> Bool {
        !(kind.isUnique && contains(kind)) && BarLayout.fits(kinds + [kind], in: width)
    }

    func setItems(_ newItems: [BarItem]) {
        guard newItems != items else { return }
        items = newItems
        save()
    }

    func remove(_ id: BarItem.ID) {
        setItems(items.filter { $0.id != id })
    }

    /// Gives the flexible space `id` a background (or takes it away), keeping its place.
    func setBackground(_ background: SpaceBackground?, of id: BarItem.ID) {
        setItems(
            items.map { $0.id == id && $0.kind.isFlexibleSpace ? BarItem(.flexibleSpace(background), id: id) : $0 })
    }

    func restoreDefaults() {
        setItems(Self.defaultKinds.map { BarItem($0) })
    }

    var isDefault: Bool { kinds == Self.defaultKinds }

    private func save() {
        UserDefaults.standard.set(kinds.map(\.rawValue), forKey: Self.key)
        onChange?()
    }
}
