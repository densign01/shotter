import AppKit
import Foundation

/// Background style for screenshot presentation
enum BackgroundStyle: String, CaseIterable, Identifiable {
    case none = "None"
    case solidWhite = "White"
    case solidBlack = "Black"
    case gradientBlue = "Blue Gradient"
    case gradientPurple = "Purple Gradient"
    case gradientSunset = "Sunset Gradient"
    case gradientMint = "Mint Gradient"

    var id: String { rawValue }

    /// Apply background to a screenshot with padding
    func render(screenshot: NSImage, padding: CGFloat, cornerRadius: CGFloat) -> NSImage {
        let paddedWidth = screenshot.size.width + padding * 2
        let paddedHeight = screenshot.size.height + padding * 2
        let size = NSSize(width: paddedWidth, height: paddedHeight)

        let result = NSImage(size: size)
        result.lockFocus()

        let fullRect = NSRect(origin: .zero, size: size)

        // Draw background
        switch self {
        case .none:
            NSColor.clear.setFill()
            fullRect.fill()
        case .solidWhite:
            NSColor.white.setFill()
            fullRect.fill()
        case .solidBlack:
            NSColor(white: 0.1, alpha: 1).setFill()
            fullRect.fill()
        case .gradientBlue:
            let gradient = NSGradient(starting: NSColor(red: 0.1, green: 0.4, blue: 0.9, alpha: 1),
                                       ending: NSColor(red: 0.3, green: 0.1, blue: 0.8, alpha: 1))
            gradient?.draw(in: fullRect, angle: 135)
        case .gradientPurple:
            let gradient = NSGradient(starting: NSColor(red: 0.5, green: 0.1, blue: 0.8, alpha: 1),
                                       ending: NSColor(red: 0.8, green: 0.2, blue: 0.6, alpha: 1))
            gradient?.draw(in: fullRect, angle: 135)
        case .gradientSunset:
            let gradient = NSGradient(starting: NSColor(red: 1.0, green: 0.4, blue: 0.3, alpha: 1),
                                       ending: NSColor(red: 1.0, green: 0.7, blue: 0.2, alpha: 1))
            gradient?.draw(in: fullRect, angle: 135)
        case .gradientMint:
            let gradient = NSGradient(starting: NSColor(red: 0.2, green: 0.8, blue: 0.7, alpha: 1),
                                       ending: NSColor(red: 0.1, green: 0.5, blue: 0.9, alpha: 1))
            gradient?.draw(in: fullRect, angle: 135)
        }

        // Draw screenshot with rounded corners and shadow
        let screenshotRect = NSRect(
            x: padding,
            y: padding,
            width: screenshot.size.width,
            height: screenshot.size.height
        )

        if cornerRadius > 0 {
            // Draw shadow
            let shadowPath = NSBezierPath(roundedRect: screenshotRect, xRadius: cornerRadius, yRadius: cornerRadius)
            let shadow = NSShadow()
            shadow.shadowColor = NSColor.black.withAlphaComponent(0.3)
            shadow.shadowBlurRadius = 20
            shadow.shadowOffset = NSSize(width: 0, height: -5)
            shadow.set()
            NSColor.white.setFill()
            shadowPath.fill()

            // Reset shadow
            NSShadow().set()

            // Clip to rounded rect and draw screenshot
            NSGraphicsContext.saveGraphicsState()
            shadowPath.addClip()
            screenshot.draw(in: screenshotRect)
            NSGraphicsContext.restoreGraphicsState()
        } else {
            screenshot.draw(in: screenshotRect)
        }

        result.unlockFocus()
        return result
    }
}

/// Device mockup frame type
enum MockupFrame: String, CaseIterable, Identifiable {
    case none = "None"
    case browserLight = "Browser (Light)"
    case browserDark = "Browser (Dark)"
    case terminalDark = "Terminal"
    case macWindow = "macOS Window"

    var id: String { rawValue }

    /// Apply a device frame mockup around a screenshot
    func apply(to screenshot: NSImage) -> NSImage {
        switch self {
        case .none:
            return screenshot
        case .browserLight:
            return renderBrowserFrame(screenshot: screenshot, isDark: false)
        case .browserDark:
            return renderBrowserFrame(screenshot: screenshot, isDark: true)
        case .terminalDark:
            return renderTerminalFrame(screenshot: screenshot)
        case .macWindow:
            return renderMacWindowFrame(screenshot: screenshot)
        }
    }

