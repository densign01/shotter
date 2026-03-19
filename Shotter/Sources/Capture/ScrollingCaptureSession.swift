import AppKit
import ScreenCaptureKit
import os.log

private let scrollingLogger = Logger(subsystem: "com.densign.shotter", category: "ScrollingCapture")

struct WindowSelectionResult {
    let window: SCWindow
    let clickPoint: CGPoint
}

private enum StitchAppendResult {
    case appended(Int)
    case noProgress
    case failed
}

private struct ScrollProbeResult {
    let viewport: ViewportAnalysis
    let secondFrame: AnalyzedFrame
    let scrollLocation: CGPoint
}

final class ScrollingCaptureSession {
    typealias WindowCapture = (SCWindow) async -> NSImage?

    private struct Configuration {
        let activationDelayNanoseconds: UInt64 = 350_000_000
        let scrollSettleDelayNanoseconds: UInt64 = 450_000_000
        let interPulseDelayNanoseconds: UInt64 = 20_000_000
        let maxFrames = 20
        let maxOutputHeightPixels = 40_000
        let initialScrollStepFraction: CGFloat = 0.45
        let steadyStateScrollStepFraction: CGFloat = 0.72
        let minimumProgressPixels = 24
        let scrollPulsePixels = 120
        let minimumFrameDifferenceForFallback = 0.018
    }

    private let selection: WindowSelectionResult
    private let captureWindow: WindowCapture
    private let configuration = Configuration()

    init(selection: WindowSelectionResult, captureWindow: @escaping WindowCapture) {
        self.selection = selection
        self.captureWindow = captureWindow
    }

    func capture() async -> NSImage? {
        guard let owningApplication = selection.window.owningApplication else {
            scrollingLogger.warning("Selected window has no owning application; falling back to single capture")
            return await captureWindow(selection.window)
        }

        await bringTargetAppToFront(pid: owningApplication.processID)

        guard let firstImage = await captureWindow(selection.window),
              let firstFrame = AnalyzedFrame(image: firstImage) else {
            scrollingLogger.error("Failed to capture initial window frame")
            return nil
        }

        let fallbackImage = firstImage
        let initialScrollStep = max(160, Int(firstFrame.sizeInPoints.height * configuration.initialScrollStepFraction))
        guard let probeResult = await probeScroll(
            from: firstFrame,
            fallbackImage: fallbackImage,
            initialScrollStep: initialScrollStep
        ) else {
            scrollingLogger.info("No scrolling movement detected; returning single window capture")
            return fallbackImage
        }

        let viewport = probeResult.viewport
        let secondFrame = probeResult.secondFrame
        var scrollLocation = probeResult.scrollLocation

        let steadyStateScrollStep = max(
            160,
            Int((CGFloat(viewport.pixelRect.height) / firstFrame.pixelScale) * configuration.steadyStateScrollStepFraction)
        )
        scrollLocation = preferredScrollLocation(for: viewport, fallback: scrollLocation)

        var stitcher = VerticalImageStitcher(
            viewportRect: viewport.pixelRect,
            pixelScale: firstFrame.pixelScale,
            maxOutputHeightPixels: configuration.maxOutputHeightPixels,
            minimumProgressPixels: configuration.minimumProgressPixels
        )

        guard stitcher.start(with: firstFrame) else {
            scrollingLogger.error("Failed to initialize stitcher with first frame")
            return fallbackImage
        }

        switch stitcher.append(secondFrame) {
        case .appended:
            break
        case .noProgress:
            return stitcher.render() ?? fallbackImage
        case .failed:
            return fallbackImage
        }

        if stitcher.hasReachedOutputLimit {
            return stitcher.render() ?? fallbackImage
        }

        for _ in 2..<configuration.maxFrames {
            guard await scroll(by: steadyStateScrollStep, at: scrollLocation) else {
                break
            }

            try? await Task.sleep(nanoseconds: configuration.scrollSettleDelayNanoseconds)

            guard let image = await captureWindow(selection.window),
                  let frame = AnalyzedFrame(image: image) else {
                break
            }

            switch stitcher.append(frame) {
            case .appended:
                if stitcher.hasReachedOutputLimit {
                    return stitcher.render() ?? fallbackImage
                }
            case .noProgress:
                return stitcher.render() ?? fallbackImage
            case .failed:
                return stitcher.render() ?? fallbackImage
            }
        }

        return stitcher.render() ?? fallbackImage
    }

