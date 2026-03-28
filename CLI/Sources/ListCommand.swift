import ArgumentParser
import Foundation

struct ListCmd: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "list",
        abstract: "List recent screenshots"
    )

    @Option(name: .customLong("limit"), help: "Maximum number of results")
    var limit: Int = 20

    @Flag(name: .customLong("today"), help: "Show only today's screenshots")
    var today = false

    @Option(name: .customLong("dir"), help: "Screenshots directory")
    var directory: String?

    mutating func run() throws {
        let searchDir: URL
        if let dir = directory {
            searchDir = URL(fileURLWithPath: dir)
        } else {
            // Default: ~/Pictures/Shotter/
            let picturesURL = FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask).first
                ?? FileManager.default.homeDirectoryForCurrentUser
            searchDir = picturesURL.appendingPathComponent("Shotter")
        }

        guard FileManager.default.fileExists(atPath: searchDir.path) else {
            fputs("Directory not found: \(searchDir.path)\n", stderr)
            throw ExitCode.failure
        }

        let fileManager = FileManager.default
        let contents = try fileManager.contentsOfDirectory(
            at: searchDir,
            includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        )

        var screenshots = contents.filter { url in
            let ext = url.pathExtension.lowercased()
            return ["png", "jpg", "jpeg"].contains(ext)
        }

        // Sort by modification date (newest first)
        screenshots.sort { a, b in
            let dateA = (try? a.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? Date.distantPast
            let dateB = (try? b.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? Date.distantPast
            return dateA > dateB
        }

        // Filter to today if requested
        if today {
            let calendar = Calendar.current
            screenshots = screenshots.filter { url in
                guard let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate else {
                    return false
                }
                return calendar.isDateInToday(date)
            }
        }

        // Apply limit
        let results = screenshots.prefix(limit)

        if results.isEmpty {
            fputs("No screenshots found\n", stderr)
            return
        }

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"

        for url in results {
            let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
            let date = values?.contentModificationDate.map { dateFormatter.string(from: $0) } ?? "Unknown"
            let size = values?.fileSize.map { ByteCountFormatter.string(fromByteCount: Int64($0), countStyle: .file) } ?? "?"

            print("\(date)  \(size.padding(toLength: 10, withPad: " ", startingAt: 0))  \(url.lastPathComponent)")
        }
    }
}
