import AppKit

/// Background style options for screenshot presentation
enum BackgroundStyle: Equatable {
    case none
    case solidColor(NSColor)
    case gradient(NSColor, NSColor, GradientDirection)
}

enum GradientDirection: String, CaseIterable {
    case topToBottom = "Top to Bottom"
    case leftToRight = "Left to Right"
    case diagonal = "Diagonal"
}

/// Device mockup frame definition
struct DeviceMockup: Identifiable {
    let id: String
    let name: String
    let category: MockupCategory

    /// Normalized screen rect (0-1) where the screenshot is placed within the frame
    let screenRect: CGRect

    /// Corner radius for the screenshot within the frame
    let screenCornerRadius: CGFloat

    /// Expected aspect ratio of screenshots for this device (height/width)
    let aspectRatio: CGFloat

    /// The drawing function that renders the device frame
    let renderFrame: (CGContext, CGSize) -> Void
}

enum MockupCategory: String, CaseIterable {
    case browser = "Browser"
    case terminal = "Terminal"
    case phone = "Phone"
    case laptop = "Laptop"
}

/// Built-in mockup frames (programmatically drawn, no asset dependencies)
struct MockupLibrary {
    static let allMockups: [DeviceMockup] = [
        safariLight,
        safariDark,
        terminalDark,
        genericPhone,
    ]

    static let safariLight = DeviceMockup(
        id: "safari-light",
        name: "Safari (Light)",
        category: .browser,
        screenRect: CGRect(x: 0, y: 0, width: 1, height: 0.93),
        screenCornerRadius: 0,
        aspectRatio: 0.625,
        renderFrame: { context, size in
            drawBrowserFrame(in: context, size: size, isDark: false)
        }
    )

    static let safariDark = DeviceMockup(
        id: "safari-dark",
        name: "Safari (Dark)",
        category: .browser,
        screenRect: CGRect(x: 0, y: 0, width: 1, height: 0.93),
        screenCornerRadius: 0,
        aspectRatio: 0.625,
        renderFrame: { context, size in
            drawBrowserFrame(in: context, size: size, isDark: true)
        }
    )

    static let terminalDark = DeviceMockup(
        id: "terminal-dark",
        name: "Terminal (Dark)",
        category: .terminal,
        screenRect: CGRect(x: 0, y: 0, width: 1, height: 0.92),
        screenCornerRadius: 0,
        aspectRatio: 0.625,
        renderFrame: { context, size in
            drawTerminalFrame(in: context, size: size)
        }
    )

    static let genericPhone = DeviceMockup(
        id: "generic-phone",
        name: "Phone",
        category: .phone,
        screenRect: CGRect(x: 0.06, y: 0.03, width: 0.88, height: 0.94),
        screenCornerRadius: 20,
        aspectRatio: 2.17,
        renderFrame: { context, size in
            drawPhoneFrame(in: context, size: size)
        }
    )

    // MARK: - Frame Drawing

    private static func drawBrowserFrame(in context: CGContext, size: CGSize, isDark: Bool) {
        let titleBarHeight = size.height * 0.07
        let barY = size.height - titleBarHeight

        // Title bar background
        let barColor = isDark
            ? NSColor(white: 0.2, alpha: 1).cgColor
            : NSColor(white: 0.95, alpha: 1).cgColor
        context.setFillColor(barColor)
        context.fill(CGRect(x: 0, y: barY, width: size.width, height: titleBarHeight))

        // Traffic lights
        let dotRadius: CGFloat = titleBarHeight * 0.18
        let dotY = barY + titleBarHeight / 2
        let startX: CGFloat = dotRadius * 2.5
        let spacing: CGFloat = dotRadius * 2.8

        let colors: [(CGFloat, CGFloat, CGFloat)] = [
            (1.0, 0.38, 0.36),  // Red
            (1.0, 0.74, 0.22),  // Yellow
            (0.33, 0.79, 0.33), // Green
        ]
        for (i, (r, g, b)) in colors.enumerated() {
            let x = startX + CGFloat(i) * spacing
            context.setFillColor(CGColor(red: r, green: g, blue: b, alpha: 1))
            context.fillEllipse(in: CGRect(x: x - dotRadius, y: dotY - dotRadius, width: dotRadius * 2, height: dotRadius * 2))
        }

        // URL bar
        let urlBarInset: CGFloat = size.width * 0.25
        let urlBarHeight = titleBarHeight * 0.5
        let urlBarY = barY + (titleBarHeight - urlBarHeight) / 2
        let urlBarColor = isDark
            ? NSColor(white: 0.12, alpha: 1).cgColor
            : NSColor(white: 0.88, alpha: 1).cgColor
        let urlBarRect = CGRect(x: urlBarInset, y: urlBarY, width: size.width - urlBarInset * 2, height: urlBarHeight)
        let urlPath = CGPath(roundedRect: urlBarRect, cornerWidth: urlBarHeight / 2, cornerHeight: urlBarHeight / 2, transform: nil)
        context.setFillColor(urlBarColor)
        context.addPath(urlPath)
        context.fillPath()

        // Bottom border
        let borderColor = isDark
            ? NSColor(white: 0.3, alpha: 1).cgColor
            : NSColor(white: 0.82, alpha: 1).cgColor
        context.setStrokeColor(borderColor)
        context.setLineWidth(1)
        context.move(to: CGPoint(x: 0, y: barY))
        context.addLine(to: CGPoint(x: size.width, y: barY))
        context.strokePath()
    }

