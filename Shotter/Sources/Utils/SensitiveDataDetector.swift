import Vision
import AppKit

// MARK: - Sensitive Data Category

enum SensitiveCategory: String, CaseIterable {
    case email
    case apiKey
    case phone
    case creditCard
    case ipAddress
    case secret

    var displayName: String {
        switch self {
        case .email: return "Email"
        case .apiKey: return "API Key"
        case .phone: return "Phone Number"
        case .creditCard: return "Credit Card"
        case .ipAddress: return "IP Address"
        case .secret: return "Secret/Password"
        }
    }
}

// MARK: - Detected Item

struct DetectedSensitiveItem {
    let text: String
    let bounds: CGRect  // In image coordinates (origin bottom-left)
    let category: SensitiveCategory
}

// MARK: - Detector

struct SensitiveDataDetector {

    /// Regex patterns for each sensitive category.
    private static let patterns: [(SensitiveCategory, NSRegularExpression)] = {
        let defs: [(SensitiveCategory, String)] = [
            (.email, "[A-Za-z0-9._%+\\-]+@[A-Za-z0-9.\\-]+\\.[A-Za-z]{2,}"),
            (.apiKey, "(sk-[a-zA-Z0-9]{20,}|ghp_[a-zA-Z0-9]{36}|AKIA[0-9A-Z]{16}|xox[bprs]-[a-zA-Z0-9\\-]+)"),
            (.phone, "\\+?[0-9]{1,3}[\\-.\\s]?\\(?[0-9]{3}\\)?[\\-.\\s]?[0-9]{3}[\\-.\\s]?[0-9]{4}"),
            (.creditCard, "[0-9]{4}[\\-.\\s]?[0-9]{4}[\\-.\\s]?[0-9]{4}[\\-.\\s]?[0-9]{4}"),
            (.ipAddress, "\\b[0-9]{1,3}\\.[0-9]{1,3}\\.[0-9]{1,3}\\.[0-9]{1,3}\\b"),
            (.secret, "(?i)(password|passwd|secret|token|bearer)\\s*[:=]\\s*\\S+"),
        ]
        return defs.compactMap { category, pattern in
            guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
            return (category, regex)
        }
    }()

    /// Run on-device OCR via Apple Vision and return any text regions that match sensitive patterns.
    static func detect(in image: NSImage) async -> [DetectedSensitiveItem] {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return []
        }

        let imageWidth = image.size.width
        let imageHeight = image.size.height

        // Perform OCR
        let observations: [VNRecognizedTextObservation]
        do {
            observations = try await recognizeText(in: cgImage)
        } catch {
            DebugLogger.log("SensitiveDataDetector OCR failed: \(error.localizedDescription)")
            return []
        }

        var results: [DetectedSensitiveItem] = []

        for observation in observations {
            guard let candidate = observation.topCandidates(1).first else { continue }
            let text = candidate.string

            for (category, regex) in patterns {
                let range = NSRange(text.startIndex..., in: text)
                let matches = regex.matches(in: text, range: range)

                for match in matches {
                    guard let matchRange = Range(match.range, in: text) else { continue }
                    let matchedText = String(text[matchRange])

                    // Try to get a tight bounding box for the matched substring.
                    let bounds: CGRect
                    if let box = try? candidate.boundingBox(for: matchRange) {
                        bounds = convertBounds(box.boundingBox, imageWidth: imageWidth, imageHeight: imageHeight)
                    } else {
                        // Fall back to the full observation bounding box.
                        bounds = convertBounds(observation.boundingBox, imageWidth: imageWidth, imageHeight: imageHeight)
                    }

                    results.append(DetectedSensitiveItem(
                        text: matchedText,
                        bounds: bounds,
                        category: category
                    ))
                }
            }
        }

        return results
    }

    // MARK: - Private Helpers

    /// Perform VNRecognizeTextRequest using async/await.
    private static func recognizeText(in cgImage: CGImage) async throws -> [VNRecognizedTextObservation] {
        try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                let observations = request.results as? [VNRecognizedTextObservation] ?? []
                continuation.resume(returning: observations)
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = false  // We want raw text for pattern matching

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    /// Convert Vision's normalised bounding box (origin bottom-left, 0-1) to image coordinates.
    /// The annotation canvas uses standard macOS coordinates (origin bottom-left), which matches
    /// Vision's coordinate system, so we only need to scale by the image dimensions.
    private static func convertBounds(_ normalizedRect: CGRect, imageWidth: CGFloat, imageHeight: CGFloat) -> CGRect {
        CGRect(
            x: normalizedRect.origin.x * imageWidth,
            y: normalizedRect.origin.y * imageHeight,
            width: normalizedRect.width * imageWidth,
            height: normalizedRect.height * imageHeight
        )
    }
}
