import Vision
import AppKit
import os.log

private let logger = Logger(subsystem: "com.densign.shotter", category: "SmartFileNaming")

struct SmartFileNaming {
    /// Generate a descriptive filename from screenshot content using on-device OCR.
    /// Falls back to standard timestamp naming if OCR fails or returns nothing useful.
    static func generateSmartFilename(for image: NSImage, extension ext: String = "png") async -> String {
        do {
            let recognizedText = try await recognizeText(in: image)
            if let slug = buildSlug(from: recognizedText) {
                let timestamp = compactTimestamp()
                return "Shotter-\(slug)-\(timestamp).\(ext)"
            }
        } catch {
            logger.warning("OCR failed, falling back to timestamp naming: \(error.localizedDescription)")
        }

        // Fallback to standard timestamp naming
        return FileNaming.generateFilename(extension: ext)
    }

    // MARK: - Private

    /// Run VNRecognizeTextRequest on the image and return all recognized strings.
    private static func recognizeText(in image: NSImage) async throws -> [String] {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return []
        }

        return try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }

                let observations = request.results as? [VNRecognizedTextObservation] ?? []
                let strings = observations.compactMap { $0.topCandidates(1).first?.string }
                continuation.resume(returning: strings)
            }

            request.recognitionLevel = .fast
            request.usesLanguageCorrection = false

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    /// Build a filesystem-safe slug from recognized text strings.
    /// Returns nil if the text is not meaningful enough.
    private static func buildSlug(from texts: [String]) -> String? {
        // Join all recognized text, split into words
        let allText = texts.joined(separator: " ")
        let words = allText
            .components(separatedBy: .whitespacesAndNewlines)
            .map { $0.trimmingCharacters(in: .punctuationCharacters) }
            .filter { isUsefulWord($0) }

        guard !words.isEmpty else { return nil }

        // Take up to 6 words to keep the filename reasonable
        let selected = Array(words.prefix(6))
        let slug = selected
            .joined(separator: "-")
            .lowercased()

        // Remove any characters that are not alphanumeric or hyphens
        let cleaned = slug
            .unicodeScalars
            .filter { CharacterSet.alphanumerics.contains($0) || $0 == "-" }
            .map { Character($0) }
        var result = String(cleaned)

        // Collapse multiple hyphens
        while result.contains("--") {
            result = result.replacingOccurrences(of: "--", with: "-")
        }
        result = result.trimmingCharacters(in: CharacterSet(charactersIn: "-"))

        // Limit length
        if result.count > 50 {
            // Truncate at a hyphen boundary if possible
            let truncated = String(result.prefix(50))
            if let lastHyphen = truncated.lastIndex(of: "-") {
                result = String(truncated[truncated.startIndex..<lastHyphen])
            } else {
                result = truncated
            }
        }

        guard result.count >= 3 else { return nil }

        return result
    }

    /// Filter out single characters and numbers-only tokens.
    private static func isUsefulWord(_ word: String) -> Bool {
        guard word.count > 1 else { return false }
        // Reject strings that are only digits/punctuation
        let letters = word.unicodeScalars.filter { CharacterSet.letters.contains($0) }
        return !letters.isEmpty
    }

    /// Compact timestamp for uniqueness suffix: "20260329-143022"
    private static func compactTimestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: Date())
    }
}
