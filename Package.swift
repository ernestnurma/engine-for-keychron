// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "EngineForKeychron",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "EngineForKeychron",
            path: "Sources/EngineForKeychron",
            linkerSettings: [.linkedFramework("IOKit")]
        )
    ]
)
