import AppKit
import Vision

/// Represents a detected text region with its bounding box and content
struct OCRTextRegion: Identifiable, Equatable {
    let id: UUID
    let text: String
    let bounds: CGRect
    let confidence: Float

    init(text: String, bounds: CGRect, confidence: Float) {
        self.id = UUID()
        self.text = text
        self.bounds = bounds
        self.confidence = confidence
    }
}

/// Recognition accuracy level for OCR
enum OCRRecognitionLevel {
    case fast
    case accurate

    var vnRecognitionLevel: VNRequestTextRecognitionLevel {
        switch self {
        case .fast: return .fast
        case .accurate: return .accurate
        }
    }
}

/// Error types for OCR operations
enum OCRError: Error, LocalizedError {
    case imageConversionFailed
    case requestFailed(Error)
    case noResultsFound

    var errorDescription: String? {
        switch self {
        case .imageConversionFailed:
            return "Failed to convert image for OCR processing"
        case .requestFailed(let error):
            return "OCR request failed: \(error.localizedDescription)"
        case .noResultsFound:
            return "No text detected in the image"
        }
    }
}

/// Service for performing OCR text detection using Apple's Vision framework
final class OCRService {

    // MARK: - Singleton

    static let shared = OCRService()

    // MARK: - Private Properties

    /// Cache for OCR results keyed by image hash
    private var cache: [Int: [OCRTextRegion]] = [:]

    /// Serial queue for thread-safe cache access
    private let cacheQueue = DispatchQueue(label: "com.shotter.ocrservice.cache")

    // MARK: - Initialization

    private init() {}

    // MARK: - Public Methods

    /// Detect text in an image and return word-level bounding boxes
    /// - Parameters:
    ///   - image: The NSImage to process
    ///   - level: Recognition accuracy level (fast or accurate)
    ///   - minimumConfidence: Minimum confidence threshold (0.0 to 1.0)
    /// - Returns: Array of detected text regions with bounds and content
    func detectText(
        in image: NSImage,
        level: OCRRecognitionLevel = .accurate,
        minimumConfidence: Float = 0.5
    ) async throws -> [OCRTextRegion] {
        // Check cache first
        let imageHash = computeImageHash(image)
        if let cached = getCachedResult(for: imageHash) {
            return cached.filter { $0.confidence >= minimumConfidence }
        }

        // Convert NSImage to CGImage
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw OCRError.imageConversionFailed
        }

        let imageSize = CGSize(width: cgImage.width, height: cgImage.height)

        // Perform OCR
        let regions = try await performOCR(on: cgImage, imageSize: imageSize, level: level)

        // Cache the results
        cacheResult(regions, for: imageHash)

        return regions.filter { $0.confidence >= minimumConfidence }
    }

    /// Clear the OCR cache
    func clearCache() {
        cacheQueue.sync {
            cache.removeAll()
        }
    }

    /// Remove cached result for a specific image
    func invalidateCache(for image: NSImage) {
        let hash = computeImageHash(image)
        cacheQueue.sync {
            _ = cache.removeValue(forKey: hash)
        }
    }

    // MARK: - Private Methods

    private func performOCR(
        on cgImage: CGImage,
        imageSize: CGSize,
        level: OCRRecognitionLevel
    ) async throws -> [OCRTextRegion] {
        try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error = error {
                    continuation.resume(throwing: OCRError.requestFailed(error))
                    return
                }

                guard let observations = request.results as? [VNRecognizedTextObservation] else {
                    continuation.resume(returning: [])
                    return
                }

                var regions: [OCRTextRegion] = []

                for observation in observations {
                    // Get top candidate for this observation
                    guard let candidate = observation.topCandidates(1).first else {
                        continue
                    }

                    // Get bounding boxes for each word
                    let words = candidate.string.components(separatedBy: .whitespaces)
                    var currentIndex = candidate.string.startIndex

                    for word in words where !word.isEmpty {
                        guard let wordRange = candidate.string.range(
                            of: word,
                            range: currentIndex..<candidate.string.endIndex
                        ) else {
                            continue
                        }

                        // Try to get bounding box for this word
                        if let wordBoundingBox = try? candidate.boundingBox(for: wordRange) {
                            // Convert normalized coordinates to image coordinates.
                            // Vision uses bottom-left origin with normalized
                            // coordinates (0-1) — the same bottom-left (y-up)
                            // convention as the annotation editor's image
                            // space, so no Y flip is needed.
                            let normalizedRect = wordBoundingBox.boundingBox
                            let imageRect = CGRect(
                                x: normalizedRect.origin.x * imageSize.width,
                                y: normalizedRect.origin.y * imageSize.height,
                                width: normalizedRect.width * imageSize.width,
                                height: normalizedRect.height * imageSize.height
                            )

                            regions.append(OCRTextRegion(
                                text: word,
                                bounds: imageRect,
                                confidence: candidate.confidence
                            ))
                        }

                        currentIndex = wordRange.upperBound
                    }
                }

                continuation.resume(returning: regions)
            }

            // Configure the request
            request.recognitionLevel = level.vnRecognitionLevel
            request.usesLanguageCorrection = true
            request.recognitionLanguages = ["en-US"]  // Default to English, can be extended

            // Create and perform the request
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])

            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: OCRError.requestFailed(error))
            }
        }
    }

    /// Compute a hash for the image to use as cache key
    private func computeImageHash(_ image: NSImage) -> Int {
        // Use the image's pointer address combined with size for a simple identity-based hash
        // This works well when the same NSImage instance is reused
        var hasher = Hasher()
        hasher.combine(ObjectIdentifier(image))
        hasher.combine(image.size.width)
        hasher.combine(image.size.height)
        return hasher.finalize()
    }

    private func getCachedResult(for hash: Int) -> [OCRTextRegion]? {
        cacheQueue.sync {
            cache[hash]
        }
    }

    private func cacheResult(_ regions: [OCRTextRegion], for hash: Int) {
        cacheQueue.sync {
            cache[hash] = regions
        }
    }
}

// MARK: - Convenience Extensions

extension OCRService {

    /// Detect text and return regions that intersect with a given rect
    /// - Parameters:
    ///   - image: The NSImage to process
    ///   - rect: The rect to filter results by
    ///   - level: Recognition accuracy level
    /// - Returns: Array of text regions that intersect with the given rect
    func detectText(
        in image: NSImage,
        intersecting rect: CGRect,
        level: OCRRecognitionLevel = .accurate
    ) async throws -> [OCRTextRegion] {
        let allRegions = try await detectText(in: image, level: level)
        return allRegions.filter { $0.bounds.intersects(rect) }
    }

    /// Detect text and return the full text content as a string
    /// - Parameters:
    ///   - image: The NSImage to process
    ///   - level: Recognition accuracy level
    /// - Returns: All detected text concatenated with spaces
    func extractText(
        from image: NSImage,
        level: OCRRecognitionLevel = .accurate
    ) async throws -> String {
        let regions = try await detectText(in: image, level: level)
        return regions.map { $0.text }.joined(separator: " ")
    }
}
