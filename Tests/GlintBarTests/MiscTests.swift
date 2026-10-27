import Foundation
import Testing

@testable import GlintBar

struct TimeTextTests {
    @Test(arguments: [
        (0.0, "0:00"), (7.9, "0:07"), (187, "3:07"), (3599, "59:59"), (3753, "1:02:33"), (-4, "0:00"),
    ])
    func formats(seconds: Double, text: String) {
        #expect(SliderPanelController.timeText(seconds) == text)
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
