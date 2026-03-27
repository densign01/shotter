import AppKit
import os.log

private let logger = Logger(subsystem: "com.densign.shotter", category: "Mockup")

/// Background style for screenshot presentation
enum BackgroundStyle: String, CaseIterable, Identifiable {
    case none = "None"
    case solid = "Solid Color"
    case gradient = "Gradient"

    var id: String { rawValue }
}

/// Available mockup frame types (programmatically rendered, no assets needed)
enum MockupFrame: String, CaseIterable, Identifiable {
    case none = "None"
    case browserSafari = "Safari Browser"
    case browserChrome = "Chrome Browser"
    case terminal = "Terminal"
    case macWindow = "macOS Window"

    var id: String { rawValue }
}

/// Configuration for mockup rendering
struct MockupConfiguration {
    var frame: MockupFrame = .none
    var backgroundStyle: BackgroundStyle = .none
    var backgroundColor: NSColor = .systemBlue
    var gradientEndColor: NSColor = .systemPurple
    var padding: CGFloat = 40
    var cornerRadius: CGFloat = 12
    var showShadow: Bool = true
}

/// Renders screenshots with device frames and background customization
struct MockupRenderer {

    /// Apply mockup configuration to an image
    static func render(image: NSImage, config: MockupConfiguration) -> NSImage {
        // First apply the device frame
        let framedImage = applyFrame(to: image, frame: config.frame)

        // Then apply background
        guard config.backgroundStyle != .none else {
            return framedImage
        }

        return applyBackground(to: framedImage, config: config)
    }

    // MARK: - Frame Rendering

    private static func applyFrame(to image: NSImage, frame: MockupFrame) -> NSImage {
        switch frame {
        case .none:
            return image
        case .browserSafari:
            return renderBrowserFrame(image: image, style: .safari)
        case .browserChrome:
            return renderBrowserFrame(image: image, style: .chrome)
        case .terminal:
            return renderTerminalFrame(image: image)
        case .macWindow:
            return renderMacWindowFrame(image: image)
        }
    }

    private enum BrowserStyle {
        case safari
        case chrome
    }

    private static func renderBrowserFrame(image: NSImage, style: BrowserStyle) -> NSImage {
        let titleBarHeight: CGFloat = 38
        let cornerRadius: CGFloat = 10
        let totalWidth = image.size.width
        let totalHeight = image.size.height + titleBarHeight

        let result = NSImage(size: NSSize(width: totalWidth, height: totalHeight))
        result.lockFocus()

        guard let context = NSGraphicsContext.current?.cgContext else {
            result.unlockFocus()
            return image
        }

        // Draw rounded rectangle background
        let outerPath = NSBezierPath(
            roundedRect: NSRect(x: 0, y: 0, width: totalWidth, height: totalHeight),
            xRadius: cornerRadius,
            yRadius: cornerRadius
        )

        // Title bar background
        let titleBarColor: NSColor = style == .safari
            ? NSColor(calibratedRed: 0.96, green: 0.96, blue: 0.96, alpha: 1.0)
            : NSColor(calibratedRed: 0.87, green: 0.87, blue: 0.87, alpha: 1.0)

        titleBarColor.setFill()
        outerPath.fill()

        // Draw image content area
        let contentRect = NSRect(x: 0, y: 0, width: totalWidth, height: image.size.height)
        image.draw(in: contentRect)

        // Draw traffic light buttons
        let buttonY = image.size.height + titleBarHeight / 2
        let buttonRadius: CGFloat = 6
        let buttonStartX: CGFloat = 14
        let buttonSpacing: CGFloat = 20

        let colors: [NSColor] = [
            NSColor(calibratedRed: 1.0, green: 0.38, blue: 0.34, alpha: 1.0), // Red
            NSColor(calibratedRed: 1.0, green: 0.74, blue: 0.21, alpha: 1.0), // Yellow
            NSColor(calibratedRed: 0.15, green: 0.80, blue: 0.26, alpha: 1.0), // Green
        ]

        for (i, color) in colors.enumerated() {
            let x = buttonStartX + CGFloat(i) * buttonSpacing
            let buttonRect = NSRect(
                x: x - buttonRadius,
                y: buttonY - buttonRadius,
                width: buttonRadius * 2,
                height: buttonRadius * 2
            )
            color.setFill()
            NSBezierPath(ovalIn: buttonRect).fill()
        }

        // Draw URL bar for browser styles
        if style == .safari || style == .chrome {
            let urlBarWidth = min(totalWidth * 0.5, 400)
            let urlBarHeight: CGFloat = 24
            let urlBarX = (totalWidth - urlBarWidth) / 2
            let urlBarY = buttonY - urlBarHeight / 2

            let urlBarRect = NSRect(x: urlBarX, y: urlBarY, width: urlBarWidth, height: urlBarHeight)
            NSColor(white: 0.92, alpha: 1.0).setFill()
            NSBezierPath(roundedRect: urlBarRect, xRadius: urlBarHeight / 2, yRadius: urlBarHeight / 2).fill()
        }

        // Draw bottom border of title bar
        context.setStrokeColor(NSColor(white: 0.8, alpha: 1.0).cgColor)
        context.setLineWidth(0.5)
        context.move(to: CGPoint(x: 0, y: image.size.height))
        context.addLine(to: CGPoint(x: totalWidth, y: image.size.height))
        context.strokePath()

        // Draw outer border
        NSColor(white: 0.7, alpha: 0.5).setStroke()
        outerPath.lineWidth = 1
        outerPath.stroke()

        result.unlockFocus()
        return result
    }

