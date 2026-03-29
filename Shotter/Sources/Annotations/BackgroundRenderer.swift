import AppKit

// MARK: - Background Style

enum BackgroundStyle: Equatable {
    case none
    case solidColor(NSColor)
    case gradient(NSColor, NSColor) // top, bottom

    var displayName: String {
        switch self {
        case .none: return "None"
        case .solidColor: return "Solid Color"
        case .gradient: return "Gradient"
        }
    }
}

// MARK: - Device Frame

enum DeviceFrame: String, CaseIterable, Identifiable {
    case none
    case browserSafari
    case browserChrome
    case terminal
    case codeEditor

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .none: return "None"
        case .browserSafari: return "Safari"
        case .browserChrome: return "Chrome"
        case .terminal: return "Terminal"
        case .codeEditor: return "Code Editor"
        }
    }

    /// Height of the frame's title bar / toolbar area
    var toolbarHeight: CGFloat {
        switch self {
        case .none: return 0
        case .browserSafari: return 52
        case .browserChrome: return 40
        case .terminal: return 28
        case .codeEditor: return 36
        }
    }
}

// MARK: - Mockup Configuration

struct MockupConfiguration {
    var background: BackgroundStyle = .none
    var deviceFrame: DeviceFrame = .none
    var padding: CGFloat = 40
    var cornerRadius: CGFloat = 12
    var shadow: Bool = true

    /// Preset background colors for quick selection
    static let presetBackgrounds: [(String, BackgroundStyle)] = [
        ("None", .none),
        ("White", .solidColor(.white)),
        ("Light Gray", .solidColor(NSColor(white: 0.95, alpha: 1))),
        ("Dark Gray", .solidColor(NSColor(white: 0.2, alpha: 1))),
        ("Black", .solidColor(.black)),
        ("Ocean", .gradient(
            NSColor(red: 0.16, green: 0.50, blue: 0.73, alpha: 1),
            NSColor(red: 0.07, green: 0.21, blue: 0.40, alpha: 1)
        )),
        ("Sunset", .gradient(
            NSColor(red: 0.98, green: 0.55, blue: 0.31, alpha: 1),
            NSColor(red: 0.85, green: 0.24, blue: 0.42, alpha: 1)
        )),
        ("Forest", .gradient(
            NSColor(red: 0.18, green: 0.76, blue: 0.49, alpha: 1),
            NSColor(red: 0.07, green: 0.39, blue: 0.27, alpha: 1)
        )),
        ("Purple Haze", .gradient(
            NSColor(red: 0.56, green: 0.27, blue: 0.68, alpha: 1),
            NSColor(red: 0.24, green: 0.10, blue: 0.40, alpha: 1)
        )),
        ("Sky", .gradient(
            NSColor(red: 0.53, green: 0.81, blue: 0.98, alpha: 1),
            NSColor(red: 0.25, green: 0.47, blue: 0.85, alpha: 1)
        )),
    ]
}

// MARK: - Background Renderer

struct BackgroundRenderer {