    private func renderBrowserFrame(screenshot: NSImage, isDark: Bool) -> NSImage {
        let titleBarHeight: CGFloat = 38
        let borderWidth: CGFloat = 1
        let totalWidth = screenshot.size.width + borderWidth * 2
        let totalHeight = screenshot.size.height + titleBarHeight + borderWidth
        let size = NSSize(width: totalWidth, height: totalHeight)

        let result = NSImage(size: size)
        result.lockFocus()

        let bgColor = isDark ? NSColor(white: 0.15, alpha: 1) : NSColor(white: 0.96, alpha: 1)
        let borderColor = isDark ? NSColor(white: 0.25, alpha: 1) : NSColor(white: 0.82, alpha: 1)
        let dotColors = [
            NSColor(red: 1.0, green: 0.38, blue: 0.34, alpha: 1),  // Red
            NSColor(red: 1.0, green: 0.74, blue: 0.21, alpha: 1),  // Yellow
            NSColor(red: 0.18, green: 0.8, blue: 0.25, alpha: 1)   // Green
        ]

        // Draw border
        borderColor.setFill()
        let outerPath = NSBezierPath(roundedRect: NSRect(origin: .zero, size: size), xRadius: 8, yRadius: 8)
        outerPath.fill()

        // Draw title bar
        bgColor.setFill()
        let titleBarRect = NSRect(x: borderWidth, y: totalHeight - titleBarHeight, width: totalWidth - borderWidth * 2, height: titleBarHeight - borderWidth)
        NSBezierPath(roundedRect: titleBarRect, xRadius: 7, yRadius: 7).fill()

        // Draw traffic light dots
        let dotSize: CGFloat = 12
        let dotY = totalHeight - titleBarHeight / 2 - dotSize / 2
        let dotStartX: CGFloat = 16
        let dotSpacing: CGFloat = 20

        for (i, color) in dotColors.enumerated() {
            let dotRect = NSRect(
                x: dotStartX + CGFloat(i) * dotSpacing,
                y: dotY,
                width: dotSize,
                height: dotSize
            )
            color.setFill()
            NSBezierPath(ovalIn: dotRect).fill()
        }

        // Draw URL bar placeholder
        let urlBarColor = isDark ? NSColor(white: 0.22, alpha: 1) : NSColor(white: 0.9, alpha: 1)
        let urlBarRect = NSRect(
            x: dotStartX + CGFloat(dotColors.count) * dotSpacing + 20,
            y: dotY + 1,
            width: totalWidth - (dotStartX + CGFloat(dotColors.count) * dotSpacing + 20) - 16,
            height: dotSize - 2
        )
        urlBarColor.setFill()
        NSBezierPath(roundedRect: urlBarRect, xRadius: 4, yRadius: 4).fill()

        // Draw screenshot content
        let contentRect = NSRect(
            x: borderWidth,
            y: borderWidth,
            width: screenshot.size.width,
            height: screenshot.size.height
        )
        screenshot.draw(in: contentRect)

        result.unlockFocus()
        return result
    }

    private func renderTerminalFrame(screenshot: NSImage) -> NSImage {
        let titleBarHeight: CGFloat = 32
        let borderWidth: CGFloat = 1
        let totalWidth = screenshot.size.width + borderWidth * 2
        let totalHeight = screenshot.size.height + titleBarHeight + borderWidth
        let size = NSSize(width: totalWidth, height: totalHeight)

        let result = NSImage(size: size)
        result.lockFocus()

        // Dark terminal background
        NSColor(white: 0.1, alpha: 1).setFill()
        let outerPath = NSBezierPath(roundedRect: NSRect(origin: .zero, size: size), xRadius: 8, yRadius: 8)
        outerPath.fill()

        // Title bar
        NSColor(white: 0.18, alpha: 1).setFill()
        let titleBarRect = NSRect(x: 0, y: totalHeight - titleBarHeight, width: totalWidth, height: titleBarHeight)
        let titlePath = NSBezierPath(roundedRect: titleBarRect, xRadius: 8, yRadius: 8)
        titlePath.fill()

        // Traffic light dots
        let dotSize: CGFloat = 12
        let dotY = totalHeight - titleBarHeight / 2 - dotSize / 2
        for (i, color) in [NSColor(red: 1.0, green: 0.38, blue: 0.34, alpha: 1),
                           NSColor(red: 1.0, green: 0.74, blue: 0.21, alpha: 1),
                           NSColor(red: 0.18, green: 0.8, blue: 0.25, alpha: 1)].enumerated() {
            let dotRect = NSRect(x: 14 + CGFloat(i) * 20, y: dotY, width: dotSize, height: dotSize)
            color.setFill()
            NSBezierPath(ovalIn: dotRect).fill()
        }

        // Title text
        let titleFont = NSFont.systemFont(ofSize: 12, weight: .medium)
        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: titleFont,
            .foregroundColor: NSColor(white: 0.6, alpha: 1)
        ]
        let titleStr = "Terminal"
        let titleSize = (titleStr as NSString).size(withAttributes: titleAttrs)
        let titlePoint = NSPoint(x: (totalWidth - titleSize.width) / 2, y: totalHeight - titleBarHeight / 2 - titleSize.height / 2)
        (titleStr as NSString).draw(at: titlePoint, withAttributes: titleAttrs)

