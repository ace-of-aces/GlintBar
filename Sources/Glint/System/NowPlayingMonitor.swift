import Foundation

/// Tracks whether something is playing, via the GlintNowPlaying helper library
/// hosted in /usr/bin/perl (see GlintNowPlaying.m for why).
@MainActor
final class NowPlayingMonitor {
    static let shared = NowPlayingMonitor()

    /// nil while unknown (helper not running yet, or unavailable).
    private(set) var isPlaying: Bool?
    private(set) var title: String?
    private(set) var artist: String?
    var onChange: (() -> Void)?

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
        self.isPlaying = !isPlaying
        onChange?()
    }

    // MARK: - Helper process

    /// The helper library: inside Glint.app, or next to the executable for `swift run`.
    private static var libraryURL: URL? {
        let name = "libGlintNowPlaying.dylib"
        let candidates = [
            Bundle.main.privateFrameworksURL?.appendingPathComponent(name),
            Bundle.main.executableURL?.deletingLastPathComponent().appendingPathComponent(name),
        ]
        return candidates.compactMap { $0 }.first { FileManager.default.fileExists(atPath: $0.path) }
    }

    private func launch() {
        guard process == nil, !isStopping else { return }
        guard let library = Self.libraryURL, FileManager.default.isExecutableFile(atPath: Self.perl.path) else {
            NSLog("Glint: now-playing helper unavailable; play/pause state will be unknown")
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
            NSLog("Glint: couldn't start now-playing helper: \(error)")
        }
    }

    private func helperExited() {
        process = nil
        input = nil
        pending.removeAll()
        if isPlaying != nil {
            isPlaying = nil
            onChange?()
        }
        guard !isStopping else { return }

        // Back off if the helper keeps dying (e.g. a future macOS closes this path).
        failures += 1
        guard failures <= 5 else {
            NSLog("Glint: now-playing helper keeps exiting; giving up")
            return
        }
        Task {
            try? await Task.sleep(for: .seconds(Double(failures * failures)))
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
                NSLog("Glint: now-playing helper: \(error)")
                continue
            }
            failures = 0
            isPlaying = object["playing"] as? Bool
            title = object["title"] as? String
            artist = object["artist"] as? String
            onChange?()
        }
    }
}