    private static func renderTerminalFrame(image: NSImage) -> NSImage {
        let titleBarHeight: CGFloat = 30
        let cornerRadius: CGFloat = 10
        let totalWidth = image.size.width
        let totalHeight = image.size.height + titleBarHeight

        let result = NSImage(size: NSSize(width: totalWidth, height: totalHeight))
        result.lockFocus()

        // Dark terminal background for title bar
        let outerPath = NSBezierPath(
            roundedRect: NSRect(x: 0, y: 0, width: totalWidth, height: totalHeight),
            xRadius: cornerRadius,
            yRadius: cornerRadius
        )
        NSColor(calibratedRed: 0.18, green: 0.18, blue: 0.20, alpha: 1.0).setFill()
        outerPath.fill()

        // Draw image content
        image.draw(in: NSRect(x: 0, y: 0, width: totalWidth, height: image.size.height))

        // Traffic light buttons
        let buttonY = image.size.height + titleBarHeight / 2
        let buttonRadius: CGFloat = 6
        let colors: [NSColor] = [
            NSColor(calibratedRed: 1.0, green: 0.38, blue: 0.34, alpha: 1.0),
            NSColor(calibratedRed: 1.0, green: 0.74, blue: 0.21, alpha: 1.0),
            NSColor(calibratedRed: 0.15, green: 0.80, blue: 0.26, alpha: 1.0),
        ]
        for (i, color) in colors.enumerated() {
            let x: CGFloat = 14 + CGFloat(i) * 20
            let rect = NSRect(x: x - buttonRadius, y: buttonY - buttonRadius, width: buttonRadius * 2, height: buttonRadius * 2)
            color.setFill()
            NSBezierPath(ovalIn: rect).fill()
        }

        // Terminal title text
        let font = NSFont.systemFont(ofSize: 12, weight: .medium)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor(white: 0.7, alpha: 1.0),
        ]
        let title = "Terminal" as NSString
        let titleSize = title.size(withAttributes: attrs)
        let titleX = (totalWidth - titleSize.width) / 2
        let titleY = buttonY - titleSize.height / 2
        title.draw(at: NSPoint(x: titleX, y: titleY), withAttributes: attrs)

        // Outer border
        NSColor(white: 0.3, alpha: 0.5).setStroke()
        outerPath.lineWidth = 1
        outerPath.stroke()

