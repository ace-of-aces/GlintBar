import Foundation
import Observation

/// The user's arrangement of the Glint bar, saved in user defaults.
@MainActor
@Observable
final class BarConfiguration {
    static let shared = BarConfiguration()

    /// Matches the original fixed layout.
    static let defaultKinds: [BarItemKind] = [
        .appControls, .space, .previousTrack, .playPause, .nextTrack,
        .flexibleSpace,
        .keyboardBrightness, .displayBrightness, .volume, .mute, .space, .screenshot, .siri,
    ]

    private(set) var items: [BarItem]

    /// A transient arrangement shown on the Touch Bar while an item is being dragged
    /// in the customization window. Never saved.
    var previewKinds: [BarItemKind]? {
        didSet { if previewKinds != oldValue { onChange?() } }
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

    func restoreDefaults() {
        setItems(Self.defaultKinds.map { BarItem($0) })
    }

    var isDefault: Bool { kinds == Self.defaultKinds }

    private func save() {
        UserDefaults.standard.set(kinds.map(\.rawValue), forKey: Self.key)
        onChange?()
    }
}
