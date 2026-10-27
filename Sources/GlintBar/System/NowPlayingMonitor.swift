import Foundation

/// Tracks whether something is playing, via the GlintBarNowPlaying helper library
/// hosted in /usr/bin/perl (see GlintBarNowPlaying.m for why).
@MainActor
final class NowPlayingMonitor {
    static let shared = NowPlayingMonitor()

    /// nil while unknown (helper not running yet, or unavailable).
    private(set) var isPlaying: Bool?
    private(set) var title: String?
    private(set) var artist: String?
    /// Track length in seconds, when the player reports one (live streams don't).
    private(set) var duration: Double?
    var onChange: (() -> Void)?

    /// Where the player last said it was.
    private var playhead: Playhead?

    /// Whether anything shows the state right now. While nothing does, the helper stops
    /// its poll (change notifications still come through) and catches up once it's
    /// watched again.
    var isWatched = true {
        didSet { if isWatched != oldValue { sendWatchState() } }
    }

    private var process: Process?
    private var input: Pipe?
    private var pending = LineBuffer()
    private var failures = 0
    private var isStopping = false

    private static let perl = URL(fileURLWithPath: "/usr/bin/perl")
    private static let script = """
        use DynaLoader;
        my $handle = DynaLoader::dl_load_file($ARGV[0], 0) or die DynaLoader::dl_error();
        my $symbol = DynaLoader::dl_find_symbol($handle, "glint_now_playing_stream") or die "missing symbol";
        DynaLoader::dl_install_xsub("main::stream", $symbol);
        stream();
        """

    private init() {}

    func start() {
        isStopping = false
        launch()
    }

    func stop() {
        isStopping = true
        process?.terminate()
    }

    /// Flips the state right away after a play/pause tap; the helper confirms or corrects it.
    func assumeToggled() {
        guard let isPlaying else { return }
        // Freeze or resume the position along with it.
        if let position = position() { playhead = Playhead(elapsed: position, at: Date(), rate: isPlaying ? 0 : 1) }
        self.isPlaying = !isPlaying
        onChange?()
    }

    /// The playback position in seconds, extrapolated from the last report.
    func position(at date: Date = Date()) -> Double? {
        playhead?.position(at: date, isPlaying: isPlaying == true, duration: duration)
    }

    /// Position as a fraction of the track, if both are known.
    var progress: Float? {
        guard let duration, duration > 0, let position = position() else { return nil }
        return Float(position / duration)
    }

    var canSeek: Bool { (duration ?? 0) > 0 && input != nil }

    /// Asks the player to jump to `seconds`. Seeking needs the same standing as reading
    /// the state, so it goes through the helper.
    func seek(to seconds: Double) {
        guard canSeek, let input else { return }
        let target = min(max(seconds, 0), duration ?? seconds)
        send("seek \(target)", to: input)
        playhead = Playhead(elapsed: target, at: Date(), rate: playhead?.rate ?? (isPlaying == true ? 1 : 0))
        onChange?()
    }

    // MARK: - Helper process

    private func sendWatchState() {
        guard let input else { return }
        send(isWatched ? "poll on" : "poll off", to: input)
    }

    private func send(_ command: String, to input: Pipe) {
        // Throwing API: a helper that just died must not take GlintBar down with it.
        try? input.fileHandleForWriting.write(contentsOf: Data("\(command)\n".utf8))
    }

    /// The helper library: inside GlintBar.app, or next to the executable for `swift run`.
    private static var libraryURL: URL? {
        let name = "libGlintBarNowPlaying.dylib"
        let candidates = [
            Bundle.main.privateFrameworksURL?.appendingPathComponent(name),
            Bundle.main.executableURL?.deletingLastPathComponent().appendingPathComponent(name),
        ]
        return candidates.compactMap { $0 }.first { FileManager.default.fileExists(atPath: $0.path) }
    }