        result.unlockFocus()
        return result
    }

    private static func renderMacWindowFrame(image: NSImage) -> NSImage {
        // Similar to browser but simpler - just a title bar with traffic lights
        let titleBarHeight: CGFloat = 28
        let cornerRadius: CGFloat = 10
        let totalWidth = image.size.width
        let totalHeight = image.size.height + titleBarHeight

        let result = NSImage(size: NSSize(width: totalWidth, height: totalHeight))
        result.lockFocus()

        let outerPath = NSBezierPath(
            roundedRect: NSRect(x: 0, y: 0, width: totalWidth, height: totalHeight),
            xRadius: cornerRadius,
            yRadius: cornerRadius
        )
        NSColor(calibratedRed: 0.93, green: 0.93, blue: 0.93, alpha: 1.0).setFill()
        outerPath.fill()

        // Content
        image.draw(in: NSRect(x: 0, y: 0, width: totalWidth, height: image.size.height))

        // Traffic lights
        let buttonY = image.size.height + titleBarHeight / 2
        let buttonRadius: CGFloat = 6
        let colors: [NSColor] = [
            NSColor(calibratedRed: 1.0, green: 0.38, blue: 0.34, alpha: 1.0),
            NSColor(calibratedRed: 1.0, green: 0.74, blue: 0.21, alpha: 1.0),
            NSColor(calibratedRed: 0.15, green: 0.80, blue: 0.26, alpha: 1.0),
        ]
        for (i, color) in colors.enumerated() {
            let x: CGFloat = 14 + CGFloat(i) * 20
            let rect = NSRect(x: x - buttonRadius, y: buttonY - buttonRadius, width: buttonRadius * 2, height: buttonRadius * 2)
            color.setFill()
            NSBezierPath(ovalIn: rect).fill()
        }

        // Border
        NSColor(white: 0.7, alpha: 0.5).setStroke()
        outerPath.lineWidth = 1
        outerPath.stroke()

        result.unlockFocus()
        return result
    }

    // MARK: - Background Rendering

    private static func applyBackground(to image: NSImage, config: MockupConfiguration) -> NSImage {
        let padding = config.padding
        let totalWidth = image.size.width + padding * 2
        let totalHeight = image.size.height + padding * 2

        let result = NSImage(size: NSSize(width: totalWidth, height: totalHeight))
        result.lockFocus()

        guard let context = NSGraphicsContext.current?.cgContext else {
            result.unlockFocus()
            return image
        }

        let backgroundRect = CGRect(x: 0, y: 0, width: totalWidth, height: totalHeight)

        // Draw background
        switch config.backgroundStyle {
        case .none:
            break
        case .solid:
            config.backgroundColor.setFill()
            context.fill(backgroundRect)
        case .gradient:
            let colors = [config.backgroundColor.cgColor, config.gradientEndColor.cgColor]
            let colorSpace = CGColorSpaceCreateDeviceRGB()
            if let gradient = CGGradient(colorsSpace: colorSpace, colors: colors as CFArray, locations: nil) {
                context.drawLinearGradient(
                    gradient,
                    start: CGPoint(x: 0, y: totalHeight),
                    end: CGPoint(x: totalWidth, y: 0),
                    options: []
                )
            }
        }

        // Draw shadow if enabled
        if config.showShadow {
            let shadowRect = NSRect(
                x: padding - 2,
                y: padding - 2,
                width: image.size.width + 4,
                height: image.size.height + 4
            )

            let shadow = NSShadow()
            shadow.shadowColor = NSColor.black.withAlphaComponent(0.3)
            shadow.shadowOffset = NSSize(width: 0, height: -4)
            shadow.shadowBlurRadius = 16
            shadow.set()

            NSColor.white.setFill()
            let shadowPath = NSBezierPath(roundedRect: shadowRect, xRadius: config.cornerRadius, yRadius: config.cornerRadius)
            shadowPath.fill()

            // Reset shadow
            NSShadow().set()
        }

        // Draw image centered with corner radius
        let imageRect = NSRect(x: padding, y: padding, width: image.size.width, height: image.size.height)

        if config.cornerRadius > 0 {
            let clipPath = NSBezierPath(roundedRect: imageRect, xRadius: config.cornerRadius, yRadius: config.cornerRadius)
            clipPath.addClip()
        }

        image.draw(in: imageRect)

        result.unlockFocus()
        return result
    }
}
