import AppKit

/// Shared compositing for the beautify "background" frame. The same routine
/// drives the live canvas preview and the final export so they stay pixel-identical.
///
/// All drawing assumes a bottom-left origin CGContext in the same coordinate
/// space as `layout` (view points for preview, output points for export).
enum BackgroundRenderer {

    /// Corners of a rect, in bottom-left coordinate space.
    struct Corners: OptionSet {
        let rawValue: Int
        static let topLeft = Corners(rawValue: 1 << 0)
        static let topRight = Corners(rawValue: 1 << 1)
        static let bottomLeft = Corners(rawValue: 1 << 2)
        static let bottomRight = Corners(rawValue: 1 << 3)
        static let all: Corners = [.topLeft, .topRight, .bottomLeft, .bottomRight]
        static let bottom: Corners = [.bottomLeft, .bottomRight]
    }

    /// Draws the background fill, drop shadow, and window chrome, then invokes
    /// `drawScreenshot(contentRect)` with a rounded clip already applied so the
    /// screenshot picks up the frame's corner treatment.
    static func drawBeautified(
        in ctx: CGContext,
        layout: BeautifyLayout,
        style: BackgroundStyle,
        imageSize: CGSize,
        drawScreenshot: (CGRect) -> Void
    ) {
        // 1) Background fill across the whole canvas.
        switch style.kind {
        case .none:
            break // transparent — leave whatever is behind
        case .solid:
            ctx.saveGState()
            ctx.setFillColor(style.solidColor.cgColor)
            ctx.fill(layout.canvasRect)
            ctx.restoreGState()
        case .gradient:
            drawGradient(style.gradient.colors, in: layout.canvasRect, context: ctx)
        }

        let radius = layout.cornerRadius
        let windowRect = layout.windowRect
        let hasFrame = style.frame != .none

        // 2) Drop shadow — cast by an opaque rounded card behind the content.
        if style.shadowStrength > 0.001 {
            let minSide = min(windowRect.width, windowRect.height)
            let strength = CGFloat(style.shadowStrength)
            let blur = minSide * 0.06 * (0.4 + strength)
            let dy = -minSide * 0.03 * strength
            let alpha = min(0.6, 0.12 + 0.5 * strength)

            ctx.saveGState()
            ctx.setShadow(offset: CGSize(width: 0, height: dy), blur: blur,
                          color: NSColor.black.withAlphaComponent(alpha).cgColor)
            ctx.addPath(roundedPath(windowRect, radius: radius, corners: .all))
            ctx.setFillColor((hasFrame ? style.frame.barColor : NSColor.white).cgColor)
            ctx.fillPath()
            ctx.restoreGState()
        }

        // 3) Window chrome (title bar + controls) for framed styles.
        if hasFrame {
            drawTitleBar(in: ctx, layout: layout, style: style, radius: radius)
        }

        // 4) Screenshot, clipped to the window's rounded shape.
        ctx.saveGState()
        ctx.addPath(roundedPath(windowRect, radius: radius, corners: .all))
        ctx.clip()
        // Intersect with the content strip so the title bar area stays visible.
        ctx.clip(to: layout.contentRect)
        drawScreenshot(layout.contentRect)
        ctx.restoreGState()
    }

    // MARK: - Title bar

    private static func drawTitleBar(in ctx: CGContext, layout: BeautifyLayout,
                                     style: BackgroundStyle, radius: CGFloat) {
        let windowRect = layout.windowRect
        let barHeight = layout.titleBarHeight
        guard barHeight > 0 else { return }

        let barRect = CGRect(x: windowRect.minX, y: windowRect.maxY - barHeight,
                             width: windowRect.width, height: barHeight)

        // Fill the bar, keeping the window's rounded top corners.
        ctx.saveGState()
        ctx.addPath(roundedPath(windowRect, radius: radius, corners: .all))
        ctx.clip()
        ctx.clip(to: barRect)
        ctx.setFillColor(style.frame.barColor.cgColor)
        ctx.fill(barRect)
        // Subtle separator under the bar.
        ctx.setFillColor(NSColor.black.withAlphaComponent(style.frame.isDark ? 0.25 : 0.08).cgColor)
        ctx.fill(CGRect(x: barRect.minX, y: barRect.minY, width: barRect.width, height: max(0.5, barHeight * 0.02)))
        ctx.restoreGState()

        // Traffic-light controls.
        let r = barHeight * 0.15
        let cy = barRect.midY
        var cx = barRect.minX + barHeight * 0.62
        let dotColors = [NSColor(hex: "#FF5F57"), NSColor(hex: "#FEBC2E"), NSColor(hex: "#28C840")]
        for color in dotColors {
            ctx.setFillColor(color.cgColor)
            ctx.fillEllipse(in: CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2))
            cx += r * 3.4
        }

