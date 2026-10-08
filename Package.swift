// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Glint",
    platforms: [.macOS("26.0")],
    targets: [
        // Thin Objective-C shim around the private frameworks Glint needs
        // (DFRFoundation, DisplayServices, CoreBrightness, MediaRemote).
        // Everything is resolved at runtime via dlopen/dlsym so a missing
        // symbol degrades a feature instead of crashing the app at launch.
        .target(
            name: "GlintPrivate",
            path: "Sources/GlintPrivate"
        ),
        .executableTarget(
            name: "Glint",
            dependencies: ["GlintPrivate"],
            path: "Sources/Glint"
        ),
    ]
)
