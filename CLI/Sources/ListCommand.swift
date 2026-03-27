import ArgumentParser
import Foundation

struct List: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "List recent screenshots"
    )

    @Flag(name: .customLong("today"), help: "Show only today's screenshots")
    var today = false

    @Option(name: [.short, .customLong("limit")], help: "Maximum number of results")
    var limit: Int = 20

    func run() throws {
        let picturesDir = FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let shotterDir = picturesDir.appendingPathComponent("Shotter")

        guard FileManager.default.fileExists(atPath: shotterDir.path) else {
            print("No screenshots found. Save directory: \(shotterDir.path)")
            return
        }

        let files = try FileManager.default.contentsOfDirectory(
            at: shotterDir,
            includingPropertiesForKeys: [.creationDateKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        )

        let imageFiles = files.filter { url in
            let ext = url.pathExtension.lowercased()
            return ["png", "jpg", "jpeg"].contains(ext)
        }

        var filtered = imageFiles

        if today {
            let calendar = Calendar.current
            filtered = filtered.filter { url in
                guard let values = try? url.resourceValues(forKeys: [.creationDateKey]),
                      let date = values.creationDate else { return false }
                return calendar.isDateInToday(date)
            }
        }

        // Sort by creation date (newest first)
        let sorted = filtered.sorted { a, b in
            let dateA = (try? a.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? .distantPast
            let dateB = (try? b.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? .distantPast
            return dateA > dateB
        }

        let results = Array(sorted.prefix(limit))

        if results.isEmpty {
            print("No screenshots found.")
            return
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let byteFormatter = ByteCountFormatter()
        byteFormatter.allowedUnits = [.useKB, .useMB]
        byteFormatter.countStyle = .file

        for url in results {
            let values = try? url.resourceValues(forKeys: [.creationDateKey, .fileSizeKey])
            let date = values?.creationDate.map { formatter.string(from: $0) } ?? "unknown"
            let size = values?.fileSize.map { byteFormatter.string(fromByteCount: Int64($0)) } ?? "?"
            print("\(date)  \(size.padding(toLength: 10, withPad: " ", startingAt: 0))  \(url.lastPathComponent)")
        }

        print("\n\(results.count) screenshot(s) shown")
    }
}
