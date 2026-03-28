import Vision
import AppKit

struct SensitiveRegion {
    let text: String
    let category: SensitiveCategory
    let bounds: CGRect // normalized 0-1 coordinates from Vision
}

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

class SensitiveDataDetector {
    private static let patterns: [(SensitiveCategory, NSRegularExpression)] = {
        let defs: [(SensitiveCategory, String)] = [
            (.email, "[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}"),
            (.apiKey, "(sk-[a-zA-Z0-9]{20,}|ghp_[a-zA-Z0-9]{36}|AKIA[0-9A-Z]{16})"),
            (.phone, "\\+?[0-9]{1,3}[-.\\s]?\\(?[0-9]{3}\\)?[-.\\s]?[0-9]{3}[-.\\s]?[0-9]{4}"),
            (.creditCard, "[0-9]{4}[-.\\s]?[0-9]{4}[-.\\s]?[0-9]{4}[-.\\s]?[0-9]{4}"),
            (.ipAddress, "\\b[0-9]{1,3}\\.[0-9]{1,3}\\.[0-9]{1,3}\\.[0-9]{1,3}\\b"),
            (.ssn, "\\b[0-9]{3}-[0-9]{2}-[0-9]{4}\\b"),
        ]
        return defs.compactMap { category, pattern in
            guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
            return (category, regex)
        }
    }()

    /// Detect sensitive data in an image using Vision OCR + regex pattern matching
    static func detect(in image: NSImage) async -> [SensitiveRegion] {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return []
        }

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])

        do {
            try handler.perform([request])
        } catch {
            return []
        }

        guard let observations = request.results else { return [] }

        var regions: [SensitiveRegion] = []

        for observation in observations {
            guard let candidate = observation.topCandidates(1).first else { continue }
            let text = candidate.string

            for (category, regex) in patterns {
                let range = NSRange(text.startIndex..<text.endIndex, in: text)
                let matches = regex.matches(in: text, range: range)

                for match in matches {
                    // Get the bounding box for the matched text range
                    if let stringRange = Range(match.range, in: text),
                       let boundingBox = try? candidate.boundingBox(for: stringRange) {
                        let rect = boundingBox.boundingBox
                        regions.append(SensitiveRegion(
                            text: String(text[stringRange]),
                            category: category,
                            bounds: rect
                        ))
                    } else {
                        // Fallback: use the whole observation bounding box
                        regions.append(SensitiveRegion(
                            text: String(text[Range(match.range, in: text)!]),
                            category: category,
                            bounds: observation.boundingBox
                        ))
                    }
                }
            }
        }

        return regions
    }

    /// Convert Vision normalized bounds (origin bottom-left, 0-1) to image pixel coordinates
    static func convertToImageCoordinates(_ region: SensitiveRegion, imageSize: CGSize) -> CGRect {
        let visionRect = region.bounds
        return CGRect(
            x: visionRect.origin.x * imageSize.width,
            y: (1 - visionRect.origin.y - visionRect.height) * imageSize.height,
            width: visionRect.width * imageSize.width,
            height: visionRect.height * imageSize.height
        )
    }
}
