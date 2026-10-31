import Foundation
import Testing

@testable import GlintBar

@MainActor
struct BarItemKindTests {
    private static var catalog: [BarItemKind] { PaletteSection.all.flatMap(\.kinds).filter { $0 != .app(nil) } }

    @Test func everyPaletteItemSurvivesSaving() {
        for kind in Self.catalog {
            #expect(BarItemKind(rawValue: kind.rawValue) == kind, "\(kind) doesn't load back")
        }
    }

    @Test func defaultLayoutSurvivesSaving() {
        for kind in BarConfiguration.defaultKinds {
            #expect(BarItemKind(rawValue: kind.rawValue) == kind)
        }
    }

    @Test func paletteOffersEachItemOnce() {
        let names = Self.catalog.map(\.rawValue)
        #expect(Set(names).count == names.count)
    }

    /// Changing one of these loses the item from every saved layout.
    @Test func savedNamesStayTheSame() {
        let names = Self.catalog.map(\.rawValue).sorted()
        #expect(
            names == [
                "appControls", "apps", "battery", "clock", "displayBrightness", "displayBrightnessDown",
                "displayBrightnessUp", "flexibleSpace", "inputSources", "keyboardBrightness",
                "keyboardBrightnessDown", "keyboardBrightnessUp", "lockScreen", "missionControl", "mute",
                "nextTrack", "nightShift", "nowPlaying", "playPause", "previousTrack", "quickActions",
                "screenSaver", "screenshot", "showDesktop", "siri", "sleep", "space", "spotlight",
                "systemResources", "volume", "volumeDown", "volumeUp",
            ])
    }

    @Test func appButtonsSurviveSaving() {
        let safari = BarItemKind.launching(URL(fileURLWithPath: "/Applications/Safari.app"))
        #expect(safari.rawValue == "app:/Applications/Safari.app")
        #expect(BarItemKind(rawValue: safari.rawValue) == safari)
    }

    @Test func appButtonsCompareEqualHoweverTheyWerePicked() {
        let picked = BarItemKind.launching(URL(fileURLWithPath: "/Applications/Tools/../Example.app/"))
        let dropped = BarItemKind.launching(URL(fileURLWithPath: "/Applications/Example.app"))
        #expect(picked == dropped)
    }

    @Test func flexibleSpaceBackgroundsSurviveSaving() {
        #expect(BarItemKind.flexibleSpace(nil).rawValue == "flexibleSpace")
        #expect(BarItemKind.flexibleSpace(.blackHole).rawValue == "flexibleSpace:blackHole")
        for background in [nil] + SpaceBackground.allCases.map(Optional.some) {
            let kind = BarItemKind.flexibleSpace(background)
            #expect(BarItemKind(rawValue: kind.rawValue) == kind)
        }
    }

    /// Changing one of these loses the background from every saved layout.
    @Test func savedBackgroundNamesStayTheSame() {
        #expect(SpaceBackground.allCases.map(\.rawValue).sorted() == ["blackHole", "midnightSky", "prism"])
    }

    @Test func unknownBackgroundsLeaveTheSpacePlain() {
        #expect(BarItemKind(rawValue: "flexibleSpace:aurora") == .flexibleSpace(nil))
        #expect(BarItemKind(rawValue: "flexibleSpace:") == .flexibleSpace(nil))
    }

    @Test func flexibleSpacesWithBackgroundsAreStillSpacers() {
        let kind = BarItemKind.flexibleSpace(.prism)
        #expect(kind.isSpacer && kind.isFlexibleSpace && !kind.isUnique)
        #expect(kind.background == .prism)
        #expect(kind.title == "Flexible Space")
        #expect(BarItemKind.space.background == nil && !BarItemKind.space.isFlexibleSpace)
    }

    @Test func unknownNamesAreSkipped() {
        #expect(BarItemKind(rawValue: "notAnItem") == nil)
        #expect(BarItemKind(rawValue: "app:") == nil)
    }
}
