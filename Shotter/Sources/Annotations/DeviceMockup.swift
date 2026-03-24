import AppKit

// MARK: - Mockup Types

enum MockupType: String, CaseIterable, Identifiable {
    case none = "None"
    case browserSafari = "Safari Browser"
    case browserChrome = "Chrome Browser"
    case terminal = "Terminal"
    case codeEditor = "Code Editor"

    var id: String { rawValue }
}

struct MockupConfig: Equatable {
    var type: MockupType = .none
    var darkMode: Bool = false
}

// MARK: - Browser Style

private enum BrowserStyle {
    case safari
    case chrome
}

// MARK: - Device Mockup Renderer

struct DeviceMockupRenderer {

    static func render(screenshot: NSImage, config: MockupConfig) -> NSImage {
        guard config.type != .none else { return screenshot }

        switch config.type {
        case .none:
            return screenshot
        case .browserSafari:
            return renderBrowserFrame(screenshot, style: .safari, darkMode: config.darkMode)
        case .browserChrome:
            return renderBrowserFrame(screenshot, style: .chrome, darkMode: config.darkMode)
        case .terminal:
            return renderTerminalFrame(screenshot, darkMode: config.darkMode)
        case .codeEditor:
            return renderCodeEditorFrame(screenshot, darkMode: config.darkMode)
        }
    }

    // MARK: - Browser Frame

    private static func renderBrowserFrame(_ screenshot: NSImage, style: BrowserStyle, darkMode: Bool) -> NSImage {
        let titleBarHeight: CGFloat = 38
        let cornerRadius: CGFloat = 10
        let outputSize = NSSize(
            width: screenshot.size.width,
            height: screenshot.size.height + titleBarHeight
        )

        let image = NSImage(size: outputSize)
        image.lockFocus()

        // Draw window background with rounded corners
        let windowPath = NSBezierPath(roundedRect: NSRect(origin: .zero, size: outputSize), xRadius: cornerRadius, yRadius: cornerRadius)
        let bgColor = darkMode ? NSColor(white: 0.17, alpha: 1) : NSColor(white: 0.96, alpha: 1)
        bgColor.setFill()
        windowPath.fill()

        // Draw title bar
        let titleBarRect = NSRect(x: 0, y: outputSize.height - titleBarHeight, width: outputSize.width, height: titleBarHeight)
        let titleBarColor = darkMode ? NSColor(white: 0.22, alpha: 1) : NSColor(white: 0.92, alpha: 1)
        titleBarColor.setFill()
        NSBezierPath(rect: titleBarRect).fill()

        // Round top corners of title bar
        let topCornerPath = NSBezierPath(
            roundedRect: NSRect(x: 0, y: outputSize.height - cornerRadius, width: outputSize.width, height: cornerRadius),
            xRadius: cornerRadius,
            yRadius: cornerRadius
        )
        titleBarColor.setFill()
        topCornerPath.fill()

        // Draw separator line
        let separatorColor = darkMode ? NSColor(white: 0.12, alpha: 1) : NSColor(white: 0.82, alpha: 1)
        separatorColor.setFill()
        NSBezierPath(rect: NSRect(x: 0, y: outputSize.height - titleBarHeight, width: outputSize.width, height: 1)).fill()

        // Draw traffic lights
        drawTrafficLights(at: outputSize.height - titleBarHeight / 2, in: outputSize)

        // Draw URL bar (Safari style) or tab bar (Chrome style)
        switch style {
        case .safari:
            let urlBarWidth = min(outputSize.width * 0.5, 400)
            let urlBarRect = NSRect(
                x: (outputSize.width - urlBarWidth) / 2,
                y: outputSize.height - titleBarHeight + 7,
                width: urlBarWidth,
                height: 24
            )
            let urlBarColor = darkMode ? NSColor(white: 0.28, alpha: 1) : NSColor(white: 0.86, alpha: 1)
            urlBarColor.setFill()
            NSBezierPath(roundedRect: urlBarRect, xRadius: 6, yRadius: 6).fill()

        case .chrome:
            // Draw a tab shape
            let tabRect = NSRect(
                x: 80,
                y: outputSize.height - titleBarHeight + 6,
                width: 160,
                height: 26
            )
            let tabColor = darkMode ? NSColor(white: 0.28, alpha: 1) : NSColor(white: 0.98, alpha: 1)
            tabColor.setFill()
            NSBezierPath(roundedRect: tabRect, xRadius: 6, yRadius: 6).fill()

            // Draw URL bar below tabs (using a slightly different y-position within title bar area)
            // For Chrome, we make the title bar taller conceptually by drawing URL bar inside content area top
            let urlBarRect = NSRect(
                x: 80,
                y: outputSize.height - titleBarHeight + 7,
                width: min(outputSize.width - 160, outputSize.width * 0.6),
                height: 24
            )
            let urlBarColor = darkMode ? NSColor(white: 0.25, alpha: 1) : NSColor(white: 0.90, alpha: 1)
            urlBarColor.setFill()
            NSBezierPath(roundedRect: urlBarRect, xRadius: 12, yRadius: 12).fill()
        }

        // Draw screenshot content (clip to rounded bottom corners)
        let contentRect = NSRect(x: 0, y: 0, width: outputSize.width, height: outputSize.height - titleBarHeight)
        let contentClipPath = NSBezierPath()
        contentClipPath.move(to: NSPoint(x: 0, y: cornerRadius))
        contentClipPath.appendArc(withCenter: NSPoint(x: cornerRadius, y: cornerRadius), radius: cornerRadius, startAngle: 180, endAngle: 270)
        contentClipPath.line(to: NSPoint(x: outputSize.width - cornerRadius, y: 0))
        contentClipPath.appendArc(withCenter: NSPoint(x: outputSize.width - cornerRadius, y: cornerRadius), radius: cornerRadius, startAngle: 270, endAngle: 360)
        contentClipPath.line(to: NSPoint(x: outputSize.width, y: contentRect.height))
        contentClipPath.line(to: NSPoint(x: 0, y: contentRect.height))
        contentClipPath.close()

        NSGraphicsContext.current?.saveGraphicsState()
        contentClipPath.addClip()
        screenshot.draw(in: contentRect)
        NSGraphicsContext.current?.restoreGraphicsState()

        image.unlockFocus()
        return image
    }

