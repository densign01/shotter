import ArgumentParser
import AppKit

@main
struct ShotterCLI: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "shotter",
        abstract: "Shotter — screenshot utility with annotation and AI features",
        version: "1.0.0",
        subcommands: [Capture.self, List.self]
    )
}

// MARK: - Capture Command

struct Capture: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Capture a screenshot"
    )

    @Flag(name: [.short, .customLong("fullscreen")], help: "Capture entire screen")
    var fullscreen = false

    @Flag(name: [.short, .customLong("area")], help: "Interactive area selection")
    var area = false

    @Flag(name: [.short, .customLong("window")], help: "Interactive window selection")
    var window = false

    @Flag(name: .customLong("scrolling"), help: "Scrolling capture of a window")
    var scrolling = false

    @Flag(name: [.short, .customLong("clipboard")], help: "Copy to clipboard instead of saving")
    var clipboard = false

    @Option(name: [.short, .customLong("output")], help: "Output file path")
    var output: String?

    @Option(name: .customLong("format"), help: "Output format (png, jpg)")
    var format: String = "png"

    mutating func validate() throws {
        let modeCount = [fullscreen, area, window, scrolling].filter { $0 }.count
        if modeCount == 0 {
            throw ValidationError("Specify a capture mode: --fullscreen, --area, --window, or --scrolling")
        }
        if modeCount > 1 {
            throw ValidationError("Specify only one capture mode")
        }
        if !["png", "jpg", "jpeg"].contains(format.lowercased()) {
            throw ValidationError("Format must be 'png' or 'jpg'")
        }
    }

    mutating func run() throws {
        // Build URL scheme command to send to running Shotter.app
        var mode = "fullscreen"
        if area { mode = "area" }
        if window { mode = "window" }
        if scrolling { mode = "scrolling" }

        // Try to communicate with running Shotter.app via URL scheme
        var components = URLComponents()
        components.scheme = "shotter"
        components.host = "capture"
        components.queryItems = [
            URLQueryItem(name: "mode", value: mode)
        ]

        if clipboard {
            components.queryItems?.append(URLQueryItem(name: "clipboard", value: "true"))
        }
        if let output = output {
            components.queryItems?.append(URLQueryItem(name: "output", value: output))
        }
        components.queryItems?.append(URLQueryItem(name: "format", value: format))

        guard let url = components.url else {
            printError("Failed to build capture URL")
            throw ExitCode.failure
        }

        // Check if Shotter is running
        let runningApps = NSWorkspace.shared.runningApplications
        let shotterRunning = runningApps.contains { $0.bundleIdentifier == "com.densign.shotter" }

        if !shotterRunning {
            printError("Shotter is not running. Please launch Shotter.app first.")
            throw ExitCode.failure
        }

        // Open URL scheme to trigger capture in the main app
        NSWorkspace.shared.open(url)
        print("Capture initiated: \(mode)")
    }
}

// MARK: - List Command

struct List: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "List recent screenshots"
    )

    @Option(name: .customLong("limit"), help: "Maximum number of results")
    var limit: Int = 20

    @Flag(name: .customLong("today"), help: "Only show today's screenshots")
    var today = false

    mutating func run() throws {
        // Read from the default save location
        let picturesURL = FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let saveFolder = picturesURL.appendingPathComponent("Shotter")

        // Check UserDefaults for custom save location
        let defaults = UserDefaults(suiteName: "com.densign.shotter")
        let savePath: URL
        if let customPath = defaults?.string(forKey: "saveLocation") {
            savePath = URL(fileURLWithPath: customPath)
        } else {
            savePath = saveFolder
        }

        guard FileManager.default.fileExists(atPath: savePath.path) else {
            print("No screenshots found at \(savePath.path)")
            return
        }

        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(
            at: savePath,
            includingPropertiesForKeys: [.creationDateKey, .fileSizeKey],
            options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants]
        ) else {
            print("Could not read screenshot directory")
            return
        }

        var files: [(url: URL, date: Date, size: Int64)] = []

        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: Date())

        while let fileURL = enumerator.nextObject() as? URL {
            guard fileURL.pathExtension.lowercased() == "png" || fileURL.pathExtension.lowercased() == "jpg" else {
                continue
            }

            let resourceValues = try? fileURL.resourceValues(forKeys: [.creationDateKey, .fileSizeKey])
            let date = resourceValues?.creationDate ?? Date.distantPast
            let size = Int64(resourceValues?.fileSize ?? 0)

            if today && date < todayStart {
                continue
            }

            files.append((url: fileURL, date: date, size: size))
        }

        // Sort by date descending
        files.sort { $0.date > $1.date }

        // Limit results
        let limited = files.prefix(limit)

        if limited.isEmpty {
            print("No screenshots found")
            return
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"

        for file in limited {
            let dateString = formatter.string(from: file.date)
            let sizeString = ByteCountFormatter.string(fromByteCount: file.size, countStyle: .file)
            print("\(dateString)  \(sizeString.padding(toLength: 10, withPad: " ", startingAt: 0))  \(file.url.lastPathComponent)")
        }

        print("\n\(limited.count) screenshot(s)")
    }
}

// MARK: - Helpers

private func printError(_ message: String) {
    FileHandle.standardError.write(Data("Error: \(message)\n".utf8))
}
