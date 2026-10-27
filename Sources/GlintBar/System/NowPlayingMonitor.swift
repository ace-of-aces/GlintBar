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

    /// The position the player last reported, when it was true, and how fast it moves.
    private var reportedElapsed: Double?
    private var reportedAt = Date()
    private var reportedRate: Double = 0

    private var process: Process?
    private var input: Pipe?
    private var pending = Data()
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
        reportedElapsed = position()
        reportedAt = Date()
        reportedRate = isPlaying ? 0 : 1
        self.isPlaying = !isPlaying
        onChange?()
    }

    /// The playback position in seconds, extrapolated from the last report.
    func position(at date: Date = Date()) -> Double? {
        guard let reportedElapsed else { return nil }
        let rate = isPlaying == true ? reportedRate : 0
        let position = reportedElapsed + rate * date.timeIntervalSince(reportedAt)
        return min(max(position, 0), duration ?? .infinity)
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
        // Throwing API: a helper that just died must not take GlintBar down with it.
        try? input.fileHandleForWriting.write(contentsOf: Data("seek \(target)\n".utf8))
        reportedElapsed = target
        reportedAt = Date()
        onChange?()
    }

    // MARK: - Helper process

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
        } catch {
            NSLog("GlintBar: couldn't start now-playing helper: \(error)")
        }
    }

    private func helperExited() {
        process = nil
        input = nil
        pending.removeAll()
        // Without the helper nothing it reported can be trusted, the track included:
        // left alone, a helper that gave up would leave the last song on the bar for good.
        isPlaying = nil
        title = nil
        artist = nil
        duration = nil
        reportedElapsed = nil
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
        pending.append(data)
        while let newline = pending.firstIndex(of: UInt8(ascii: "\n")) {
            let line = pending[pending.startIndex..<newline]
            pending.removeSubrange(pending.startIndex...newline)
            guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else { continue }
            if let error = object["error"] as? String {
                NSLog("GlintBar: now-playing helper: \(error)")
                continue
            }
            failures = 0
            isPlaying = object["playing"] as? Bool
            title = object["title"] as? String
            artist = object["artist"] as? String
            duration = object["duration"] as? Double
            reportedElapsed = object["elapsed"] as? Double
            reportedRate = object["rate"] as? Double ?? (isPlaying == true ? 1 : 0)
            reportedAt = (object["timestamp"] as? Double).map(Date.init(timeIntervalSince1970:)) ?? Date()
            onChange?()
        }
    }
}
