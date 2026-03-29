import AppKit
import os.log

private let logger = Logger(subsystem: "com.densign.shotter", category: "TimestampOverlay")

/// Renders a semi-transparent timestamp badge onto a screenshot image.
struct TimestampOverlay {

    /// Apply a timestamp (and optional app name) badge to the given image.
    /// Returns a new image with the overlay baked in.
    static func apply(to image: NSImage, appName: String?, position: OverlayCorner) -> NSImage {
        let imageSize = image.size
        guard imageSize.width > 0 && imageSize.height > 0 else { return image }

        // Font size scales with image height, clamped to a readable range.
        let baseFontSize = imageSize.height * 0.02
        let fontSize = min(max(baseFontSize, 10), 24)
        let font = NSFont.systemFont(ofSize: fontSize, weight: .medium)
        let smallFont = NSFont.systemFont(ofSize: fontSize * 0.85, weight: .regular)

        // Build text lines
        let timestamp = Self.currentTimestamp()
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .left

        let primaryAttributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.white,
            .paragraphStyle: paragraphStyle,
        ]

        let secondaryAttributes: [NSAttributedString.Key: Any] = [
            .font: smallFont,
            .foregroundColor: NSColor.white.withAlphaComponent(0.9),
            .paragraphStyle: paragraphStyle,
        ]

        let timestampLine = NSAttributedString(string: timestamp, attributes: primaryAttributes)

        let lines: [NSAttributedString]
        if let appName = appName, !appName.isEmpty {
            let appLine = NSAttributedString(string: appName, attributes: secondaryAttributes)
            lines = [timestampLine, appLine]
        } else {
            lines = [timestampLine]
        }

        // Measure text
        let lineSpacing: CGFloat = fontSize * 0.25
        var textHeight: CGFloat = 0
        var textWidth: CGFloat = 0
        var lineSizes: [CGSize] = []
        for line in lines {
            let size = line.size()
            lineSizes.append(size)
            textWidth = max(textWidth, size.width)
            textHeight += size.height
        }
        if lines.count > 1 {
            textHeight += lineSpacing * CGFloat(lines.count - 1)
        }

        // Badge dimensions
        let padding = fontSize * 0.6
        let badgeWidth = textWidth + padding * 2
        let badgeHeight = textHeight + padding * 2
        let cornerRadius = fontSize * 0.4
        let margin = fontSize * 0.5

        // Determine badge origin based on chosen corner
        let badgeOrigin: CGPoint
        switch position {
        case .topLeft:
            badgeOrigin = CGPoint(x: margin, y: imageSize.height - margin - badgeHeight)
        case .topRight:
            badgeOrigin = CGPoint(x: imageSize.width - margin - badgeWidth, y: imageSize.height - margin - badgeHeight)
        case .bottomLeft:
            badgeOrigin = CGPoint(x: margin, y: margin)
        case .bottomRight:
            badgeOrigin = CGPoint(x: imageSize.width - margin - badgeWidth, y: margin)
        }

        // Draw
        let resultImage = NSImage(size: imageSize)
        resultImage.lockFocus()

        // Draw original image
        image.draw(in: CGRect(origin: .zero, size: imageSize),
                   from: .zero,
                   operation: .copy,
                   fraction: 1.0)

        // Draw badge background
        let badgeRect = CGRect(origin: badgeOrigin, size: CGSize(width: badgeWidth, height: badgeHeight))
        let badgePath = NSBezierPath(roundedRect: badgeRect, xRadius: cornerRadius, yRadius: cornerRadius)
        NSColor.black.withAlphaComponent(0.55).setFill()
        badgePath.fill()

        // Draw text lines top-to-bottom (Cocoa y is flipped: higher y = higher on screen)
        var yOffset = badgeOrigin.y + badgeHeight - padding
        for (index, line) in lines.enumerated() {
            let size = lineSizes[index]
            yOffset -= size.height
            line.draw(at: CGPoint(x: badgeOrigin.x + padding, y: yOffset))
            if index < lines.count - 1 {
                yOffset -= lineSpacing
            }
        }

        resultImage.unlockFocus()

        logger.debug("Applied timestamp overlay at \(position.rawValue)")
        return resultImage
    }

    // MARK: - Private

    private static func currentTimestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: Date())
    }
}
