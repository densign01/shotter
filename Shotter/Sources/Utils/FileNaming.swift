import Foundation
import AppKit
import Vision
import os.log

private let logger = Logger(subsystem: "com.densign.shotter", category: "FileNaming")

struct FileNaming {
    static func generateFilename(extension ext: String = "png") -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmmss-SSS"
        let timestamp = formatter.string(from: Date())
        return "Shotter-\(timestamp).\(ext)"
    }

    /// Generate a descriptive filename using on-device Vision OCR
    /// Falls back to timestamp-based naming if OCR fails or produces no useful text
    static func generateSmartFilename(for image: NSImage, extension ext: String = "png") async -> String {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return generateFilename(extension: ext)
        }

        do {
            let recognizedText = try await recognizeText(in: cgImage)
            if let descriptiveName = buildDescriptiveName(from: recognizedText) {
                let formatter = DateFormatter()
                formatter.dateFormat = "yyyy-MM-dd-HHmmss"
                let timestamp = formatter.string(from: Date())
                return "\(descriptiveName)-\(timestamp).\(ext)"
            }
        } catch {
            logger.warning("Smart naming OCR failed: \(error.localizedDescription)")
        }

        return generateFilename(extension: ext)
    }

    /// Perform OCR on the image using Vision framework
    private static func recognizeText(in image: CGImage) async throws -> [String] {
        try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }

                let observations = request.results as? [VNRecognizedTextObservation] ?? []
                let texts = observations.compactMap { observation in
                    observation.topCandidates(1).first?.string
                }
                continuation.resume(returning: texts)
            }
            request.recognitionLevel = .fast
            request.usesLanguageCorrection = true

            let handler = VNImageRequestHandler(cgImage: image)
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    /// Build a descriptive filename from recognized text
    /// Extracts the most prominent/meaningful text and sanitizes it
    private static func buildDescriptiveName(from texts: [String]) -> String? {
        guard !texts.isEmpty else { return nil }

        // Take the first few significant text blocks (likely titles/headers)
        // Filter out very short or very long strings
        let candidates = texts
            .filter { $0.count >= 3 && $0.count <= 60 }
            .prefix(3)

        guard let primary = candidates.first else { return nil }

        // Sanitize for filesystem
        let sanitized = sanitizeForFilename(primary)

        guard sanitized.count >= 3 else { return nil }

        // Truncate to reasonable length
        let maxLength = 48
        if sanitized.count > maxLength {
            return String(sanitized.prefix(maxLength))
        }

        return sanitized
    }

    /// Sanitize a string for use as a filename
    private static func sanitizeForFilename(_ input: String) -> String {
        // Replace filesystem-unsafe characters with hyphens
        let unsafe = CharacterSet.alphanumerics.inverted
        let components = input.unicodeScalars
            .map { unsafe.contains($0) ? "-" : String($0) }
            .joined()

        // Collapse multiple hyphens and trim
        let collapsed = components
            .replacingOccurrences(of: "-{2,}", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))

        return collapsed
    }
}
