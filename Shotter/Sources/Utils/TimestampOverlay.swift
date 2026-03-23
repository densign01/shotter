import AppKit

struct TimestampOverlay {
    /// Apply a timestamp + app name overlay to the screenshot
    static func apply(
        to image: NSImage,
        appName: String?,
        position: TimestampPosition
    ) -> NSImage {
        let size = image.size
        let result = NSImage(size: size)

        result.lockFocus()

        // Draw original image
        image.draw(in: CGRect(origin: .zero, size: size))

        // Format timestamp
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let timestamp = formatter.string(from: Date())

        // Build overlay text
        var overlayText = timestamp
        if let appName = appName, !appName.isEmpty {
            overlayText = "\(appName) — \(timestamp)"
        }

        // Calculate font size relative to image (auto-scale)
        let baseFontSize = max(11, min(16, size.width / 80))
        let font = NSFont.systemFont(ofSize: baseFontSize, weight: .medium)

        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.white
        ]

        let textSize = (overlayText as NSString).size(withAttributes: attributes)
        let padding: CGFloat = baseFontSize * 0.6
        let bgHeight = textSize.height + padding * 2
        let bgWidth = textSize.width + padding * 2

        // Calculate position
        let bgRect: CGRect
        switch position {
        case .topLeft:
            bgRect = CGRect(x: 0, y: size.height - bgHeight, width: bgWidth, height: bgHeight)
        case .topRight:
            bgRect = CGRect(x: size.width - bgWidth, y: size.height - bgHeight, width: bgWidth, height: bgHeight)
        case .bottomLeft:
            bgRect = CGRect(x: 0, y: 0, width: bgWidth, height: bgHeight)
        case .bottomRight:
            bgRect = CGRect(x: size.width - bgWidth, y: 0, width: bgWidth, height: bgHeight)
        }

        // Draw semi-transparent background
        NSColor.black.withAlphaComponent(0.5).setFill()
        let bgPath = NSBezierPath(roundedRect: bgRect, xRadius: 4, yRadius: 4)
        bgPath.fill()

        // Draw text
        let textPoint = CGPoint(
            x: bgRect.origin.x + padding,
            y: bgRect.origin.y + padding
        )
        (overlayText as NSString).draw(at: textPoint, withAttributes: attributes)

        result.unlockFocus()
        return result
    }
}
