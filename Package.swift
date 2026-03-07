// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "codex-switcher",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "CodexSwitcherCore", targets: ["CodexSwitcherCore"]),
        .executable(name: "codex-switcher", targets: ["CodexSwitcherApp"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-testing.git", from: "0.8.0")
    ],
    targets: [
        .target(
            name: "CodexSwitcherCore",
            path: "Sources/CodexSwitcherCore"
        ),
        .executableTarget(
            name: "CodexSwitcherApp",
            dependencies: ["CodexSwitcherCore"],
            path: "Sources/CodexSwitcherApp"
        ),
        .testTarget(
            name: "CodexSwitcherCoreTests",
            dependencies: [
                "CodexSwitcherCore",
                .product(name: "Testing", package: "swift-testing")
            ],
            path: "Tests/CodexSwitcherCoreTests"
        )
    ]
)