    private func bringTargetAppToFront(pid: pid_t) async {
        _ = await MainActor.run {
            guard let application = NSRunningApplication(processIdentifier: pid) else {
                return false
            }
            return application.activate(options: [.activateAllWindows])
        }
        try? await Task.sleep(nanoseconds: configuration.activationDelayNanoseconds)
    }

    private func probeScroll(
        from firstFrame: AnalyzedFrame,
        fallbackImage: NSImage,
        initialScrollStep: Int
    ) async -> ScrollProbeResult? {
        for location in scrollProbeLocations() {
            guard await scroll(by: initialScrollStep, at: location) else {
                continue
            }

            try? await Task.sleep(nanoseconds: configuration.scrollSettleDelayNanoseconds)

            guard let secondImage = await captureWindow(selection.window),
                  let secondFrame = AnalyzedFrame(image: secondImage) else {
                continue
            }

            if let viewport = ViewportAnalyzer.detectViewport(first: firstFrame, second: secondFrame) {
                return ScrollProbeResult(
                    viewport: viewport,
                    secondFrame: secondFrame,
                    scrollLocation: preferredScrollLocation(for: viewport, fallback: location)
                )
            }

            if let viewport = ViewportAnalyzer.fullFrameFallback(
                first: firstFrame,
                second: secondFrame,
                minimumDifference: configuration.minimumFrameDifferenceForFallback
            ) {
                scrollingLogger.info("Detected frame movement without clear viewport; using full window fallback")
                return ScrollProbeResult(
                    viewport: viewport,
                    secondFrame: secondFrame,
                    scrollLocation: location
                )
            }
        }

        return nil
    }

    private func scrollProbeLocations() -> [CGPoint] {
        let windowFrame = selection.window.frame
        let clickedPoint = NSScreen.convertToSCK(selection.clickPoint)
        let relativeX = (clickedPoint.x - windowFrame.minX) / max(windowFrame.width, 1)
        let relativeY = (clickedPoint.y - windowFrame.minY) / max(windowFrame.height, 1)
        let safeClick = windowFrame.contains(clickedPoint)
            && relativeX >= 0.18 && relativeX <= 0.82
            && relativeY >= 0.28 && relativeY <= 0.88

        var locations: [CGPoint] = []

        if safeClick {
            locations.append(clickedPoint)
        }

        locations.append(
            CGPoint(
                x: windowFrame.midX,
                y: windowFrame.minY + (windowFrame.height * 0.62)
            )
        )
        locations.append(
            CGPoint(
                x: windowFrame.midX,
                y: windowFrame.minY + (windowFrame.height * 0.76)
            )
        )
        locations.append(
            CGPoint(
                x: windowFrame.midX,
                y: windowFrame.minY + (windowFrame.height * 0.5)
            )
        )

        var uniqueLocations: [CGPoint] = []
        for location in locations {
            let alreadyIncluded = uniqueLocations.contains { existing in
                abs(existing.x - location.x) < 4 && abs(existing.y - location.y) < 4
            }
            if !alreadyIncluded {
                uniqueLocations.append(location)
            }
        }

        return uniqueLocations
    }

    private func viewportScrollLocation(normalizedRect: CGRect) -> CGPoint {
        let windowFrame = selection.window.frame
        return CGPoint(
            x: windowFrame.minX + normalizedRect.midX * windowFrame.width,
            y: windowFrame.minY + normalizedRect.midY * windowFrame.height
        )
    }

    private func preferredScrollLocation(for viewport: ViewportAnalysis, fallback: CGPoint) -> CGPoint {
        let location = viewportScrollLocation(normalizedRect: viewport.normalizedRect)
        let windowFrame = selection.window.frame
        guard windowFrame.contains(location) else {
            return fallback
        }
        return location
    }

    private func scroll(by pixels: Int, at location: CGPoint) async -> Bool {
        var remaining = pixels

        while remaining > 0 {
            let pulse = min(configuration.scrollPulsePixels, remaining)
            guard let event = makeScrollEvent(delta: -pulse, location: location, phase: remaining == pixels ? .began : .changed) else {
                return false
            }
            event.post(tap: .cghidEventTap)

            remaining -= pulse
            if remaining > 0 {
                try? await Task.sleep(nanoseconds: configuration.interPulseDelayNanoseconds)
            }
        }

        if let endEvent = makeScrollEvent(delta: 0, location: location, phase: .ended) {
            endEvent.post(tap: .cghidEventTap)
        }

        return true
    }

