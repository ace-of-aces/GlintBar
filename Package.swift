// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "GlintBar",
    platforms: [.macOS("26.0")],
    products: [
        .executable(name: "GlintBar", targets: ["GlintBar"]),
        .library(name: "GlintBarNowPlaying", type: .dynamic, targets: ["GlintBarNowPlaying"]),
    ],
    targets: [
        // Thin Objective-C shim around the private frameworks GlintBar needs
        // (DFRFoundation, DisplayServices, CoreBrightness, MediaRemote).
        // Everything is resolved at runtime via dlopen/dlsym so a missing
        // symbol degrades a feature instead of crashing the app at launch.
        .target(
            name: "GlintBarPrivate",
            path: "Sources/GlintBarPrivate"
        ),
        // Loaded into /usr/bin/perl by NowPlayingMonitor, never linked into GlintBar:
        // MediaRemote only reports playback state to Apple-signed processes.
        .target(
            name: "GlintBarNowPlaying",
            path: "Sources/GlintBarNowPlaying"
        ),
        .executableTarget(
            name: "GlintBar",
            dependencies: ["GlintBarPrivate"],
            path: "Sources/GlintBar"
        ),
        .testTarget(
            name: "GlintBarTests",
            dependencies: ["GlintBar"],
            path: "Tests/GlintBarTests"
        ),
    ]
)
