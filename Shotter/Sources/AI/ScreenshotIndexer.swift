import CoreSpotlight
import UniformTypeIdentifiers
import Vision
import AppKit
import os.log

private let indexerLogger = Logger(subsystem: "com.densign.shotter", category: "Indexer")

class ScreenshotIndexer {
    static let shared = ScreenshotIndexer()
    private let domainID = "com.densign.shotter.screenshots"

    private init() {}

    /// Index a screenshot with OCR-extracted text for searchability
    func indexScreenshot(at url: URL, appName: String? = nil) {
        Task {
            guard let image = NSImage(contentsOf: url),
                  let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                indexerLogger.warning("Could not load image for indexing: \(url.path)")
                return
            }

            // Run OCR
            let text = await extractText(from: cgImage)

            // Create searchable item
            let attributeSet = CSSearchableItemAttributeSet(contentType: .image)
            attributeSet.title = url.lastPathComponent
            attributeSet.contentDescription = text
            attributeSet.keywords = text.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
            attributeSet.creator = appName
            attributeSet.contentCreationDate = Date()
            attributeSet.thumbnailURL = url

            let item = CSSearchableItem(
                uniqueIdentifier: url.path,
                domainIdentifier: domainID,
                attributeSet: attributeSet
            )
            item.expirationDate = Calendar.current.date(byAdding: .year, value: 1, to: Date())

            CSSearchableIndex.default().indexSearchableItems([item]) { error in
                if let error = error {
                    indexerLogger.error("Failed to index screenshot: \(error.localizedDescription)")
                } else {
                    indexerLogger.info("Indexed screenshot: \(url.lastPathComponent)")
                }
            }
        }
    }

    /// Search indexed screenshots by text content
    func search(query: String, limit: Int = 20) async -> [URL] {
        await withCheckedContinuation { continuation in
            let escapedQuery = query.replacingOccurrences(of: "\"", with: "\\\"")
            let queryString = "contentDescription == \"*\(escapedQuery)*\"cd"
            let searchQuery = CSSearchQuery(queryString: queryString, attributes: ["contentDescription"])

            var results: [URL] = []

            searchQuery.foundItemsHandler = { items in
                let urls = items.prefix(limit).compactMap { item -> URL? in
                    URL(fileURLWithPath: item.uniqueIdentifier)
                }
                results.append(contentsOf: urls)
            }

            searchQuery.completionHandler = { error in
                if let error = error {
                    indexerLogger.error("Search failed: \(error.localizedDescription)")
                }
                continuation.resume(returning: results)
            }

            searchQuery.start()
        }
    }

    /// Remove a screenshot from the index
    func removeFromIndex(at url: URL) {
        CSSearchableIndex.default().deleteSearchableItems(withIdentifiers: [url.path]) { error in
            if let error = error {
                indexerLogger.error("Failed to remove from index: \(error.localizedDescription)")
            }
        }
    }

    private func extractText(from cgImage: CGImage) async -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])

        do {
            try handler.perform([request])
        } catch {
            return ""
        }

        guard let results = request.results else { return "" }

        return results
            .compactMap { $0.topCandidates(1).first?.string }
            .joined(separator: " ")
    }
}