    private func makeScrollEvent(delta: Int, location: CGPoint, phase: CGScrollPhase) -> CGEvent? {
        guard let source = CGEventSource(stateID: .hidSystemState),
              let event = CGEvent(
                scrollWheelEvent2Source: source,
                units: .pixel,
                wheelCount: 1,
                wheel1: Int32(delta),
                wheel2: 0,
                wheel3: 0
              ) else {
            return nil
        }

        event.location = location
        event.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
        event.setIntegerValueField(.scrollWheelEventPointDeltaAxis1, value: Int64(delta))
        event.setIntegerValueField(.scrollWheelEventScrollPhase, value: Int64(phase.rawValue))
        event.setIntegerValueField(.scrollWheelEventMomentumPhase, value: Int64(CGMomentumScrollPhase.none.rawValue))
        return event
    }
}

private struct PixelRect {
    let x: Int
    let y: Int
    let width: Int
    let height: Int

    var cgRect: CGRect {
        CGRect(x: x, y: y, width: width, height: height)
    }

    func normalized(in frame: AnalyzedFrame) -> CGRect {
        CGRect(
            x: CGFloat(x) / CGFloat(frame.width),
            y: CGFloat(y) / CGFloat(frame.height),
            width: CGFloat(width) / CGFloat(frame.width),
            height: CGFloat(height) / CGFloat(frame.height)
        )
    }
}

private struct ViewportAnalysis {
    let pixelRect: PixelRect
    let normalizedRect: CGRect
}

private struct ViewportAnalyzer {
    static func detectViewport(first: AnalyzedFrame, second: AnalyzedFrame) -> ViewportAnalysis? {
        guard first.width == second.width, first.height == second.height else {
            return nil
        }

        let width = first.width
        let height = first.height
        guard width > 120, height > 120 else {
            return nil
        }

        let horizontalInset = max(24, width / 10)
        let rowThreshold = 0.055

        let top = firstChangedRow(
            first: first,
            second: second,
            in: horizontalInset..<(width - horizontalInset),
            threshold: rowThreshold
        )
        let bottom = lastChangedRow(
            first: first,
            second: second,
            in: horizontalInset..<(width - horizontalInset),
            threshold: rowThreshold
        )

        guard let topRow = top, let bottomRow = bottom, bottomRow - topRow > height / 3 else {
            return nil
        }

        let verticalInset = max(12, (bottomRow - topRow) / 14)
        let adjustedTop = max(0, topRow - verticalInset)
        let adjustedBottom = min(height, bottomRow + verticalInset)
        let columnThreshold = 0.055

        let left = firstChangedColumn(
            first: first,
            second: second,
            in: adjustedTop..<adjustedBottom,
            threshold: columnThreshold
        ) ?? 0
        let right = lastChangedColumn(
            first: first,
            second: second,
            in: adjustedTop..<adjustedBottom,
            threshold: columnThreshold
        ) ?? width

        let minimumViewportWidth = width / 3
        let finalLeft: Int
        let finalRight: Int
        if right - left >= minimumViewportWidth {
            finalLeft = max(0, left - 8)
            finalRight = min(width, right + 8)
        } else {
            finalLeft = 0
            finalRight = width
        }

        let pixelRect = PixelRect(
            x: finalLeft,
            y: adjustedTop,
            width: finalRight - finalLeft,
            height: adjustedBottom - adjustedTop
        )
        guard pixelRect.width > 0, pixelRect.height > 0 else {
            return nil
        }

        return ViewportAnalysis(pixelRect: pixelRect, normalizedRect: pixelRect.normalized(in: first))
    }

    static func fullFrameFallback(
        first: AnalyzedFrame,
        second: AnalyzedFrame,
        minimumDifference: Double
    ) -> ViewportAnalysis? {
        guard first.width == second.width, first.height == second.height else {
            return nil
        }

        let difference = first.averageSignatureDifference(comparedTo: second)
        guard difference >= minimumDifference else {
            return nil
        }

        let pixelRect = PixelRect(x: 0, y: 0, width: first.width, height: first.height)
        return ViewportAnalysis(pixelRect: pixelRect, normalizedRect: pixelRect.normalized(in: first))
    }

