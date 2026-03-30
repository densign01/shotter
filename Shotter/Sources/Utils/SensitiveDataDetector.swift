import AppKit
import Vision

/// A detected region of sensitive text in an image
struct SensitiveTextRegion: Identifiable {
    let id = UUID()
    let text: String
    let category: SensitiveCategory
    let bounds: CGRect  // In image coordinates (origin bottom-left)
    var isSelected: Bool = true  // Selected for redaction by default
}

/// Categories of sensitive information
enum SensitiveCategory: String, CaseIterable {
    case email = "Email"
    case apiKey = "API Key"
    case phone = "Phone"
    case creditCard = "Credit Card"
    case ipAddress = "IP Address"
    case ssn = "SSN"

    var icon: String {
        switch self {
        case .email: return "envelope"
        case .apiKey: return "key"
        case .phone: return "phone"
        case .creditCard: return "creditcard"
        case .ipAddress: return "network"
        case .ssn: return "person.text.rectangle"
        }
    }
}

/// Detects sensitive information in screenshots using on-device OCR + regex pattern matching
struct SensitiveDataDetector {
    /// Regex patterns for each sensitive category
    private static let patterns: [(SensitiveCategory, NSRegularExpression)] = {
        let defs: [(SensitiveCategory, String)] = [
            (.email, #"[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}"#),
            (.apiKey, #"(sk-[a-zA-Z0-9]{20,}|ghp_[a-zA-Z0-9]{36}|AKIA[0-9A-Z]{16}|sk-proj-[a-zA-Z0-9\-_]{20,})"#),
            (.phone, #"\+?[0-9]{1,3}[\-.\s]?\(?[0-9]{3}\)?[\-.\s]?[0-9]{3}[\-.\s]?[0-9]{4}"#),
            (.creditCard, #"[0-9]{4}[\-.\s]?[0-9]{4}[\-.\s]?[0-9]{4}[\-.\s]?[0-9]{4}"#),
            (.ipAddress, #"[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}"#),
            (.ssn, #"[0-9]{3}[\-][0-9]{2}[\-][0-9]{4}"#),
        ]
        return defs.compactMap { category, pattern in
            guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return nil }
            return (category, regex)
        }
    }()

    /// Scan an image for sensitive data. Returns regions in image coordinates.
    static func detect(in image: NSImage) async -> [SensitiveTextRegion] {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return []
        }

        let imageSize = image.size

        return await withCheckedContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                guard error == nil,
                      let observations = request.results as? [VNRecognizedTextObservation] else {
                    continuation.resume(returning: [])
                    return
                }

                var regions: [SensitiveTextRegion] = []

                for observation in observations {
                    guard let candidate = observation.topCandidates(1).first else { continue }
                    let text = candidate.string

                    for (category, regex) in patterns {
                        let range = NSRange(text.startIndex..., in: text)
                        let matches = regex.matches(in: text, options: [], range: range)

                        for match in matches {
                            guard let swiftRange = Range(match.range, in: text) else { continue }
                            let matchedText = String(text[swiftRange])

                            // Get bounding box for the matched substring
                            if let box = try? candidate.boundingBox(for: swiftRange) {
                                let normalizedRect = box.boundingBox
                                // Convert from Vision normalized coords (origin bottom-left, 0-1)
                                // to image coords
                                let imageRect = CGRect(
                                    x: normalizedRect.origin.x * imageSize.width,
                                    y: normalizedRect.origin.y * imageSize.height,
                                    width: normalizedRect.width * imageSize.width,
                                    height: normalizedRect.height * imageSize.height
                                )
                                // Add padding
                                let padded = imageRect.insetBy(dx: -4, dy: -2)

                                regions.append(SensitiveTextRegion(
                                    text: matchedText,
                                    category: category,
                                    bounds: padded
                                ))
                            }
                        }
                    }
                }

                continuation.resume(returning: regions)
            }

            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = false

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(returning: [])
            }
        }
    }
}