    /// Render a screenshot with background and optional device frame.
    static func render(screenshot: NSImage, config: MockupConfiguration) -> NSImage {
        let frameToolbarHeight = config.deviceFrame.toolbarHeight
        let screenshotSize = screenshot.size

        // Calculate the content area (screenshot + frame toolbar)
        let contentWidth = screenshotSize.width
        let contentHeight = screenshotSize.height + frameToolbarHeight

        // Total canvas size includes padding on all sides
        let totalWidth = contentWidth + config.padding * 2
        let totalHeight = contentHeight + config.padding * 2

        let canvasSize = CGSize(width: totalWidth, height: totalHeight)
        let result = NSImage(size: canvasSize)
        result.lockFocus()

        guard let context = NSGraphicsContext.current?.cgContext else {
            result.unlockFocus()
            return screenshot
        }

        // 1. Draw background
        drawBackground(config.background, in: context, size: canvasSize)

        // 2. Calculate frame rect (the area where the device frame + screenshot go)
        let frameRect = CGRect(
            x: config.padding,
            y: config.padding,
            width: contentWidth,
            height: contentHeight
        )

        // 3. Draw shadow if enabled
        if config.shadow {
            drawShadow(in: context, rect: frameRect, cornerRadius: config.cornerRadius)
        }

        // 4. Clip to rounded rect for the content area
        context.saveGState()
        let clipPath = CGPath(
            roundedRect: frameRect,
            cornerWidth: config.cornerRadius,
            cornerHeight: config.cornerRadius,
            transform: nil
        )
        context.addPath(clipPath)
        context.clip()

        // 5. Draw screenshot at the bottom of the frame rect
        let screenshotRect = CGRect(
            x: frameRect.minX,
            y: frameRect.minY,
            width: screenshotSize.width,
            height: screenshotSize.height
        )
        screenshot.draw(in: screenshotRect)

        // 6. Draw device frame toolbar on top of the screenshot
        if config.deviceFrame != .none {
            drawDeviceFrame(config.deviceFrame, in: context, frameRect: frameRect, screenshotSize: screenshotSize)
        }

        context.restoreGState()

        result.unlockFocus()
        return result
    }

    // MARK: - Background Drawing

    private static func drawBackground(_ style: BackgroundStyle, in context: CGContext, size: CGSize) {
        let rect = CGRect(origin: .zero, size: size)

        switch style {
        case .none:
            // Transparent / checkerboard - just leave transparent
            break

        case .solidColor(let color):
            context.setFillColor(color.cgColor)
            context.fill(rect)

        case .gradient(let topColor, let bottomColor):
            let colorSpace = CGColorSpaceCreateDeviceRGB()
            let colors = [topColor.cgColor, bottomColor.cgColor] as CFArray
            if let gradient = CGGradient(colorsSpace: colorSpace, colors: colors, locations: [0.0, 1.0]) {
                context.drawLinearGradient(
                    gradient,
                    start: CGPoint(x: size.width / 2, y: size.height),
                    end: CGPoint(x: size.width / 2, y: 0),
                    options: []
                )
            }
        }
    }

    // MARK: - Shadow Drawing

    private static func drawShadow(in context: CGContext, rect: CGRect, cornerRadius: CGFloat) {
        context.saveGState()
        context.setShadow(
            offset: CGSize(width: 0, height: -8),
            blur: 30,
            color: NSColor.black.withAlphaComponent(0.35).cgColor
        )
        let shadowPath = CGPath(
            roundedRect: rect,
            cornerWidth: cornerRadius,
            cornerHeight: cornerRadius,
            transform: nil
        )
        context.setFillColor(NSColor.white.cgColor)
        context.addPath(shadowPath)
        context.fillPath()
        context.restoreGState()
    }

    // MARK: - Device Frame Drawing

    private static func drawDeviceFrame(
        _ frame: DeviceFrame,
        in context: CGContext,
        frameRect: CGRect,
        screenshotSize: CGSize
    ) {
        switch frame {
        case .none:
            break
        case .browserSafari:
            drawSafariFrame(in: context, frameRect: frameRect)
        case .browserChrome:
            drawChromeFrame(in: context, frameRect: frameRect)
        case .terminal:
            drawTerminalFrame(in: context, frameRect: frameRect)
        case .codeEditor:
            drawCodeEditorFrame(in: context, frameRect: frameRect)
        }
    }

    // MARK: - Safari Browser Frame

