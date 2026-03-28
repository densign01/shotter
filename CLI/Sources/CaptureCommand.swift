import ArgumentParser
import AppKit
import Foundation

struct Capture: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Capture a screenshot"
    )

    @Flag(name: [.short, .customLong("fullscreen")], help: "Capture entire screen")
    var fullscreen = false

    @Option(name: [.short, .customLong("output")], help: "Output file path")
    var output: String?

    @Option(name: .customLong("format"), help: "Output format (png, jpg)")
    var format: String = "png"

    @Option(name: .customLong("quality"), help: "JPEG quality (1-100)")
    var quality: Int = 90

    @Flag(name: [.short, .customLong("clipboard")], help: "Copy to clipboard instead of saving")
    var clipboard = false

    @Option(name: [.customLong("delay")], help: "Delay in seconds before capture")
    var delay: Double = 0

    mutating func run() throws {
        // Run the async capture on the main run loop
        let semaphore = DispatchSemaphore(value: 0)
        var captureError: Error?

        Task {
            do {
                try await performCapture()
            } catch {
                captureError = error
            }
            semaphore.signal()
        }

        // Run the run loop while waiting (needed for ScreenCaptureKit)
        while semaphore.wait(timeout: .now()) == .timedOut {
            RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.1))
        }

        if let error = captureError {
            throw error
        }
    }

    private func performCapture() async throws {
        if delay > 0 {
            fputs("Capturing in \(Int(delay)) seconds...\n", stderr)
            try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        }

        // Use CGWindowListCreateImage for CLI (doesn't require ScreenCaptureKit entitlements)
        guard let image = CGWindowListCreateImage(
            CGRect.null,
            .optionOnScreenOnly,
            kCGNullWindowID,
            [.bestResolution, .boundsIgnoreFraming]
        ) else {
            throw CLIError.captureFailed("Failed to capture screen")
        }

        let nsImage = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))

        if clipboard {
            copyToClipboard(nsImage)
            fputs("Screenshot copied to clipboard\n", stderr)
            return
        }

        // Determine output path
        let outputURL: URL
        if let output = output {
            outputURL = URL(fileURLWithPath: output)
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd-HHmmss"
            let timestamp = formatter.string(from: Date())
            let filename = "Shotter-\(timestamp).\(format)"
            let desktop = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop")
            outputURL = desktop.appendingPathComponent(filename)
        }

        // Save image
        try saveImage(nsImage, to: outputURL)
        fputs("\(outputURL.path)\n", stdout)
    }

    private func saveImage(_ image: NSImage, to url: URL) throws {
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData) else {
            throw CLIError.captureFailed("Failed to convert image")
        }

        let data: Data
        if format == "jpg" || format == "jpeg" {
            guard let jpegData = bitmap.representation(using: .jpeg, properties: [.compressionFactor: NSNumber(value: Float(quality) / 100.0)]) else {
                throw CLIError.captureFailed("Failed to encode JPEG")
            }
            data = jpegData
        } else {
            guard let pngData = bitmap.representation(using: .png, properties: [:]) else {
                throw CLIError.captureFailed("Failed to encode PNG")
            }
            data = pngData
        }

        // Ensure directory exists
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        try data.write(to: url)
    }

    private func copyToClipboard(_ image: NSImage) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([image])
    }
}

enum CLIError: LocalizedError {
    case captureFailed(String)

    var errorDescription: String? {
        switch self {
        case .captureFailed(let message):
            return message
        }
    }
}
