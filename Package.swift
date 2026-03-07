// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CodexMenubar",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "CodexMenubarCore", targets: ["CodexMenubarCore"]),
        .executable(name: "CodexMenubarApp", targets: ["CodexMenubarApp"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-testing.git", from: "0.8.0")
    ],
    targets: [
        .target(
            name: "CodexMenubarCore",
            path: "Sources/CodexMenubarCore"
        ),
        .executableTarget(
            name: "CodexMenubarApp",
            dependencies: ["CodexMenubarCore"],
            path: "Sources/CodexMenubarApp",
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "CodexMenubarCoreTests",
            dependencies: [
                "CodexMenubarCore",
                .product(name: "Testing", package: "swift-testing")
            ],
            path: "Tests/CodexMenubarCoreTests"
        )
    ]
)