    private static func firstChangedRow(
        first: AnalyzedFrame,
        second: AnalyzedFrame,
        in xRange: Range<Int>,
        threshold: Double
    ) -> Int? {
        for y in 0..<first.height {
            if rowDifference(first: first, second: second, y: y, xRange: xRange) > threshold {
                return y
            }
        }
        return nil
    }

    private static func lastChangedRow(
        first: AnalyzedFrame,
        second: AnalyzedFrame,
        in xRange: Range<Int>,
        threshold: Double
    ) -> Int? {
        for y in stride(from: first.height - 1, through: 0, by: -1) {
            if rowDifference(first: first, second: second, y: y, xRange: xRange) > threshold {
                return y + 1
            }
        }
        return nil
    }

    private static func firstChangedColumn(
        first: AnalyzedFrame,
        second: AnalyzedFrame,
        in yRange: Range<Int>,
        threshold: Double
    ) -> Int? {
        for x in 0..<first.width {
            if columnDifference(first: first, second: second, x: x, yRange: yRange) > threshold {
                return x
            }
        }
        return nil
    }

    private static func lastChangedColumn(
        first: AnalyzedFrame,
        second: AnalyzedFrame,
        in yRange: Range<Int>,
        threshold: Double
    ) -> Int? {
        for x in stride(from: first.width - 1, through: 0, by: -1) {
            if columnDifference(first: first, second: second, x: x, yRange: yRange) > threshold {
                return x + 1
            }
        }
        return nil
    }

    private static func rowDifference(
        first: AnalyzedFrame,
        second: AnalyzedFrame,
        y: Int,
        xRange: Range<Int>
    ) -> Double {
        let step = max(2, (xRange.upperBound - xRange.lowerBound) / 96)
        var total = 0
        var count = 0

        for x in stride(from: xRange.lowerBound, to: xRange.upperBound, by: step) {
            total += abs(Int(first.luminance(x: x, y: y)) - Int(second.luminance(x: x, y: y)))
            count += 1
        }

        guard count > 0 else { return 0 }
        return Double(total) / Double(count * 255)
    }

    private static func columnDifference(
        first: AnalyzedFrame,
        second: AnalyzedFrame,
        x: Int,
        yRange: Range<Int>
    ) -> Double {
        let step = max(2, (yRange.upperBound - yRange.lowerBound) / 96)
        var total = 0
        var count = 0

        for y in stride(from: yRange.lowerBound, to: yRange.upperBound, by: step) {
            total += abs(Int(first.luminance(x: x, y: y)) - Int(second.luminance(x: x, y: y)))
            count += 1
        }

        guard count > 0 else { return 0 }
        return Double(total) / Double(count * 255)
    }
}

private struct AnalyzedFrame {
    private static let signatureWidth = 48

    let cgImage: CGImage
    let bitmap: NSBitmapImageRep
    let width: Int
    let height: Int
    let pixelScale: CGFloat
    let sizeInPoints: CGSize
    let bytesPerRow: Int
    let bytesPerPixel: Int
    let samplesPerPixel: Int
    let bitmapData: UnsafePointer<UInt8>
    let rowSignatures: [UInt8]

    init?(image: NSImage) {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }

