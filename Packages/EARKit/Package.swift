// swift-tools-version: 6.0
import PackageDescription

// Platform-independent analysis, notebook storage and teaching content for EAR.
// Everything except Audio/AudioFiles.swift (AVFoundation) builds and tests on Linux as well as Apple platforms.
let package = Package(
    name: "EARKit",
    platforms: [.iOS("26.0"), .macOS("15.0")],
    products: [.library(name: "EARKit", targets: ["EARKit"])],
    targets: [
        .target(name: "EARKit", resources: [.process("Resources")]),
        .testTarget(name: "EARKitTests", dependencies: ["EARKit"], resources: [.copy("Fixtures")]),
    ]
)
