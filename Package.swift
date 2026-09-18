// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "EngineForKeychron",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "EngineForKeychron", targets: ["EngineForKeychron"]),
        .executable(name: "engine-cli", targets: ["engine-cli"]),
        .library(name: "KeychronKit", targets: ["KeychronKit"]),
    ],
    targets: [
        // Device access and protocol logic. No UI code, so it can be unit-tested and reused.
        .target(
            name: "KeychronKit",
            linkerSettings: [.linkedFramework("IOKit"), .linkedFramework("CoreBluetooth")]
        ),
        // The SwiftUI app.
        .executableTarget(name: "EngineForKeychron", dependencies: ["KeychronKit"]),
        // Hardware diagnostics against a connected mouse.
        .executableTarget(name: "engine-cli", dependencies: ["KeychronKit"]),
        .testTarget(name: "KeychronKitTests", dependencies: ["KeychronKit"]),
    ]
)
