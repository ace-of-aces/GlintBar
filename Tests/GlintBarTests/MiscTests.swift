import Foundation
import Testing
@testable import GlintBar

struct TimeTextTests {
    @Test(arguments: [
        (0.0, "0:00"), (7.9, "0:07"), (187, "3:07"), (3599, "59:59"), (3753, "1:02:33"), (-4, "0:00"),
    ])
    func formats(seconds: Double, text: String) {
        #expect(BarController.timeText(seconds) == text)
    }
}

struct LevelStepTests {
    @Test func movesOneNotch() {
        #expect(Level.stepped(0.5, by: 1) == 9.0 / 16)
        #expect(Level.stepped(0.5, by: -1) == 7.0 / 16)
    }

    @Test func snapsToTheNearestNotchFirst() {
        // 0.52 is nearest notch 8 of 16.
        #expect(Level.stepped(0.52, by: 1) == 9.0 / 16)
        #expect(Level.stepped(0.52, by: -1) == 7.0 / 16)
    }
}

/// Uses throwaway defaults domains, removed again afterwards.
@Suite(.serialized)
struct MigrationTests {
    private let defaults = UserDefaults.standard
    private let newID = "center.julian.GlintBarTests.new.\(UUID().uuidString)"
    private let oldID = "center.julian.GlintBarTests.old.\(UUID().uuidString)"

    private func cleanUp() {
        defaults.removePersistentDomain(forName: newID)
        defaults.removePersistentDomain(forName: oldID)
    }

    @Test func carriesOldSettingsOver() {
        defer { cleanUp() }
        defaults.setPersistentDomain(["barLayout": ["volume"]], forName: oldID)
        Settings.migrateFromGlint(defaults: defaults, bundleID: newID, oldBundleID: oldID)
        #expect(defaults.persistentDomain(forName: newID)?["barLayout"] as? [String] == ["volume"])
    }

    @Test func leavesExistingSettingsAlone() {
        defer { cleanUp() }
        defaults.setPersistentDomain(["barLayout": ["volume"]], forName: oldID)
        defaults.setPersistentDomain(["barLayout": ["mute"]], forName: newID)
        Settings.migrateFromGlint(defaults: defaults, bundleID: newID, oldBundleID: oldID)
        #expect(defaults.persistentDomain(forName: newID)?["barLayout"] as? [String] == ["mute"])
    }

    @Test func doesNothingWithoutOldSettings() {
        defer { cleanUp() }
        Settings.migrateFromGlint(defaults: defaults, bundleID: newID, oldBundleID: oldID)
        #expect(defaults.persistentDomain(forName: newID) == nil)
    }
}
