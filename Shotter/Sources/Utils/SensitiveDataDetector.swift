import AppKit
import Vision
import os.log

private let logger = Logger(subsystem: "com.densign.shotter", category: "SensitiveData")

/// Represents a detected sensitive text region in an image
struct SensitiveRegion: Identifiable {
    let id = UUID()
    let text: String
    let category: SensitiveCategory
    let bounds: CGRect  // In image coordinates (0,0 = bottom-left, normalized)
    var isSelected: Bool = true  // Selected for redaction by default
}

/// Categories of sensitive information
enum SensitiveCategory: String, CaseIterable {
    case email = "Email"
    case apiKey = "API Key"
    case phone = "Phone"
    case creditCard = "Credit Card"
    case ipAddress = "IP Address"
    case socialSecurity = "SSN"

    var icon: String {
        switch self {
        case .email: return "envelope"
        case .apiKey: return "key"
        case .phone: return "phone"
        case .creditCard: return "creditcard"
        case .ipAddress: return "network"
        case .socialSecurity: return "person.badge.shield.checkmark"
        }
    }
}

/// Detects sensitive information in screenshots using Vision OCR + regex patterns
struct SensitiveDataDetector {

    /// Regex patterns for each sensitive data category
    private static let patterns: [(SensitiveCategory, NSRegularExpression)] = {
        let defs: [(SensitiveCategory, String)] = [
            (.email, "[A-Za-z0-9._%+\\-]+@[A-Za-z0-9.\\-]+\\.[A-Za-z]{2,}"),
            (.apiKey, "(sk-[a-zA-Z0-9]{20,}|ghp_[a-zA-Z0-9]{36}|AKIA[0-9A-Z]{16}|sk-proj-[a-zA-Z0-9\\-]{20,}|xox[bpsa]-[a-zA-Z0-9\\-]+)"),
            (.phone, "\\+?[0-9]{1,3}[\\-.\\s]?\\(?[0-9]{3}\\)?[\\-.\\s]?[0-9]{3}[\\-.\\s]?[0-9]{4}"),
            (.creditCard, "[0-9]{4}[\\-.\\s]?[0-9]{4}[\\-.\\s]?[0-9]{4}[\\-.\\s]?[0-9]{4}"),
            (.ipAddress, "\\b(?:(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\\.){3}(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\\b"),
            (.socialSecurity, "\\b[0-9]{3}-[0-9]{2}-[0-9]{4}\\b"),
        ]
        return defs.compactMap { category, pattern in
            guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return nil }
            return (category, regex)
        }
    }()

    /// Detect sensitive regions in an image
    static func detect(in image: NSImage) async -> [SensitiveRegion] {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return []
        }

        do {
            let observations = try await performOCR(on: cgImage)
            return matchPatterns(in: observations, imageSize: image.size)
        } catch {
            logger.error("Sensitive data detection failed: \(error.localizedDescription)")
            return []
        }
    }

    private static func performOCR(on image: CGImage) async throws -> [VNRecognizedTextObservation] {
        try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                let results = request.results as? [VNRecognizedTextObservation] ?? []
                continuation.resume(returning: results)
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true

            let handler = VNImageRequestHandler(cgImage: image)
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    private static func matchPatterns(
        in observations: [VNRecognizedTextObservation],
        imageSize: CGSize
    ) -> [SensitiveRegion] {
        var regions: [SensitiveRegion] = []

        for observation in observations {
            guard let candidate = observation.topCandidates(1).first else { continue }
            let text = candidate.string

            for (category, regex) in patterns {
                let range = NSRange(text.startIndex..<text.endIndex, in: text)
                let matches = regex.matches(in: text, options: [], range: range)

                for match in matches {
                    guard let matchRange = Range(match.range, in: text) else { continue }
                    let matchedText = String(text[matchRange])

                    // Get the bounding box for the matched text within the observation
                    if let boundingBox = try? candidate.boundingBox(for: matchRange) {
                        // Convert from Vision normalized coordinates to image coordinates
                        let rect = CGRect(
                            x: boundingBox.bottomLeft.x * imageSize.width,
                            y: boundingBox.bottomLeft.y * imageSize.height,
                            width: (boundingBox.bottomRight.x - boundingBox.bottomLeft.x) * imageSize.width,
                            height: (boundingBox.topLeft.y - boundingBox.bottomLeft.y) * imageSize.height
                        )

                        // Add padding around the detected region
                        let paddedRect = rect.insetBy(dx: -4, dy: -4)

                        regions.append(SensitiveRegion(
                            text: matchedText,
                            category: category,
                            bounds: paddedRect
                        ))
                    }
                }
            }
        }

        return regions
    }
}
