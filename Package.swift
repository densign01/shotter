// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Shotter",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.5.0")
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
        )
    ]
)
