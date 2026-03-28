import AppKit
import Foundation

struct TimestampOverlay {
    /// Renders a timestamp and optional app name overlay onto an image
    static func apply(
        to image: NSImage,
        appName: String? = nil,
        position: OverlayCorner = .bottomLeft
    ) -> NSImage {
        let size = image.size
        let result = NSImage(size: size)
        result.lockFocus()

        // Draw original image
        image.draw(in: CGRect(origin: .zero, size: size))

        guard let _ = NSGraphicsContext.current else {
            result.unlockFocus()
            return image
        }

        // Format timestamp
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let timestamp = formatter.string(from: Date())

        // Build label text
        var label = timestamp
        if let appName = appName, !appName.isEmpty {
            label = "\(appName)  \u{2022}  \(timestamp)"
        }

        // Calculate font size based on image dimensions (auto-scale)
        let baseFontSize = max(11, min(size.width, size.height) * 0.018)
        let font = NSFont.monospacedSystemFont(ofSize: baseFontSize, weight: .medium)

        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.white
        ]
        let textSize = (label as NSString).size(withAttributes: attributes)

        let padding: CGFloat = baseFontSize * 0.6
        let badgeWidth = textSize.width + padding * 2
        let badgeHeight = textSize.height + padding
        let cornerInset: CGFloat = baseFontSize * 0.8

        // Position badge based on corner preference
        let badgeOrigin: CGPoint
        switch position {
        case .topLeft:
            badgeOrigin = CGPoint(x: cornerInset, y: size.height - badgeHeight - cornerInset)
        case .topRight:
            badgeOrigin = CGPoint(x: size.width - badgeWidth - cornerInset, y: size.height - badgeHeight - cornerInset)
        case .bottomLeft:
            badgeOrigin = CGPoint(x: cornerInset, y: cornerInset)
        case .bottomRight:
            badgeOrigin = CGPoint(x: size.width - badgeWidth - cornerInset, y: cornerInset)
        }

        let badgeRect = CGRect(origin: badgeOrigin, size: CGSize(width: badgeWidth, height: badgeHeight))

        // Draw semi-transparent background
        let bgPath = NSBezierPath(roundedRect: badgeRect, xRadius: 4, yRadius: 4)
        NSColor.black.withAlphaComponent(0.55).setFill()
        bgPath.fill()

        // Draw text centered in badge
        let textRect = CGRect(
            x: badgeRect.origin.x + padding,
            y: badgeRect.origin.y + (badgeHeight - textSize.height) / 2,
            width: textSize.width,
            height: textSize.height
        )
        (label as NSString).draw(in: textRect, withAttributes: attributes)

        result.unlockFocus()
        return result
    }
}
