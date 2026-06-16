// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Gitify",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "GitKit", targets: ["GitKit"]),
        .executable(name: "Gitify", targets: ["Gitify"]),
    ],
    targets: [
        .target(
            name: "GitKit"
        ),
        .executableTarget(
            name: "Gitify",
            dependencies: ["GitKit"]
        ),
        // Full Xcode (XCTest / swift-testing) isn't installed, so the engine's
        // verification suite runs as a standalone executable harness instead.
        .executableTarget(
            name: "GitKitChecks",
            dependencies: ["GitKit"],
            path: "Tests/GitKitChecks"
        ),
    ]
)
