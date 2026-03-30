import AppKit

/// Position for the timestamp overlay badge
enum TimestampOverlayPosition: String, CaseIterable {
    case topLeft = "topLeft"
    case topRight = "topRight"
    case bottomLeft = "bottomLeft"
    case bottomRight = "bottomRight"

    var displayName: String {
        switch self {
        case .topLeft: return "Top Left"
        case .topRight: return "Top Right"
        case .bottomLeft: return "Bottom Left"
        case .bottomRight: return "Bottom Right"
        }
    }
}

/// Renders a timestamp and optional app name overlay onto a screenshot
struct TimestampOverlay {
    /// Apply a timestamp (and optional app name) badge to the given image.
    /// Returns a new image with the overlay composited.
    static func apply(
        to image: NSImage,
        appName: String?,
        position: TimestampOverlayPosition
    ) -> NSImage {
        let size = image.size
        guard size.width > 0, size.height > 0 else { return image }

        let result = NSImage(size: size)
        result.lockFocus()

        guard let context = NSGraphicsContext.current?.cgContext else {
            result.unlockFocus()
            return image
        }

        // Draw original image
        image.draw(in: CGRect(origin: .zero, size: size))

        // Build label text
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        var label = formatter.string(from: Date())
        if let app = appName, !app.isEmpty {
            label += "  \(app)"
        }

        // Determine font size relative to image dimensions (auto-scale)
        let referenceDimension = min(size.width, size.height)
        let fontSize = max(min(referenceDimension * 0.018, 18), 10)

        let font = NSFont.systemFont(ofSize: fontSize, weight: .medium)
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .left

        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.white,
            .paragraphStyle: paragraphStyle
        ]

        let attributedString = NSAttributedString(string: label, attributes: attributes)
        let textSize = attributedString.size()

        let paddingH: CGFloat = fontSize * 0.6
        let paddingV: CGFloat = fontSize * 0.35
        let badgeWidth = textSize.width + paddingH * 2
        let badgeHeight = textSize.height + paddingV * 2
        let margin: CGFloat = fontSize * 0.5
        let cornerRadius: CGFloat = fontSize * 0.3

        // Calculate badge origin based on position
        let badgeOrigin: CGPoint
        switch position {
        case .topLeft:
            badgeOrigin = CGPoint(x: margin, y: size.height - badgeHeight - margin)
        case .topRight:
            badgeOrigin = CGPoint(x: size.width - badgeWidth - margin, y: size.height - badgeHeight - margin)
        case .bottomLeft:
            badgeOrigin = CGPoint(x: margin, y: margin)
        case .bottomRight:
            badgeOrigin = CGPoint(x: size.width - badgeWidth - margin, y: margin)
        }

        let badgeRect = CGRect(origin: badgeOrigin, size: CGSize(width: badgeWidth, height: badgeHeight))

        // Draw semi-transparent background
        let bgPath = CGPath(roundedRect: badgeRect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)
        context.setFillColor(NSColor.black.withAlphaComponent(0.55).cgColor)
        context.addPath(bgPath)
        context.fillPath()

        // Draw text
        let textRect = CGRect(
            x: badgeRect.origin.x + paddingH,
            y: badgeRect.origin.y + paddingV,
            width: textSize.width,
            height: textSize.height
        )

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        attributedString.draw(in: textRect)
        NSGraphicsContext.restoreGraphicsState()

        result.unlockFocus()
        return result
    }
}