    private static func drawSafariFrame(in context: CGContext, frameRect: CGRect) {
        let toolbarHeight: CGFloat = DeviceFrame.browserSafari.toolbarHeight
        let toolbarRect = CGRect(
            x: frameRect.minX,
            y: frameRect.maxY - toolbarHeight,
            width: frameRect.width,
            height: toolbarHeight
        )

        // Toolbar background - light gray
        context.setFillColor(NSColor(white: 0.96, alpha: 1).cgColor)
        context.fill(toolbarRect)

        // Bottom border of toolbar
        context.setStrokeColor(NSColor(white: 0.85, alpha: 1).cgColor)
        context.setLineWidth(1)
        context.move(to: CGPoint(x: toolbarRect.minX, y: toolbarRect.minY))
        context.addLine(to: CGPoint(x: toolbarRect.maxX, y: toolbarRect.minY))
        context.strokePath()

        // Traffic lights
        let buttonY = toolbarRect.minY + (toolbarHeight - 12) / 2
        drawTrafficLights(in: context, x: frameRect.minX + 20, y: buttonY)

        // Address bar (centered, rounded rect)
        let addressBarWidth = min(frameRect.width - 200, 400)
        let addressBarX = frameRect.minX + (frameRect.width - addressBarWidth) / 2
        let addressBarRect = CGRect(
            x: addressBarX,
            y: toolbarRect.minY + (toolbarHeight - 28) / 2,
            width: addressBarWidth,
            height: 28
        )
        let addressPath = CGPath(
            roundedRect: addressBarRect,
            cornerWidth: 6,
            cornerHeight: 6,
            transform: nil
        )
        context.setFillColor(NSColor(white: 0.90, alpha: 1).cgColor)
        context.addPath(addressPath)
        context.fillPath()

        // URL text placeholder
        drawText(
            "example.com",
            in: context,
            at: CGPoint(x: addressBarRect.midX, y: addressBarRect.midY),
            color: NSColor(white: 0.55, alpha: 1),
            fontSize: 12,
            centered: true
        )
    }

    // MARK: - Chrome Browser Frame

    private static func drawChromeFrame(in context: CGContext, frameRect: CGRect) {
        let toolbarHeight: CGFloat = DeviceFrame.browserChrome.toolbarHeight
        let toolbarRect = CGRect(
            x: frameRect.minX,
            y: frameRect.maxY - toolbarHeight,
            width: frameRect.width,
            height: toolbarHeight
        )

        // Toolbar background - slightly darker gray
        context.setFillColor(NSColor(white: 0.92, alpha: 1).cgColor)
        context.fill(toolbarRect)

        // Bottom border
        context.setStrokeColor(NSColor(white: 0.82, alpha: 1).cgColor)
        context.setLineWidth(1)
        context.move(to: CGPoint(x: toolbarRect.minX, y: toolbarRect.minY))
        context.addLine(to: CGPoint(x: toolbarRect.maxX, y: toolbarRect.minY))
        context.strokePath()

        // Traffic lights
        let buttonY = toolbarRect.minY + (toolbarHeight - 12) / 2
        drawTrafficLights(in: context, x: frameRect.minX + 14, y: buttonY)

        // Tab shape (simplified: just a rounded rect representing the active tab)
        let tabRect = CGRect(
            x: frameRect.minX + 80,
            y: toolbarRect.minY + 8,
            width: 160,
            height: toolbarHeight - 8
        )
        let tabPath = CGMutablePath()
        tabPath.addRoundedRect(in: tabRect, cornerWidth: 8, cornerHeight: 8)
        context.setFillColor(NSColor(white: 0.98, alpha: 1).cgColor)
        context.addPath(tabPath)
        context.fillPath()

        // Tab title
        drawText(
            "New Tab",
            in: context,
            at: CGPoint(x: tabRect.midX, y: tabRect.midY),
            color: NSColor(white: 0.4, alpha: 1),
            fontSize: 11,
            centered: true
        )
    }

    // MARK: - Terminal Frame

    private static func drawTerminalFrame(in context: CGContext, frameRect: CGRect) {
        let toolbarHeight: CGFloat = DeviceFrame.terminal.toolbarHeight
        let toolbarRect = CGRect(
            x: frameRect.minX,
            y: frameRect.maxY - toolbarHeight,
            width: frameRect.width,
            height: toolbarHeight
        )

        // Dark toolbar background
        context.setFillColor(NSColor(white: 0.22, alpha: 1).cgColor)
        context.fill(toolbarRect)

        // Bottom border
        context.setStrokeColor(NSColor(white: 0.15, alpha: 1).cgColor)
        context.setLineWidth(1)
        context.move(to: CGPoint(x: toolbarRect.minX, y: toolbarRect.minY))
        context.addLine(to: CGPoint(x: toolbarRect.maxX, y: toolbarRect.minY))
        context.strokePath()

        // Traffic lights
        let buttonY = toolbarRect.minY + (toolbarHeight - 12) / 2
        drawTrafficLights(in: context, x: frameRect.minX + 12, y: buttonY)

        // Title
        drawText(
            "Terminal",
            in: context,
            at: CGPoint(x: frameRect.midX, y: toolbarRect.midY),
            color: NSColor(white: 0.7, alpha: 1),
            fontSize: 12,
            centered: true
        )
    }