    private static func drawTerminalFrame(in context: CGContext, size: CGSize) {
        let titleBarHeight = size.height * 0.08
        let barY = size.height - titleBarHeight

        // Title bar
        context.setFillColor(NSColor(white: 0.18, alpha: 1).cgColor)
        context.fill(CGRect(x: 0, y: barY, width: size.width, height: titleBarHeight))

        // Traffic lights
        let dotRadius: CGFloat = titleBarHeight * 0.18
        let dotY = barY + titleBarHeight / 2
        let startX: CGFloat = dotRadius * 2.5
        let spacing: CGFloat = dotRadius * 2.8

        let colors: [(CGFloat, CGFloat, CGFloat)] = [
            (1.0, 0.38, 0.36),
            (1.0, 0.74, 0.22),
            (0.33, 0.79, 0.33),
        ]
        for (i, (r, g, b)) in colors.enumerated() {
            let x = startX + CGFloat(i) * spacing
            context.setFillColor(CGColor(red: r, green: g, blue: b, alpha: 1))
            context.fillEllipse(in: CGRect(x: x - dotRadius, y: dotY - dotRadius, width: dotRadius * 2, height: dotRadius * 2))
        }

        // Title text
        let titleFont = NSFont.systemFont(ofSize: titleBarHeight * 0.4, weight: .medium)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: titleFont,
            .foregroundColor: NSColor(white: 0.6, alpha: 1),
        ]
        let titleString = NSAttributedString(string: "Terminal", attributes: attributes)
        let titleSize = titleString.size()
        let titleRect = CGRect(
            x: (size.width - titleSize.width) / 2,
            y: barY + (titleBarHeight - titleSize.height) / 2,
            width: titleSize.width,
            height: titleSize.height
        )

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        titleString.draw(in: titleRect)
        NSGraphicsContext.restoreGraphicsState()

        // Content area background (dark)
        context.setFillColor(NSColor(red: 0.1, green: 0.1, blue: 0.12, alpha: 1).cgColor)
        context.fill(CGRect(x: 0, y: 0, width: size.width, height: barY))
    }

    private static func drawPhoneFrame(in context: CGContext, size: CGSize) {
        let cornerRadius: CGFloat = size.width * 0.12

        // Phone body (dark border)
        let bodyPath = CGPath(roundedRect: CGRect(origin: .zero, size: size), cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)
        context.setFillColor(NSColor(white: 0.15, alpha: 1).cgColor)
        context.addPath(bodyPath)
        context.fillPath()

        // Inner border
        let inset: CGFloat = 3
        let innerRect = CGRect(origin: .zero, size: size).insetBy(dx: inset, dy: inset)
        let innerPath = CGPath(roundedRect: innerRect, cornerWidth: cornerRadius - inset, cornerHeight: cornerRadius - inset, transform: nil)
        context.setStrokeColor(NSColor(white: 0.3, alpha: 1).cgColor)
        context.setLineWidth(1)
        context.addPath(innerPath)
        context.strokePath()
    }
}

