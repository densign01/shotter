import ArgumentParser
import Foundation

@main
struct ShotterCLI: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "shotter",
        abstract: "Shotter - Screenshot utility for macOS",
        version: "1.0.0",
        subcommands: [Capture.self, List.self]
    )
}
