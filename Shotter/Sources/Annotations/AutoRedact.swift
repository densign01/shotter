import Vision
import AppKit

/// A region of text detected as sensitive by the auto-redact system
struct SensitiveRegion {
    let text: String
    let boundingBox: CGRect  // In normalized coordinates (0-1) from Vision framework
    let type: SensitiveDataType
}

/// Types of sensitive data that can be detected in screenshots
enum SensitiveDataType: String, CaseIterable {
    case email
    case apiKey
    case phone
    case creditCard
    case ipAddress

    var pattern: String {
        switch self {
        case .email:
            return "[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}"
        case .apiKey:
            return "(sk-[a-zA-Z0-9]{20,}|ghp_[a-zA-Z0-9]{36}|AKIA[0-9A-Z]{16}|xox[bpas]-[a-zA-Z0-9-]+)"
        case .phone:
            return "\\+?[0-9]{1,3}[-.\\s]?\\(?[0-9]{3}\\)?[-.\\s]?[0-9]{3}[-.\\s]?[0-9]{4}"
        case .creditCard:
            return "[0-9]{4}[-.\\s]?[0-9]{4}[-.\\s]?[0-9]{4}[-.\\s]?[0-9]{4}"
        case .ipAddress:
            return "\\b[0-9]{1,3}\\.[0-9]{1,3}\\.[0-9]{1,3}\\.[0-9]{1,3}\\b"
        }
    }

    var displayName: String {
        switch self {
        case .email: return "Email"
        case .apiKey: return "API Key"
        case .phone: return "Phone"
        case .creditCard: return "Credit Card"
        case .ipAddress: return "IP Address"
        }
    }
}

/// On-device sensitive data detection using Apple Vision framework OCR
struct AutoRedact {

    /// Detect sensitive regions in an image using Vision OCR and regex pattern matching
    static func detectSensitiveRegions(in image: NSImage) async -> [SensitiveRegion] {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return []
        }

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])

        do {
            try handler.perform([request])
        } catch {
            DebugLogger.log("AutoRedact OCR failed: \(error.localizedDescription)")
            return []
        }

        guard let observations = request.results else {
            return []
        }

        var regions: [SensitiveRegion] = []

        for observation in observations {
            guard let candidate = observation.topCandidates(1).first else { continue }
            let text = candidate.string

            for dataType in SensitiveDataType.allCases {
                guard let regex = try? NSRegularExpression(pattern: dataType.pattern) else { continue }
                let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))

                for match in matches {
                    guard let matchRange = Range(match.range, in: text) else { continue }
                    let matchedText = String(text[matchRange])

                    // Get the bounding box for the matched substring within the observation
                    if let boxObservation = try? candidate.boundingBox(for: matchRange) {
                        let boundingBox = boxObservation.boundingBox
                        regions.append(SensitiveRegion(
                            text: matchedText,
                            boundingBox: boundingBox,
                            type: dataType
                        ))
                    } else {
                        // Fall back to the full observation bounding box
                        regions.append(SensitiveRegion(
                            text: matchedText,
                            boundingBox: observation.boundingBox,
                            type: dataType
                        ))
                    }
                }
            }
        }

        DebugLogger.log("AutoRedact found \(regions.count) sensitive region(s)")
        return regions
    }
}