    // MARK: - Terminal Frame

    private static func renderTerminalFrame(_ screenshot: NSImage, darkMode: Bool) -> NSImage {
        let titleBarHeight: CGFloat = 38
        let cornerRadius: CGFloat = 10
        let outputSize = NSSize(
            width: screenshot.size.width,
            height: screenshot.size.height + titleBarHeight
        )

        let image = NSImage(size: outputSize)
        image.lockFocus()

        // Terminal defaults to a dark appearance
        let effectiveDark = true

        // Draw window background with rounded corners
        let windowPath = NSBezierPath(roundedRect: NSRect(origin: .zero, size: outputSize), xRadius: cornerRadius, yRadius: cornerRadius)
        let bgColor = effectiveDark ? NSColor(white: 0.12, alpha: 1) : NSColor(white: 0.96, alpha: 1)
        bgColor.setFill()
        windowPath.fill()

        // Draw title bar
        let titleBarRect = NSRect(x: 0, y: outputSize.height - titleBarHeight, width: outputSize.width, height: titleBarHeight)
        let titleBarColor = effectiveDark ? NSColor(white: 0.18, alpha: 1) : NSColor(white: 0.92, alpha: 1)
        titleBarColor.setFill()
        NSBezierPath(rect: titleBarRect).fill()

        // Round top corners
        let topCornerPath = NSBezierPath(
            roundedRect: NSRect(x: 0, y: outputSize.height - cornerRadius, width: outputSize.width, height: cornerRadius),
            xRadius: cornerRadius,
            yRadius: cornerRadius
        )
        titleBarColor.setFill()
        topCornerPath.fill()

        // Separator
        let separatorColor = effectiveDark ? NSColor(white: 0.08, alpha: 1) : NSColor(white: 0.82, alpha: 1)
        separatorColor.setFill()
        NSBezierPath(rect: NSRect(x: 0, y: outputSize.height - titleBarHeight, width: outputSize.width, height: 1)).fill()

        // Traffic lights
        drawTrafficLights(at: outputSize.height - titleBarHeight / 2, in: outputSize)

        // Title text
        let titleText = "Terminal \u{2014} zsh"
        let titleFont = NSFont.systemFont(ofSize: 12, weight: .medium)
        let titleColor = effectiveDark ? NSColor(white: 0.70, alpha: 1) : NSColor(white: 0.30, alpha: 1)
        let titleAttributes: [NSAttributedString.Key: Any] = [
            .font: titleFont,
            .foregroundColor: titleColor,
        ]
        let titleSize = (titleText as NSString).size(withAttributes: titleAttributes)
        let titlePoint = NSPoint(
            x: (outputSize.width - titleSize.width) / 2,
            y: outputSize.height - titleBarHeight + (titleBarHeight - titleSize.height) / 2
        )
        (titleText as NSString).draw(at: titlePoint, withAttributes: titleAttributes)

        // Draw screenshot content
        let contentRect = NSRect(x: 0, y: 0, width: outputSize.width, height: outputSize.height - titleBarHeight)
        let contentClipPath = NSBezierPath()
        contentClipPath.move(to: NSPoint(x: 0, y: cornerRadius))
        contentClipPath.appendArc(withCenter: NSPoint(x: cornerRadius, y: cornerRadius), radius: cornerRadius, startAngle: 180, endAngle: 270)
        contentClipPath.line(to: NSPoint(x: outputSize.width - cornerRadius, y: 0))
        contentClipPath.appendArc(withCenter: NSPoint(x: outputSize.width - cornerRadius, y: cornerRadius), radius: cornerRadius, startAngle: 270, endAngle: 360)
        contentClipPath.line(to: NSPoint(x: outputSize.width, y: contentRect.height))
        contentClipPath.line(to: NSPoint(x: 0, y: contentRect.height))
        contentClipPath.close()

        NSGraphicsContext.current?.saveGraphicsState()
        contentClipPath.addClip()
        screenshot.draw(in: contentRect)
        NSGraphicsContext.current?.restoreGraphicsState()

        image.unlockFocus()
        return image
    }