    // MARK: - Code Editor Frame

    private static func drawCodeEditorFrame(in context: CGContext, frameRect: CGRect) {
        let toolbarHeight: CGFloat = DeviceFrame.codeEditor.toolbarHeight
        let toolbarRect = CGRect(
            x: frameRect.minX,
            y: frameRect.maxY - toolbarHeight,
            width: frameRect.width,
            height: toolbarHeight
        )

        // Dark toolbar (VS Code style)
        context.setFillColor(NSColor(red: 0.2, green: 0.2, blue: 0.24, alpha: 1).cgColor)
        context.fill(toolbarRect)

        // Bottom border
        context.setStrokeColor(NSColor(red: 0.15, green: 0.15, blue: 0.18, alpha: 1).cgColor)
        context.setLineWidth(1)
        context.move(to: CGPoint(x: toolbarRect.minX, y: toolbarRect.minY))
        context.addLine(to: CGPoint(x: toolbarRect.maxX, y: toolbarRect.minY))
        context.strokePath()

        // Traffic lights
        let buttonY = toolbarRect.minY + (toolbarHeight - 12) / 2
        drawTrafficLights(in: context, x: frameRect.minX + 12, y: buttonY)

        // File tab
        let tabRect = CGRect(
            x: frameRect.minX + 80,
            y: toolbarRect.minY,
            width: 120,
            height: toolbarHeight
        )
        context.setFillColor(NSColor(red: 0.12, green: 0.12, blue: 0.16, alpha: 1).cgColor)
        context.fill(tabRect)

        drawText(
            "Untitled",
            in: context,
            at: CGPoint(x: tabRect.midX, y: tabRect.midY),
            color: NSColor(white: 0.75, alpha: 1),
            fontSize: 11,
            centered: true
        )
    }

    // MARK: - Shared Drawing Helpers

    private static func drawTrafficLights(in context: CGContext, x: CGFloat, y: CGFloat) {
        let colors: [(CGFloat, CGFloat, CGFloat)] = [
            (0.94, 0.32, 0.28), // red
            (0.98, 0.74, 0.17), // yellow
            (0.15, 0.78, 0.32), // green
        ]
        for (i, rgb) in colors.enumerated() {
            let cx = x + CGFloat(i) * 22
            context.setFillColor(
                CGColor(red: rgb.0, green: rgb.1, blue: rgb.2, alpha: 1)
            )
            context.fillEllipse(in: CGRect(x: cx, y: y, width: 12, height: 12))
        }
    }

    private static func drawText(
        _ text: String,
        in context: CGContext,
        at point: CGPoint,
        color: NSColor,
        fontSize: CGFloat,
        centered: Bool
    ) {
        let font = NSFont.systemFont(ofSize: fontSize)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
        ]
        let nsString = text as NSString
        let size = nsString.size(withAttributes: attributes)

        let drawPoint: CGPoint
        if centered {
            drawPoint = CGPoint(x: point.x - size.width / 2, y: point.y - size.height / 2)
        } else {
            drawPoint = point
        }

        // Use NSString drawing (works within lockFocus context)
        context.saveGState()
        // NSString.draw uses a flipped coordinate system, so we need to flip
        let transform = CGAffineTransform(translationX: 0, y: drawPoint.y * 2 + size.height)
            .scaledBy(x: 1, y: -1)
        context.concatenate(transform)
        nsString.draw(at: drawPoint, withAttributes: attributes)
        context.concatenate(transform.inverted())
        context.restoreGState()
    }
}
