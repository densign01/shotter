import ArgumentParser
import AppKit
import ScreenCaptureKit
import Foundation

struct Capture: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Capture a screenshot"
    )

    @Flag(name: [.short, .customLong("fullscreen")], help: "Capture entire screen")
    var fullscreen = false

    @Option(name: [.short, .customLong("window")], help: "Capture window by name")
    var windowName: String?

    @Option(name: .customLong("window-pid"), help: "Capture window by PID")
    var windowPID: Int?

    @Flag(name: [.short, .customLong("clipboard")], help: "Copy to clipboard instead of saving")
    var clipboard = false

    @Option(name: [.short, .customLong("output")], help: "Output file path")
    var output: String?

    @Option(name: .customLong("format"), help: "Output format (png, jpg)")
    var format: String = "png"

    @Option(name: .customLong("quality"), help: "JPEG quality (1-100)")
    var quality: Int = 90

    mutating func run() async throws {
        // Need to ensure we have screen recording permission
        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
        } catch {
            throw CLIError.noPermission(
                "Screen recording permission required. Grant access in System Settings > Privacy & Security > Screen Recording."
            )
        }

        let image: CGImage

        if let windowName = windowName {
            image = try await captureWindowByName(windowName, content: content)
        } else if let pid = windowPID {
            image = try await captureWindowByPID(pid_t(pid), content: content)
        } else {
            // Default to fullscreen
            image = try await captureFullscreen(content: content)
        }

        if clipboard {
            try copyToClipboard(image)
            print("Screenshot copied to clipboard")
        } else {
            let url = try saveImage(image)
            print("Screenshot saved to: \(url.path)")
        }
    }

    private func captureFullscreen(content: SCShareableContent) async throws -> CGImage {
        guard let display = content.displays.first else {
            throw CLIError.captureError("No display available")
        }

        let filter = SCContentFilter(display: display, excludingWindows: [])
        let config = SCStreamConfiguration()

        let scaleFactor = NSScreen.main?.backingScaleFactor ?? 2.0
        config.width = Int(CGFloat(display.width) * scaleFactor)
        config.height = Int(CGFloat(display.height) * scaleFactor)
        config.scalesToFit = false
        config.showsCursor = false

        return try await SCScreenshotManager.captureImage(
            contentFilter: filter,
            configuration: config
        )
    }

    private func captureWindowByName(_ name: String, content: SCShareableContent) async throws -> CGImage {
        let matchingWindows = content.windows.filter { window in
            window.title?.localizedCaseInsensitiveContains(name) == true
        }

        guard let window = matchingWindows.first else {
            throw CLIError.captureError("No window found matching '\(name)'")
        }

        return try await captureWindow(window)
    }

    private func captureWindowByPID(_ pid: pid_t, content: SCShareableContent) async throws -> CGImage {
        let matchingWindows = content.windows.filter { window in
            window.owningApplication?.processID == pid
        }

        guard let window = matchingWindows.first else {
            throw CLIError.captureError("No window found for PID \(pid)")
        }

        return try await captureWindow(window)
    }

    private func captureWindow(_ window: SCWindow) async throws -> CGImage {
        let scaleFactor = NSScreen.main?.backingScaleFactor ?? 2.0
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let config = SCStreamConfiguration()

        config.width = Int(window.frame.width * scaleFactor)
        config.height = Int(window.frame.height * scaleFactor)
        config.scalesToFit = false
        config.showsCursor = false
        config.shouldBeOpaque = false

        return try await SCScreenshotManager.captureImage(
            contentFilter: filter,
            configuration: config
        )
    }

    private func copyToClipboard(_ image: CGImage) throws {
        let nsImage = NSImage(cgImage: image, size: .zero)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        guard let tiffData = nsImage.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:]) else {
            throw CLIError.captureError("Failed to convert image for clipboard")
        }

        pasteboard.declareTypes([.png, .tiff], owner: nil)
        pasteboard.setData(pngData, forType: .png)
        pasteboard.setData(tiffData, forType: .tiff)
    }

    private func saveImage(_ image: CGImage) throws -> URL {
        let nsImage = NSImage(cgImage: image, size: .zero)

        guard let tiffData = nsImage.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData) else {
            throw CLIError.captureError("Failed to convert image")
        }

        let fileData: Data
        let ext: String

        if format.lowercased() == "jpg" || format.lowercased() == "jpeg" {
            guard let jpegData = bitmap.representation(using: .jpeg, properties: [.compressionFactor: NSNumber(value: Float(quality) / 100.0)]) else {
                throw CLIError.captureError("Failed to create JPEG data")
            }
            fileData = jpegData
            ext = "jpg"
        } else {
            guard let pngData = bitmap.representation(using: .png, properties: [:]) else {
                throw CLIError.captureError("Failed to create PNG data")
            }
            fileData = pngData
            ext = "png"
        }

        let url: URL
        if let outputPath = output {
            url = URL(fileURLWithPath: outputPath)
        } else {
            // Default: save to ~/Pictures/Shotter/ with timestamp name
            let picturesDir = FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask).first
                ?? FileManager.default.temporaryDirectory
            let shotterDir = picturesDir.appendingPathComponent("Shotter")
            try FileManager.default.createDirectory(at: shotterDir, withIntermediateDirectories: true)

            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd-HHmmss-SSS"
            let filename = "Shotter-\(formatter.string(from: Date())).\(ext)"
            url = shotterDir.appendingPathComponent(filename)
        }

        try fileData.write(to: url)
        return url
    }
}

enum CLIError: Error, CustomStringConvertible {
    case noPermission(String)
    case captureError(String)

    var description: String {
        switch self {
        case .noPermission(let msg): return "Permission error: \(msg)"
        case .captureError(let msg): return "Capture error: \(msg)"
        }
    }
}