    // MARK: - Code Editor Frame

    private static func renderCodeEditorFrame(_ screenshot: NSImage, darkMode: Bool) -> NSImage {
        let titleBarHeight: CGFloat = 38
        let gutterWidth: CGFloat = 40
        let cornerRadius: CGFloat = 10
        let outputSize = NSSize(
            width: screenshot.size.width + gutterWidth,
            height: screenshot.size.height + titleBarHeight
        )

        let image = NSImage(size: outputSize)
        image.lockFocus()

        // Code editors typically use dark mode
        let effectiveDark = true

        // Draw window background with rounded corners
        let windowPath = NSBezierPath(roundedRect: NSRect(origin: .zero, size: outputSize), xRadius: cornerRadius, yRadius: cornerRadius)
        let bgColor = effectiveDark ? NSColor(white: 0.14, alpha: 1) : NSColor(white: 0.96, alpha: 1)
        bgColor.setFill()
        windowPath.fill()

        // Draw title bar
        let titleBarRect = NSRect(x: 0, y: outputSize.height - titleBarHeight, width: outputSize.width, height: titleBarHeight)
        let titleBarColor = effectiveDark ? NSColor(white: 0.20, alpha: 1) : NSColor(white: 0.92, alpha: 1)
        titleBarColor.setFill()
        NSBezierPath(rect: titleBarRect).fill()

        // Round top corners
        let topCornerPath = NSBezierPath(
            roundedRect: NSRect(x: 0, y: outputSize.height - cornerRadius, width: outputSize.width, height: cornerRadius),
            xRadius: cornerRadius,
            yRadius: cornerRadius
        )
        titleBarColor.setFill()
        topCornerPath.fill()

        // Separator
        let separatorColor = effectiveDark ? NSColor(white: 0.08, alpha: 1) : NSColor(white: 0.82, alpha: 1)
        separatorColor.setFill()
        NSBezierPath(rect: NSRect(x: 0, y: outputSize.height - titleBarHeight, width: outputSize.width, height: 1)).fill()

        // Traffic lights
        drawTrafficLights(at: outputSize.height - titleBarHeight / 2, in: outputSize)

        // Tab
        let tabRect = NSRect(
            x: 80,
            y: outputSize.height - titleBarHeight + 6,
            width: 120,
            height: 26
        )
        let tabColor = effectiveDark ? NSColor(white: 0.14, alpha: 1) : NSColor(white: 0.98, alpha: 1)
        tabColor.setFill()
        NSBezierPath(roundedRect: tabRect, xRadius: 4, yRadius: 4).fill()

        let tabText = "untitled"
        let tabFont = NSFont.systemFont(ofSize: 11)
        let tabTextColor = effectiveDark ? NSColor(white: 0.65, alpha: 1) : NSColor(white: 0.35, alpha: 1)
        let tabAttributes: [NSAttributedString.Key: Any] = [
            .font: tabFont,
            .foregroundColor: tabTextColor,
        ]
        let tabTextSize = (tabText as NSString).size(withAttributes: tabAttributes)
        let tabTextPoint = NSPoint(
            x: tabRect.midX - tabTextSize.width / 2,
            y: tabRect.midY - tabTextSize.height / 2
        )
        (tabText as NSString).draw(at: tabTextPoint, withAttributes: tabAttributes)

        // Draw line number gutter
        let gutterRect = NSRect(x: 0, y: 0, width: gutterWidth, height: outputSize.height - titleBarHeight)
        let gutterColor = effectiveDark ? NSColor(white: 0.16, alpha: 1) : NSColor(white: 0.94, alpha: 1)
        gutterColor.setFill()

        // Clip gutter to bottom-left rounded corner
        let gutterClipPath = NSBezierPath()
        gutterClipPath.move(to: NSPoint(x: 0, y: cornerRadius))
        gutterClipPath.appendArc(withCenter: NSPoint(x: cornerRadius, y: cornerRadius), radius: cornerRadius, startAngle: 180, endAngle: 270)
        gutterClipPath.line(to: NSPoint(x: gutterWidth, y: 0))
        gutterClipPath.line(to: NSPoint(x: gutterWidth, y: gutterRect.height))
        gutterClipPath.line(to: NSPoint(x: 0, y: gutterRect.height))
        gutterClipPath.close()

        NSGraphicsContext.current?.saveGraphicsState()
        gutterClipPath.addClip()
        gutterColor.setFill()
        NSBezierPath(rect: gutterRect).fill()
        NSGraphicsContext.current?.restoreGraphicsState()

        // Draw line numbers
        let lineHeight: CGFloat = 18
        let lineFont = NSFont.monospacedSystemFont(ofSize: 10, weight: .regular)
        let lineColor = effectiveDark ? NSColor(white: 0.40, alpha: 1) : NSColor(white: 0.60, alpha: 1)
        let lineAttributes: [NSAttributedString.Key: Any] = [
            .font: lineFont,
            .foregroundColor: lineColor,
        ]

        let lineCount = Int(gutterRect.height / lineHeight)
        for i in 1...min(lineCount, 999) {
            let text = "\(i)"
            let textSize = (text as NSString).size(withAttributes: lineAttributes)
            let y = gutterRect.height - CGFloat(i) * lineHeight + (lineHeight - textSize.height) / 2
            if y < 0 { break }
            let x = gutterWidth - textSize.width - 8
            (text as NSString).draw(at: NSPoint(x: x, y: y), withAttributes: lineAttributes)
        }

        // Gutter separator
        let gutterSepColor = effectiveDark ? NSColor(white: 0.10, alpha: 1) : NSColor(white: 0.85, alpha: 1)
        gutterSepColor.setFill()
        NSBezierPath(rect: NSRect(x: gutterWidth, y: 0, width: 1, height: gutterRect.height)).fill()

        // Draw screenshot content next to gutter
        let contentRect = NSRect(x: gutterWidth, y: 0, width: outputSize.width - gutterWidth, height: outputSize.height - titleBarHeight)
        let contentClipPath = NSBezierPath()
        contentClipPath.move(to: NSPoint(x: gutterWidth, y: 0))
        contentClipPath.line(to: NSPoint(x: outputSize.width - cornerRadius, y: 0))
        contentClipPath.appendArc(withCenter: NSPoint(x: outputSize.width - cornerRadius, y: cornerRadius), radius: cornerRadius, startAngle: 270, endAngle: 360)
        contentClipPath.line(to: NSPoint(x: outputSize.width, y: contentRect.height))
        contentClipPath.line(to: NSPoint(x: gutterWidth, y: contentRect.height))
        contentClipPath.close()

        NSGraphicsContext.current?.saveGraphicsState()
        contentClipPath.addClip()
        screenshot.draw(in: contentRect)
        NSGraphicsContext.current?.restoreGraphicsState()

        image.unlockFocus()
        return image
    }

    // MARK: - Helpers

    private static func drawTrafficLights(at centerY: CGFloat, in size: NSSize) {
        let buttonColors: [NSColor] = [
            NSColor(red: 1.0, green: 0.38, blue: 0.34, alpha: 1),  // Red (close)
            NSColor(red: 1.0, green: 0.74, blue: 0.21, alpha: 1),  // Yellow (minimize)
            NSColor(red: 0.15, green: 0.78, blue: 0.25, alpha: 1), // Green (fullscreen)
        ]
        for (i, color) in buttonColors.enumerated() {
            let x = 16 + CGFloat(i) * 20
            let buttonRect = NSRect(x: x, y: centerY - 6, width: 12, height: 12)
            color.setFill()
            NSBezierPath(ovalIn: buttonRect).fill()
        }
    }
}
