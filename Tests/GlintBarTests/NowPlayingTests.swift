import Foundation
import Testing

@testable import GlintBar

struct NowPlayingTests {
    @Test func linesAreHandedOutWhole() {
        var buffer = LineBuffer()
        #expect(buffer.append(Data("{\"a\":".utf8)).isEmpty)
        #expect(buffer.append(Data("1}\n{\"b\":2}\n{\"c\"".utf8)) == [Data("{\"a\":1}".utf8), Data("{\"b\":2}".utf8)])
        #expect(buffer.append(Data(":3}\n".utf8)) == [Data("{\"c\":3}".utf8)])
    }

    @Test func readsAState() {
        let line = Data(
            #"{"playing":true,"title":"Song","artist":"Band","duration":200,"elapsed":12.5,"rate":1,"timestamp":1000}"#
                .utf8)
        #expect(
            NowPlayingReport(line: line)
                == .state(
                    .init(
                        isPlaying: true, title: "Song", artist: "Band", duration: 200,
                        playhead: Playhead(elapsed: 12.5, at: Date(timeIntervalSince1970: 1000), rate: 1)
                    )))
    }

    @Test func missingRateAndTimestampFollowThePlayState() {
        let now = Date(timeIntervalSince1970: 50)
        let playing = NowPlayingReport(line: Data(#"{"playing":true,"elapsed":3}"#.utf8), receivedAt: now)
        #expect(playing == .state(.init(isPlaying: true, playhead: Playhead(elapsed: 3, at: now, rate: 1))))
        let paused = NowPlayingReport(line: Data(#"{"playing":false,"elapsed":3}"#.utf8), receivedAt: now)
        #expect(paused == .state(.init(isPlaying: false, playhead: Playhead(elapsed: 3, at: now, rate: 0))))
    }

    @Test func nothingPlayingHasNoPlayhead() {
        #expect(NowPlayingReport(line: Data(#"{"playing":false}"#.utf8)) == .state(.init(isPlaying: false)))
    }

    @Test func readsErrorsAndSkipsGarbage() {
        #expect(
            NowPlayingReport(line: Data(#"{"error":"MediaRemote unavailable"}"#.utf8))
                == .error("MediaRemote unavailable"))
        #expect(NowPlayingReport(line: Data("not json".utf8)) == nil)
        #expect(NowPlayingReport(line: Data("[1,2]".utf8)) == nil)
    }

    @Test func positionMovesOnlyWhilePlaying() {
        let start = Date(timeIntervalSince1970: 0)
        let playhead = Playhead(elapsed: 10, at: start, rate: 1)
        let later = start.addingTimeInterval(5)
        #expect(playhead.position(at: later, isPlaying: true, duration: 100) == 15)
        #expect(playhead.position(at: later, isPlaying: false, duration: 100) == 10)
        #expect(Playhead(elapsed: 10, at: start, rate: 2).position(at: later, isPlaying: true, duration: 100) == 20)
    }

    @Test func positionStaysWithinTheTrack() {
        let start = Date(timeIntervalSince1970: 0)
        #expect(
            Playhead(elapsed: 98, at: start, rate: 1).position(
                at: start.addingTimeInterval(5), isPlaying: true, duration: 100) == 100)
        #expect(
            Playhead(elapsed: 2, at: start, rate: -1).position(
                at: start.addingTimeInterval(5), isPlaying: true, duration: 100) == 0)
        #expect(
            Playhead(elapsed: 2, at: start, rate: 1).position(
                at: start.addingTimeInterval(5), isPlaying: true, duration: nil) == 7)
    }
}