    private func launch() {
        guard process == nil, !isStopping else { return }
        guard let library = Self.libraryURL, FileManager.default.isExecutableFile(atPath: Self.perl.path) else {
            NSLog("GlintBar: now-playing helper unavailable; play/pause state will be unknown")
            return
        }

        let process = Process()
        process.executableURL = Self.perl
        process.arguments = ["-e", Self.script, library.path]
        let output = Pipe()
        let input = Pipe()
        process.standardOutput = output
        process.standardInput = input
        process.standardError = FileHandle.nullDevice

        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                handle.readabilityHandler = nil // EOF
                return
            }
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.consume(data) }
            }
        }
        process.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.helperExited() }
            }
        }

        do {
            try process.run()
            self.process = process
            self.input = input
            if !isWatched { sendWatchState() } // a new helper polls
        } catch {
            NSLog("GlintBar: couldn't start now-playing helper: \(error)")
        }
    }

    private func helperExited() {
        process = nil
        input = nil
        pending = LineBuffer()
        // Without the helper nothing it reported can be trusted, the track included:
        // left alone, a helper that gave up would leave the last song on the bar for good.
        isPlaying = nil
        title = nil
        artist = nil
        duration = nil
        playhead = nil
        onChange?()
        guard !isStopping else { return }

        // Back off if the helper keeps dying (e.g. a future macOS closes this path), but
        // never give up for good: whatever kills it may pass, like a player that stops.
        failures += 1
        if failures == 6 {
            NSLog("GlintBar: now-playing helper keeps exiting; retrying every minute")
        }
        Task {
            try? await Task.sleep(for: .seconds(Double(min(failures * failures, 60))))
            launch()
        }
    }

    private func consume(_ data: Data) {
        for line in pending.append(data) {
            switch NowPlayingReport(line: line) {
            case .state(let report)?:
                failures = 0
                isPlaying = report.isPlaying
                title = report.title
                artist = report.artist
                duration = report.duration
                playhead = report.playhead
                onChange?()
            case .error(let error)?:
                NSLog("GlintBar: now-playing helper: \(error)")
            case nil:
                continue
            }
        }
    }
}

/// A playback position the player reported: `elapsed` seconds in at `at`, moving at `rate`.
struct Playhead: Equatable {
    var elapsed: Double
    var at: Date
    var rate: Double

    /// The position at `date`, extrapolated while playing and kept within the track.
    func position(at date: Date, isPlaying: Bool, duration: Double?) -> Double {
        let position = elapsed + (isPlaying ? rate : 0) * date.timeIntervalSince(at)
        return min(max(position, 0), duration ?? .infinity)
    }
}

/// Collects the helper's output and hands it out a whole line at a time.
struct LineBuffer {
    private var pending = Data()

    /// The lines `data` completes, without their newlines.
    mutating func append(_ data: Data) -> [Data] {
        pending.append(data)
        var lines: [Data] = []
        while let newline = pending.firstIndex(of: UInt8(ascii: "\n")) {
            lines.append(Data(pending[pending.startIndex..<newline]))
            pending.removeSubrange(pending.startIndex...newline)
        }
        return lines
    }
}

/// What one line from the helper says.
enum NowPlayingReport: Equatable {
    struct State: Equatable {
        var isPlaying: Bool?
        var title: String?
        var artist: String?
        var duration: Double?
        var playhead: Playhead?
    }

    case state(State)
    case error(String)

    /// nil for a line that isn't a JSON object.
    init?(line: Data, receivedAt: Date = Date()) {
        guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else { return nil }
        if let error = object["error"] as? String {
            self = .error(error)
            return
        }
        let isPlaying = object["playing"] as? Bool
        self = .state(State(
            isPlaying: isPlaying,
            title: object["title"] as? String,
            artist: object["artist"] as? String,
            duration: object["duration"] as? Double,
            playhead: (object["elapsed"] as? Double).map { elapsed in
                Playhead(
                    elapsed: elapsed,
                    at: (object["timestamp"] as? Double).map(Date.init(timeIntervalSince1970:)) ?? receivedAt,
                    rate: object["rate"] as? Double ?? (isPlaying == true ? 1 : 0)
                )
            }
        ))
    }
}
