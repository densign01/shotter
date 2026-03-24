import Vision
import AppKit

struct SmartNaming {
    /// Generate a descriptive filename from screenshot content using OCR
    static func generateSmartFilename(from image: NSImage, extension ext: String = "png") async -> String {
        let texts = await recognizeText(in: image)
        let filtered = texts.filter { $0.count >= 3 }

        guard !filtered.isEmpty else {
            return FileNaming.generateFilename(extension: ext)
        }

        let name = generateName(from: filtered)
        guard !name.isEmpty else {
            return FileNaming.generateFilename(extension: ext)
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "HHmmss"
        let timestamp = formatter.string(from: Date())

        return "Shotter-\(name)-\(timestamp).\(ext)"
    }

    private static func recognizeText(in image: NSImage) async -> [String] {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return []
        }

        return await withCheckedContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                guard let observations = request.results as? [VNRecognizedTextObservation] else {
                    continuation.resume(returning: [])
                    return
                }
                let texts = observations.compactMap { $0.topCandidates(1).first?.string }
                continuation.resume(returning: texts)
            }
            request.recognitionLevel = .fast
            request.usesLanguageCorrection = false

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(returning: [])
            }
        }
    }

    private static func generateName(from texts: [String]) -> String {
        // Take the first 1-3 text fragments
        let fragments = Array(texts.prefix(3))
        let joined = fragments.joined(separator: " ")

        // Remove non-alphanumeric characters (keep spaces)
        let cleaned = joined.unicodeScalars
            .filter { CharacterSet.alphanumerics.contains($0) || $0 == " " }
            .reduce("") { $0 + String($1) }
            .trimmingCharacters(in: .whitespaces)

        guard !cleaned.isEmpty else { return "" }

        // Replace spaces with hyphens, lowercase
        let hyphenated = cleaned
            .components(separatedBy: .whitespaces)
            .filter { !$0.isEmpty }
            .joined(separator: "-")
            .lowercased()

        // Truncate to 40 chars at word boundary
        if hyphenated.count <= 40 {
            return hyphenated
        }

        let truncated = String(hyphenated.prefix(40))
        if let lastHyphen = truncated.lastIndex(of: "-") {
            return String(truncated[truncated.startIndex..<lastHyphen])
        }
        return truncated
    }
}
