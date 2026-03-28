import Foundation
import AppKit

struct FileNaming {
    /// Generate a filename with optional context from the captured window/app
    static func generateFilename(
        appName: String? = nil,
        windowTitle: String? = nil,
        extension ext: String = "png"
    ) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        let timestamp = formatter.string(from: Date())

        // Build descriptive prefix from app/window context
        let prefix = buildPrefix(appName: appName, windowTitle: windowTitle)

        if prefix.isEmpty {
            return "Shotter-\(timestamp).\(ext)"
        } else {
            return "Shotter-\(prefix)-\(timestamp).\(ext)"
        }
    }

    /// Build a sanitized prefix from app name and window title
    private static func buildPrefix(appName: String?, windowTitle: String?) -> String {
        var parts: [String] = []

        if let app = appName, !app.isEmpty {
            parts.append(sanitize(app))
        }

        if let title = windowTitle, !title.isEmpty {
            // Truncate long window titles
            let truncated = String(title.prefix(40))
            let sanitized = sanitize(truncated)
            // Avoid duplicating the app name in the title
            if let app = appName, sanitized.lowercased() != sanitize(app).lowercased() {
                parts.append(sanitized)
            }
        }

        return parts.joined(separator: "-")
    }

    /// Sanitize a string for use in a filename
    private static func sanitize(_ input: String) -> String {
        // Replace problematic characters with hyphens
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_ "))
        let cleaned = input.unicodeScalars
            .map { allowed.contains($0) ? String($0) : "-" }
            .joined()

        // Replace spaces and multiple hyphens
        return cleaned
            .replacingOccurrences(of: " ", with: "-")
            .replacingOccurrences(of: "--+", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }
}