        // Browser URL pill.
        if style.frame.isBrowser {
            let pillW = windowRect.width * 0.46
            let pillH = barHeight * 0.44
            let pillRect = CGRect(x: barRect.midX - pillW / 2, y: cy - pillH / 2,
                                  width: pillW, height: pillH)
            ctx.addPath(roundedPath(pillRect, radius: pillH / 2, corners: .all))
            ctx.setFillColor((style.frame.isDark ? NSColor(hex: "#404044") : NSColor.white).cgColor)
            ctx.fillPath()
        }
    }

    // MARK: - Gradient

    static func drawGradient(_ colors: [NSColor], in rect: CGRect, context ctx: CGContext) {
        guard !colors.isEmpty else { return }
        let cgColors = colors.compactMap { $0.usingColorSpace(.sRGB)?.cgColor } as CFArray
        let locations: [CGFloat] = colors.count == 1
            ? [0]
            : (0..<colors.count).map { CGFloat($0) / CGFloat(colors.count - 1) }

        guard let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                                        colors: cgColors, locations: locations) else { return }
        ctx.saveGState()
        ctx.clip(to: rect)
        // Diagonal top-left → bottom-right.
        let start = CGPoint(x: rect.minX, y: rect.maxY)
        let end = CGPoint(x: rect.maxX, y: rect.minY)
        ctx.drawLinearGradient(gradient, start: start, end: end,
                               options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        ctx.restoreGState()
    }

    // MARK: - Rounded path

    static func roundedPath(_ rect: CGRect, radius: CGFloat, corners: Corners) -> CGPath {
        let path = CGMutablePath()
        let r = max(0, min(radius, min(rect.width, rect.height) / 2))
        if r <= 0 {
            path.addRect(rect)
            return path
        }

        let tl = corners.contains(.topLeft) ? r : 0
        let tr = corners.contains(.topRight) ? r : 0
        let bl = corners.contains(.bottomLeft) ? r : 0
        let br = corners.contains(.bottomRight) ? r : 0

        // Bottom-left origin. Start at bottom edge, go clockwise.
        path.move(to: CGPoint(x: rect.minX + bl, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - br, y: rect.minY))
        path.addArc(tangent1End: CGPoint(x: rect.maxX, y: rect.minY),
                    tangent2End: CGPoint(x: rect.maxX, y: rect.minY + br), radius: br)
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - tr))
        path.addArc(tangent1End: CGPoint(x: rect.maxX, y: rect.maxY),
                    tangent2End: CGPoint(x: rect.maxX - tr, y: rect.maxY), radius: tr)
        path.addLine(to: CGPoint(x: rect.minX + tl, y: rect.maxY))
        path.addArc(tangent1End: CGPoint(x: rect.minX, y: rect.maxY),
                    tangent2End: CGPoint(x: rect.minX, y: rect.maxY - tl), radius: tl)
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + bl))
        path.addArc(tangent1End: CGPoint(x: rect.minX, y: rect.minY),
                    tangent2End: CGPoint(x: rect.minX + bl, y: rect.minY), radius: bl)
        path.closeSubpath()
        return path
    }

    // MARK: - Export

    /// Composites the beautify frame around an already-annotated screenshot,
    /// rendered at the screenshot's native pixel density. Returns the annotated
    /// screenshot unchanged when the style is inactive.
    static func renderBeautified(annotated: NSImage, imageSize: CGSize, style: BackgroundStyle) -> NSImage {
        guard style.isActive,
              let annotatedCG = annotated.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return annotated
        }

        // Pixel density of the source (Retina screenshots are typically 2x).
        let px = max(1, CGFloat(annotatedCG.width) / max(imageSize.width, 1))

        // Compute the canvas in point space (viewSize == canvasSize → scale 1),
        // then scale the whole context by px for native-resolution output.
        let refDim = max(imageSize.width, imageSize.height)
        let padPts = CGFloat(style.paddingFraction) * refDim
        let titlePts = style.titleBarHeight(imageWidth: imageSize.width)
        let canvasPts = CGSize(width: imageSize.width + 2 * padPts,
                               height: imageSize.height + titlePts + 2 * padPts)

        let pixelW = Int((canvasPts.width * px).rounded())
        let pixelH = Int((canvasPts.height * px).rounded())
        guard pixelW > 0, pixelH > 0,
              let ctx = CGContext(data: nil, width: pixelW, height: pixelH,
                                  bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            return annotated
        }

        ctx.scaleBy(x: px, y: px)
        ctx.interpolationQuality = .high

        let layout = beautifyLayout(viewSize: canvasPts, imageSize: imageSize, style: style)
        drawBeautified(in: ctx, layout: layout, style: style, imageSize: imageSize) { contentRect in
            ctx.draw(annotatedCG, in: contentRect)
        }

        guard let outCG = ctx.makeImage() else { return annotated }
        return NSImage(cgImage: outCG, size: canvasPts)
    }
}
