import AppKit

// MARK: - Background Types

enum GradientDirection: String, CaseIterable {
    case horizontal
    case vertical
    case diagonal

    var displayName: String {
        switch self {
        case .horizontal: return "Horizontal"
        case .vertical: return "Vertical"
        case .diagonal: return "Diagonal"
        }
    }
}

enum BackgroundStyle: Equatable {
    case none
    case solid(NSColor)
    case gradient(NSColor, NSColor, GradientDirection)
}

struct BackgroundConfig: Equatable {
    var style: BackgroundStyle = .none
    var padding: CGFloat = 60
    var cornerRadius: CGFloat = 12
    var shadowEnabled: Bool = true
    var shadowRadius: CGFloat = 20
}

// MARK: - Background Renderer

struct BackgroundRenderer {
    /// Renders the screenshot on a decorative background with padding, corner radius, and optional shadow.
    static func render(screenshot: NSImage, config: BackgroundConfig) -> NSImage {
        let screenshotSize = screenshot.size

        // If no background style, just apply corner radius if needed
        if config.style == .none {
            if config.cornerRadius > 0 {
                return applyCornerRadius(to: screenshot, radius: config.cornerRadius)
            }
            return screenshot
        }

        let outputSize = NSSize(
            width: screenshotSize.width + config.padding * 2,
            height: screenshotSize.height + config.padding * 2
        )

        let image = NSImage(size: outputSize)
        image.lockFocus()

        guard let context = NSGraphicsContext.current?.cgContext else {
            image.unlockFocus()
            return screenshot
        }

        let fullRect = CGRect(origin: .zero, size: outputSize)

        // 1. Fill background
        switch config.style {
        case .none:
            break
        case .solid(let color):
            context.setFillColor(color.cgColor)
            context.fill(fullRect)
        case .gradient(let startColor, let endColor, let direction):
            drawGradient(
                in: context,
                rect: fullRect,
                startColor: startColor,
                endColor: endColor,
                direction: direction
            )
        }

        // 2. Calculate screenshot rect (centered)
        let screenshotRect = CGRect(
            x: config.padding,
            y: config.padding,
            width: screenshotSize.width,
            height: screenshotSize.height
        )

        // 3. Draw shadow if enabled
        if config.shadowEnabled {
            context.saveGState()
            let shadowColor = NSColor.black.withAlphaComponent(0.4).cgColor
            context.setShadow(
                offset: CGSize(width: 0, height: -4),
                blur: config.shadowRadius,
                color: shadowColor
            )
            // Draw a filled rounded rect to cast the shadow
            let shadowPath = CGPath(
                roundedRect: screenshotRect,
                cornerWidth: config.cornerRadius,
                cornerHeight: config.cornerRadius,
                transform: nil
            )
            context.setFillColor(NSColor.black.cgColor)
            context.addPath(shadowPath)
            context.fillPath()
            context.restoreGState()
        }

        // 4. Draw screenshot with corner radius clipping
        context.saveGState()
        if config.cornerRadius > 0 {
            let clipPath = CGPath(
                roundedRect: screenshotRect,
                cornerWidth: config.cornerRadius,
                cornerHeight: config.cornerRadius,
                transform: nil
            )
            context.addPath(clipPath)
            context.clip()
        }
        screenshot.draw(in: screenshotRect)
        context.restoreGState()

        image.unlockFocus()
        return image
    }

    // MARK: - Helpers

    private static func drawGradient(
        in context: CGContext,
        rect: CGRect,
        startColor: NSColor,
        endColor: NSColor,
        direction: GradientDirection
    ) {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let gradient = CGGradient(
            colorsSpace: colorSpace,
            colors: [startColor.cgColor, endColor.cgColor] as CFArray,
            locations: [0.0, 1.0]
        ) else { return }

        let startPoint: CGPoint
        let endPoint: CGPoint

        switch direction {
        case .horizontal:
            startPoint = CGPoint(x: rect.minX, y: rect.midY)
            endPoint = CGPoint(x: rect.maxX, y: rect.midY)
        case .vertical:
            startPoint = CGPoint(x: rect.midX, y: rect.minY)
            endPoint = CGPoint(x: rect.midX, y: rect.maxY)
        case .diagonal:
            startPoint = CGPoint(x: rect.minX, y: rect.minY)
            endPoint = CGPoint(x: rect.maxX, y: rect.maxY)
        }

        context.drawLinearGradient(
            gradient,
            start: startPoint,
            end: endPoint,
            options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
        )
    }

    private static func applyCornerRadius(to image: NSImage, radius: CGFloat) -> NSImage {
        let size = image.size
        let result = NSImage(size: size)
        result.lockFocus()

        guard let context = NSGraphicsContext.current?.cgContext else {
            result.unlockFocus()
            return image
        }

        let rect = CGRect(origin: .zero, size: size)
        let clipPath = CGPath(
            roundedRect: rect,
            cornerWidth: radius,
            cornerHeight: radius,
            transform: nil
        )
        context.addPath(clipPath)
        context.clip()
        image.draw(in: rect)

        result.unlockFocus()
        return result
    }
}
