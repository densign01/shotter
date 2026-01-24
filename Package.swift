// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Shotter",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "Shotter",
            path: "Shotter/Sources",
            resources: [
                .process("../Resources")
            ]
        )
    ]
)
