import AppKit
import Vision

/// Generates descriptive filenames for screenshots using on-device OCR.
/// Falls back to timestamp-based naming when no text is detected.
struct SmartFileNaming {
    /// Maximum length for the descriptive portion of the filename
    private static let maxDescriptionLength = 60

    /// Analyze an image and generate a descriptive filename.
    /// Uses Vision framework OCR to extract text content and derive a short description.
    static func generateFilename(for image: NSImage, extension ext: String = "png") async -> String {
        guard let text = await extractText(from: image) else {
            return FileNaming.generateFilename(extension: ext)
        }

        let description = buildDescription(from: text)
        if description.isEmpty {
            return FileNaming.generateFilename(extension: ext)
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        let timestamp = formatter.string(from: Date())
        return "Shotter-\(timestamp)-\(description).\(ext)"
    }

    /// Extract text from an image using Apple Vision framework.
    static func extractText(from image: NSImage) async -> String? {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }

        return await withCheckedContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                guard error == nil,
                      let observations = request.results as? [VNRecognizedTextObservation] else {
                    continuation.resume(returning: nil)
                    return
                }

                let texts = observations.compactMap { observation in
                    observation.topCandidates(1).first?.string
                }

                let combined = texts.joined(separator: " ")
                continuation.resume(returning: combined.isEmpty ? nil : combined)
            }

            request.recognitionLevel = .fast  // Use fast for filename generation
            request.usesLanguageCorrection = false

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(returning: nil)
            }
        }
    }

    /// Build a short filename-safe description from extracted text.
    private static func buildDescription(from text: String) -> String {
        // Take the first meaningful chunk of text
        let words = text
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }

        guard !words.isEmpty else { return "" }

        // Take first few words that fit within the max length
        var description = ""
        for word in words {
            let candidate = description.isEmpty ? word : "\(description) \(word)"
            if candidate.count > maxDescriptionLength { break }
            description = candidate
        }

        // Sanitize for filesystem: replace unsafe chars, collapse whitespace
        return sanitizeForFilename(description)
    }

    /// Remove or replace characters that are unsafe in filenames.
    private static func sanitizeForFilename(_ input: String) -> String {
        let unsafe = CharacterSet.alphanumerics.inverted
        let components = input.unicodeScalars
            .map { unsafe.contains($0) ? "-" : String($0) }
            .joined()

        // Collapse multiple hyphens and trim
        let collapsed = components
            .replacingOccurrences(of: "-{2,}", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))

        return String(collapsed.prefix(maxDescriptionLength))
    }
}
