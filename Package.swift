// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Glint",
    platforms: [.macOS("26.0")],
    products: [
        .executable(name: "Glint", targets: ["Glint"]),
        .library(name: "GlintNowPlaying", type: .dynamic, targets: ["GlintNowPlaying"]),
    ],
    targets: [
        // Thin Objective-C shim around the private frameworks Glint needs
        // (DFRFoundation, DisplayServices, CoreBrightness, MediaRemote).
        // Everything is resolved at runtime via dlopen/dlsym so a missing
        // symbol degrades a feature instead of crashing the app at launch.
        .target(
            name: "GlintPrivate",
            path: "Sources/GlintPrivate"
        ),
        // Loaded into /usr/bin/perl by NowPlayingMonitor, never linked into Glint:
        // MediaRemote only reports playback state to Apple-signed processes.
        .target(
            name: "GlintNowPlaying",
            path: "Sources/GlintNowPlaying"
        ),
        .executableTarget(
            name: "Glint",
            dependencies: ["GlintPrivate"],
            path: "Sources/Glint"
        ),
    ]
)