        let scale = image.size.width > 0 ? CGFloat(cgImage.width) / image.size.width : 1
        self.init(cgImage: cgImage, sizeInPoints: image.size, pixelScale: scale)
    }

    init?(cgImage: CGImage, sizeInPoints: CGSize, pixelScale: CGFloat) {
        let bitmap = NSBitmapImageRep(cgImage: cgImage)
        guard let bitmapData = bitmap.bitmapData else {
            return nil
        }

        self.cgImage = cgImage
        self.bitmap = bitmap
        self.width = cgImage.width
        self.height = cgImage.height
        self.pixelScale = pixelScale
        self.sizeInPoints = sizeInPoints
        self.bytesPerRow = bitmap.bytesPerRow
        self.bytesPerPixel = max(1, bitmap.bitsPerPixel / 8)
        self.samplesPerPixel = bitmap.samplesPerPixel
        self.bitmapData = UnsafePointer(bitmapData)
        self.rowSignatures = AnalyzedFrame.buildRowSignatures(
            bitmapData: UnsafePointer(bitmapData),
            width: cgImage.width,
            height: cgImage.height,
            bytesPerRow: bitmap.bytesPerRow,
            bytesPerPixel: max(1, bitmap.bitsPerPixel / 8),
            samplesPerPixel: bitmap.samplesPerPixel
        )
    }

    func luminance(x: Int, y: Int) -> UInt8 {
        let offset = y * bytesPerRow + x * bytesPerPixel

        if samplesPerPixel >= 3 {
            let c0 = Int(bitmapData[offset])
            let c1 = Int(bitmapData[offset + 1])
            let c2 = Int(bitmapData[offset + 2])
            return UInt8((c0 + c1 + c2) / 3)
        }

        return bitmapData[offset]
    }

    func cropped(to rect: PixelRect) -> AnalyzedFrame? {
        guard let croppedImage = cgImage.cropping(to: rect.cgRect) else {
            return nil
        }

        let croppedSize = CGSize(
            width: CGFloat(rect.width) / pixelScale,
            height: CGFloat(rect.height) / pixelScale
        )
        return AnalyzedFrame(cgImage: croppedImage, sizeInPoints: croppedSize, pixelScale: pixelScale)
    }

    func signatureRow(at row: Int) -> ArraySlice<UInt8> {
        let start = row * AnalyzedFrame.signatureWidth
        return rowSignatures[start..<(start + AnalyzedFrame.signatureWidth)]
    }

    func averageSignatureDifference(comparedTo other: AnalyzedFrame) -> Double {
        guard width == other.width, height == other.height, rowSignatures.count == other.rowSignatures.count else {
            return 1
        }

        let rowStep = max(1, height / 96)
        var total = 0
        var count = 0

        for row in stride(from: 0, to: height, by: rowStep) {
            let lhs = signatureRow(at: row)
            let rhs = other.signatureRow(at: row)
            for (left, right) in zip(lhs, rhs) {
                total += abs(Int(left) - Int(right))
                count += 1
            }
        }

        guard count > 0 else {
            return 0
        }

        return Double(total) / Double(count * 255)
    }

    private static func buildRowSignatures(
        bitmapData: UnsafePointer<UInt8>,
        width: Int,
        height: Int,
        bytesPerRow: Int,
        bytesPerPixel: Int,
        samplesPerPixel: Int
    ) -> [UInt8] {
        var signatures = [UInt8](repeating: 0, count: height * signatureWidth)
        let maxX = max(0, width - 1)

        for y in 0..<height {
            let rowStart = y * signatureWidth
            for sampleIndex in 0..<signatureWidth {
                let x: Int
                if signatureWidth == 1 {
                    x = maxX / 2
                } else {
                    x = Int(round(Double(sampleIndex) * Double(maxX) / Double(signatureWidth - 1)))
                }

                let offset = y * bytesPerRow + x * bytesPerPixel
                if samplesPerPixel >= 3 {
                    let c0 = Int(bitmapData[offset])
                    let c1 = Int(bitmapData[offset + 1])
                    let c2 = Int(bitmapData[offset + 2])
                    signatures[rowStart + sampleIndex] = UInt8((c0 + c1 + c2) / 3)
                } else {
                    signatures[rowStart + sampleIndex] = bitmapData[offset]
                }
            }
        }

        return signatures
    }
}

private struct VerticalImageStitcher {
    private struct Segment {
        let image: CGImage
        let trimTopPixels: Int
    }

    let viewportRect: PixelRect
    let pixelScale: CGFloat
    let maxOutputHeightPixels: Int
    let minimumProgressPixels: Int

    private var segments: [Segment] = []
    private var previousFrame: AnalyzedFrame?
    private(set) var totalHeightPixels = 0

    init(
        viewportRect: PixelRect,
        pixelScale: CGFloat,
        maxOutputHeightPixels: Int,
        minimumProgressPixels: Int
    ) {
        self.viewportRect = viewportRect
        self.pixelScale = pixelScale
        self.maxOutputHeightPixels = maxOutputHeightPixels
        self.minimumProgressPixels = minimumProgressPixels
    }

    var hasReachedOutputLimit: Bool {
        totalHeightPixels >= maxOutputHeightPixels
    }

    mutating func start(with frame: AnalyzedFrame) -> Bool {
        guard let cropped = frame.cropped(to: viewportRect) else {
            return false
        }

        segments = [Segment(image: cropped.cgImage, trimTopPixels: 0)]
        previousFrame = cropped
        totalHeightPixels = cropped.height
        return true
    }

