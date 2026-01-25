import Foundation

struct FileNaming {
    static func generateFilename(extension ext: String = "png") -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmmss-SSS"
        let timestamp = formatter.string(from: Date())
        return "Shotter-\(timestamp).\(ext)"
    }
}