/// Composites a screenshot with a device mockup and optional background
struct BackgroundRenderer {
    /// Apply a background and optional device mockup to a screenshot.
    static func render(
        screenshot: NSImage,
        background: BackgroundStyle,
        mockup: DeviceMockup?,
        padding: CGFloat = 40,
        cornerRadius: CGFloat = 8
    ) -> NSImage {
        if background == .none && mockup == nil {
            return screenshot
        }

        let screenshotSize = screenshot.size
        let totalPadding = padding * 2

        // Calculate output size
        let outputWidth: CGFloat
        let outputHeight: CGFloat

        if let mockup = mockup {
            // Scale screenshot to fit within mockup's screen area
            let mockupWidth = screenshotSize.width / mockup.screenRect.width
            let mockupHeight = screenshotSize.height / mockup.screenRect.height
            outputWidth = mockupWidth + totalPadding
            outputHeight = mockupHeight + totalPadding
        } else {
            outputWidth = screenshotSize.width + totalPadding
            outputHeight = screenshotSize.height + totalPadding
        }

        let outputSize = CGSize(width: outputWidth, height: outputHeight)
        let result = NSImage(size: outputSize)
        result.lockFocus()

        guard let context = NSGraphicsContext.current?.cgContext else {
            result.unlockFocus()
            return screenshot
        }

        // Draw background
        let bgRect = CGRect(origin: .zero, size: outputSize)
        switch background {
        case .none:
            // Transparent
            context.clear(bgRect)
        case .solidColor(let color):
            context.setFillColor(color.cgColor)
            context.fill(bgRect)
        case .gradient(let start, let end, let direction):
            drawGradient(in: context, rect: bgRect, from: start, to: end, direction: direction)
        }

        if let mockup = mockup {
            let mockupWidth = screenshotSize.width / mockup.screenRect.width
            let mockupHeight = screenshotSize.height / mockup.screenRect.height
            let mockupSize = CGSize(width: mockupWidth, height: mockupHeight)
            let mockupOrigin = CGPoint(x: padding, y: padding)
            let mockupRect = CGRect(origin: mockupOrigin, size: mockupSize)

            // Draw mockup frame
            context.saveGState()
            context.translateBy(x: mockupOrigin.x, y: mockupOrigin.y)
            mockup.renderFrame(context, mockupSize)
            context.restoreGState()

            // Draw screenshot in screen area
            let screenRect = CGRect(
                x: mockupOrigin.x + mockup.screenRect.origin.x * mockupSize.width,
                y: mockupOrigin.y + mockup.screenRect.origin.y * mockupSize.height,
                width: mockup.screenRect.width * mockupSize.width,
                height: mockup.screenRect.height * mockupSize.height
            )

            if mockup.screenCornerRadius > 0 {
                let clipPath = CGPath(
                    roundedRect: screenRect,
                    cornerWidth: mockup.screenCornerRadius,
                    cornerHeight: mockup.screenCornerRadius,
                    transform: nil
                )
                context.saveGState()
                context.addPath(clipPath)
                context.clip()
                screenshot.draw(in: screenRect)
                context.restoreGState()
            } else {
                screenshot.draw(in: screenRect)
            }

            // Draw shadow
            if background != .none {
                context.saveGState()
                context.setShadow(offset: CGSize(width: 0, height: -4), blur: 20, color: NSColor.black.withAlphaComponent(0.3).cgColor)
                let shadowPath = CGPath(roundedRect: mockupRect, cornerWidth: 8, cornerHeight: 8, transform: nil)
                context.addPath(shadowPath)
                context.setFillColor(NSColor.clear.cgColor)
                context.fillPath()
                context.restoreGState()
            }
        } else {
            // No mockup — just draw screenshot with corner radius and shadow
            let screenshotRect = CGRect(
                x: padding,
                y: padding,
                width: screenshotSize.width,
                height: screenshotSize.height
            )

            if cornerRadius > 0 {
                let clipPath = CGPath(
                    roundedRect: screenshotRect,
                    cornerWidth: cornerRadius,
                    cornerHeight: cornerRadius,
                    transform: nil
                )
                context.saveGState()
                context.addPath(clipPath)
                context.clip()
                screenshot.draw(in: screenshotRect)
                context.restoreGState()
            } else {
                screenshot.draw(in: screenshotRect)
            }
        }

        result.unlockFocus()
        return result
    }

    private static func drawGradient(
        in context: CGContext,
        rect: CGRect,
        from startColor: NSColor,
        to endColor: NSColor,
        direction: GradientDirection
    ) {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let gradient = CGGradient(
            colorsSpace: colorSpace,
            colors: [startColor.cgColor, endColor.cgColor] as CFArray,
            locations: [0, 1]
        ) else { return }

        let startPoint: CGPoint
        let endPoint: CGPoint
        switch direction {
        case .topToBottom:
            startPoint = CGPoint(x: rect.midX, y: rect.maxY)
            endPoint = CGPoint(x: rect.midX, y: rect.minY)
        case .leftToRight:
            startPoint = CGPoint(x: rect.minX, y: rect.midY)
            endPoint = CGPoint(x: rect.maxX, y: rect.midY)
        case .diagonal:
            startPoint = CGPoint(x: rect.minX, y: rect.maxY)
            endPoint = CGPoint(x: rect.maxX, y: rect.minY)
        }

        context.drawLinearGradient(gradient, start: startPoint, end: endPoint, options: [])
    }
}