    mutating func append(_ frame: AnalyzedFrame) -> StitchAppendResult {
        guard let previous = previousFrame,
              let cropped = frame.cropped(to: viewportRect) else {
            return .failed
        }

        let overlap = bestOverlap(previous: previous, next: cropped)
        let appendedPixels = max(0, cropped.height - overlap)
        guard appendedPixels >= minimumProgressPixels else {
            return .noProgress
        }

        let remainingBudget = maxOutputHeightPixels - totalHeightPixels
        guard remainingBudget > 0 else {
            return .noProgress
        }

        let trimmedTop = overlap + max(0, appendedPixels - remainingBudget)
        let actualAppendedPixels = cropped.height - trimmedTop
        guard actualAppendedPixels >= minimumProgressPixels else {
            return .noProgress
        }

        segments.append(Segment(image: cropped.cgImage, trimTopPixels: trimmedTop))
        previousFrame = cropped
        totalHeightPixels += actualAppendedPixels
        return .appended(actualAppendedPixels)
    }

    func render() -> NSImage? {
        guard let firstSegment = segments.first else {
            return nil
        }

        let outputWidth = firstSegment.image.width
        let outputHeight = totalHeightPixels
        guard outputWidth > 0, outputHeight > 0 else {
            return nil
        }

        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: outputWidth,
            pixelsHigh: outputHeight,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            return nil
        }

        bitmap.size = NSSize(width: CGFloat(outputWidth) / pixelScale, height: CGFloat(outputHeight) / pixelScale)

        guard let context = NSGraphicsContext(bitmapImageRep: bitmap)?.cgContext else {
            return nil
        }

        context.translateBy(x: 0, y: CGFloat(outputHeight))
        context.scaleBy(x: 1, y: -1)

        var currentY: CGFloat = 0
        for segment in segments {
            let remainingHeight = segment.image.height - segment.trimTopPixels
            guard remainingHeight > 0 else { continue }

            let sourceRect = CGRect(
                x: 0,
                y: segment.trimTopPixels,
                width: segment.image.width,
                height: remainingHeight
            )
            guard let slice = segment.image.cropping(to: sourceRect) else {
                continue
            }

            context.draw(
                slice,
                in: CGRect(
                    x: 0,
                    y: currentY,
                    width: CGFloat(slice.width),
                    height: CGFloat(slice.height)
                )
            )
            currentY += CGFloat(slice.height)
        }

        let image = NSImage(size: bitmap.size)
        image.addRepresentation(bitmap)
        return image
    }

    private func bestOverlap(previous: AnalyzedFrame, next: AnalyzedFrame) -> Int {
        let maxCandidate = min(previous.height, next.height) - minimumProgressPixels
        let minCandidate = max(40, Int(CGFloat(next.height) * 0.15))
        guard maxCandidate > minCandidate else {
            return 0
        }

        var bestOverlap = 0
        var bestScore = Double.greatestFiniteMagnitude

        for overlap in stride(from: minCandidate, through: maxCandidate, by: 4) {
            let score = overlapScore(previous: previous, next: next, overlap: overlap)
            if score < bestScore {
                bestScore = score
                bestOverlap = overlap
            }
        }

        let refineStart = max(minCandidate, bestOverlap - 3)
        let refineEnd = min(maxCandidate, bestOverlap + 3)
        for overlap in refineStart...refineEnd {
            let score = overlapScore(previous: previous, next: next, overlap: overlap)
            if score < bestScore {
                bestScore = score
                bestOverlap = overlap
            }
        }

        return bestOverlap
    }

    private func overlapScore(previous: AnalyzedFrame, next: AnalyzedFrame, overlap: Int) -> Double {
        let rowStep = max(1, overlap / 48)
        var total = 0
        var count = 0

        for rowOffset in stride(from: 0, to: overlap, by: rowStep) {
            let previousRow = previous.height - overlap + rowOffset
            let nextRow = rowOffset
            let previousSignature = previous.signatureRow(at: previousRow)
            let nextSignature = next.signatureRow(at: nextRow)

            for (lhs, rhs) in zip(previousSignature, nextSignature) {
                total += abs(Int(lhs) - Int(rhs))
                count += 1
            }
        }

        guard count > 0 else { return Double.greatestFiniteMagnitude }
        return Double(total) / Double(count)
    }
}
