// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Shotter",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.5.0"),
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.3.0")
    ],
    targets: [
        .executableTarget(
            name: "Shotter",
            dependencies: [
                .product(name: "Sparkle", package: "Sparkle")
            ],
            path: "Shotter/Sources",
            resources: [
                .process("../Resources")
            ]
        ),
        .executableTarget(
            name: "shotter-cli",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ],
            path: "CLI/Sources"
        )
    ]
)