        // Screenshot content
        screenshot.draw(in: NSRect(x: borderWidth, y: borderWidth, width: screenshot.size.width, height: screenshot.size.height))

        result.unlockFocus()
        return result
    }

    private func renderMacWindowFrame(screenshot: NSImage) -> NSImage {
        // Similar to browser but with macOS-style title bar (no URL bar)
        let titleBarHeight: CGFloat = 28
        let shadowPadding: CGFloat = 20
        let totalWidth = screenshot.size.width + shadowPadding * 2
        let totalHeight = screenshot.size.height + titleBarHeight + shadowPadding * 2
        let size = NSSize(width: totalWidth, height: totalHeight)

        let result = NSImage(size: size)
        result.lockFocus()

        // Transparent background
        NSColor.clear.setFill()
        NSRect(origin: .zero, size: size).fill()

        let windowRect = NSRect(
            x: shadowPadding,
            y: shadowPadding,
            width: screenshot.size.width,
            height: screenshot.size.height + titleBarHeight
        )

        // Draw shadow
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
        shadow.shadowBlurRadius = 15
        shadow.shadowOffset = NSSize(width: 0, height: -3)
        shadow.set()
        NSColor.white.setFill()
        NSBezierPath(roundedRect: windowRect, xRadius: 8, yRadius: 8).fill()
        NSShadow().set()

        // Title bar
        NSColor(white: 0.97, alpha: 1).setFill()
        let titleBarRect = NSRect(x: windowRect.minX, y: windowRect.maxY - titleBarHeight, width: windowRect.width, height: titleBarHeight)
        NSBezierPath(roundedRect: titleBarRect, xRadius: 8, yRadius: 8).fill()

        // Border
        NSColor(white: 0.82, alpha: 1).setStroke()
        let borderPath = NSBezierPath(roundedRect: windowRect, xRadius: 8, yRadius: 8)
        borderPath.lineWidth = 0.5
        borderPath.stroke()

        // Traffic lights
        let dotSize: CGFloat = 12
        let dotY = windowRect.maxY - titleBarHeight / 2 - dotSize / 2
        for (i, color) in [NSColor(red: 1.0, green: 0.38, blue: 0.34, alpha: 1),
                           NSColor(red: 1.0, green: 0.74, blue: 0.21, alpha: 1),
                           NSColor(red: 0.18, green: 0.8, blue: 0.25, alpha: 1)].enumerated() {
            let dotRect = NSRect(x: windowRect.minX + 12 + CGFloat(i) * 20, y: dotY, width: dotSize, height: dotSize)
            color.setFill()
            NSBezierPath(ovalIn: dotRect).fill()
        }

        // Screenshot
        let contentRect = NSRect(
            x: windowRect.minX,
            y: windowRect.minY,
            width: screenshot.size.width,
            height: screenshot.size.height
        )
        NSGraphicsContext.saveGraphicsState()
        let clipPath = NSBezierPath(roundedRect: NSRect(x: windowRect.minX, y: windowRect.minY, width: windowRect.width, height: screenshot.size.height), xRadius: 0, yRadius: 0)
        clipPath.addClip()
        screenshot.draw(in: contentRect)
        NSGraphicsContext.restoreGraphicsState()

        result.unlockFocus()
        return result
    }
}
