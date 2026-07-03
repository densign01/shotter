import AppKit
import SwiftUI
import UniformTypeIdentifiers

private enum OverlayLayout {
    static let overlayWidth: CGFloat = 280
    static let minOverlayHeight: CGFloat = 150
    static let maxOverlayHeight: CGFloat = 280
    static let actionButtonSize: CGFloat = 28
    static let actionButtonSpacing: CGFloat = 8
    static let actionBarInnerPadding: CGFloat = 6
    static let actionBarOuterPadding: CGFloat = 8
    static let stackSpacing: CGFloat = 12
    static let screenPadding: CGFloat = 20
}

private enum DragExportError: LocalizedError {
    case imageConversionFailed

    var errorDescription: String? {
        switch self {
        case .imageConversionFailed:
            return "Could not convert the screenshot to PNG for dragging."
        }
    }
}

class OverlayController {
    private var overlayWindows: [OverlayWindow] = []
    private let maxStackedOverlays = 5

    /// Shows a post-capture overlay. New captures stack above existing overlays
    /// instead of replacing them. Returns a closure that dismisses this
    /// specific overlay (used e.g. after a successful manual save).
    @discardableResult
    func showOverlay(
        image: NSImage,
        savedURL: URL?,
        preferredScreen: NSScreen?,
        onCopy: @escaping () -> Void,
        onSave: @escaping () -> Void,
        onAnnotate: @escaping () -> Void,
        onDelete: @escaping () -> Void
    ) -> () -> Void {
        // Cap the stack; drop the oldest overlay when full
        if overlayWindows.count >= maxStackedOverlays, let oldest = overlayWindows.first {
            dismiss(oldest)
        }

        let window = OverlayWindow(
            image: image,
            savedURL: savedURL,
            preferredScreen: preferredScreen,
            onCopy: onCopy,
            onSave: onSave,
            onAnnotate: onAnnotate,
            onDelete: onDelete
        )
        window.onRequestDismiss = { [weak self, weak window] in
            guard let self, let window else { return }
            self.dismiss(window)
        }

        overlayWindows.append(window)
        restack(animated: false)
        window.show()
        window.startAutoDismissTimer()

        return { [weak self, weak window] in
            guard let self, let window else { return }
            self.dismiss(window)
        }
    }

    /// Dismiss one overlay and slide the remaining stack back into place.
    func dismiss(_ window: OverlayWindow) {
        if let index = overlayWindows.firstIndex(where: { $0 === window }) {
            overlayWindows.remove(at: index)
        }
        window.close()
        restack(animated: true)
    }

    /// Dismiss every overlay (kept for callers that need a full reset).
    func dismissOverlay() {
        let windows = overlayWindows
        overlayWindows.removeAll()
        for window in windows {
            window.close()
        }
    }

    /// Lay out overlays bottom-up per screen: the newest capture sits at the
    /// base position, older ones are pushed upward.
    private func restack(animated: Bool) {
        var nextYByScreen: [String: CGFloat] = [:]

        for window in overlayWindows.reversed() {
            guard let screen = window.anchorScreen ?? NSScreen.main else { continue }
            let key = "\(screen.frame.origin)"
            let baseY = screen.visibleFrame.minY + OverlayLayout.screenPadding
            let y = nextYByScreen[key] ?? baseY

            var frame = window.frame
            frame.origin.y = y
            if animated {
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.2
                    window.animator().setFrame(frame, display: true)
                }
            } else {
                window.setFrame(frame, display: true)
            }

            nextYByScreen[key] = y + frame.height + OverlayLayout.stackSpacing
        }
    }
}

/// Owns the promised screenshot data for a drag session, independent of the
/// overlay window's lifetime — so slow drop targets (Mail, network folders)
/// still receive the file after the overlay is dismissed and deallocated.
final class ScreenshotDragSource: NSObject, NSFilePromiseProviderDelegate {
    private static var activeSources: [ObjectIdentifier: ScreenshotDragSource] = [:]

    private let image: NSImage
    private let savedURL: URL?
    private let filename: String

    init(image: NSImage, savedURL: URL?, filename: String) {
        self.image = image
        self.savedURL = savedURL
        self.filename = filename
    }

    func retainUntilFulfilled() {
        Self.activeSources[ObjectIdentifier(self)] = self
    }

    func release() {
        Self.activeSources[ObjectIdentifier(self)] = nil
    }

    // MARK: - NSFilePromiseProviderDelegate

    func filePromiseProvider(_ filePromiseProvider: NSFilePromiseProvider, fileNameForType fileType: String) -> String {
        filename
    }

    func filePromiseProvider(
        _ filePromiseProvider: NSFilePromiseProvider,
        writePromiseTo url: URL,
        completionHandler: @escaping (Error?) -> Void
    ) {
        DispatchQueue.global(qos: .userInitiated).async {
            defer {
                DispatchQueue.main.async { self.release() }
            }
            do {
                try self.write(to: url)
                completionHandler(nil)
            } catch {
                completionHandler(error)
            }
        }
    }

    private func write(to destinationURL: URL) throws {
        let fileManager = FileManager.default

        if let savedURL = savedURL, fileManager.fileExists(atPath: savedURL.path) {
            if fileManager.fileExists(atPath: destinationURL.path) {
                try fileManager.removeItem(at: destinationURL)
            }
            try fileManager.copyItem(at: savedURL, to: destinationURL)
            return
        }

        // Fall back to converting image to PNG
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:]) else {
            throw DragExportError.imageConversionFailed
        }
        try pngData.write(to: destinationURL, options: .atomic)
    }
}

class OverlayWindow: NSPanel, NSDraggingSource {
    private var hostingView: NSHostingView<OverlayView>?

    /// Screen this overlay is anchored to, used for stack layout.
    let anchorScreen: NSScreen?

    var onRequestDismiss: (() -> Void)?

    // Drag state
    private var image: NSImage
    private var savedURL: URL?
    private var isDragging = false
    private var mouseDownLocation: NSPoint?
    private var currentDragSource: ScreenshotDragSource?

    // Auto-dismiss timer, scoped to this window so overlapping overlays
    // never interfere with each other's timing.
    private var dismissTimer: Timer?

    // Button exclusion zones (top-right action bar, top-left close button)
    private let actionBarRect: NSRect
    private let closeButtonRect: NSRect

    /// Window height derived from the capture's aspect ratio, so the
    /// thumbnail shows the whole capture instead of a center crop.
    static func overlayHeight(for image: NSImage) -> CGFloat {
        guard image.size.width > 0, image.size.height > 0 else {
            return OverlayLayout.minOverlayHeight
        }
        let aspect = image.size.width / image.size.height
        let height = OverlayLayout.overlayWidth / aspect
        return min(max(height, OverlayLayout.minOverlayHeight), OverlayLayout.maxOverlayHeight)
    }

    init(
        image: NSImage,
        savedURL: URL?,
        preferredScreen: NSScreen?,
        onCopy: @escaping () -> Void,
        onSave: @escaping () -> Void,
        onAnnotate: @escaping () -> Void,
        onDelete: @escaping () -> Void
    ) {
        self.image = image
        self.savedURL = savedURL
        self.anchorScreen = preferredScreen ?? NSScreen.main

        let overlayWidth = OverlayLayout.overlayWidth
        let overlayHeight = Self.overlayHeight(for: image)

        // Define button exclusion zones (in window coordinates, origin bottom-left)
        // Action bar: top-right corner (4 buttons)
        let actionBarWidth: CGFloat = 50
        let actionBarHeight: CGFloat = 156
        self.actionBarRect = NSRect(
            x: overlayWidth - actionBarWidth - OverlayLayout.actionBarOuterPadding,
            y: overlayHeight - actionBarHeight - OverlayLayout.actionBarOuterPadding,
            width: actionBarWidth,
            height: actionBarHeight
        )
        // Close button: top-left corner
        self.closeButtonRect = NSRect(x: 0, y: overlayHeight - 40, width: 40, height: 40)

        guard let screen = preferredScreen ?? NSScreen.main else {
            super.init(
                contentRect: .zero,
                styleMask: [.borderless, .nonactivatingPanel, .hudWindow],
                backing: .buffered,
                defer: false
            )
            return
        }

        // visibleFrame excludes dock and menu bar
        let visibleFrame = screen.visibleFrame

        // Calculate x position based on preference
        let position = PreferencesManager.shared.overlayPosition
        let xOffset: CGFloat

        if position == .bottomRight {
            xOffset = visibleFrame.maxX - overlayWidth - OverlayLayout.screenPadding
        } else {
            xOffset = visibleFrame.minX + OverlayLayout.screenPadding
        }

        let frame = NSRect(
            x: xOffset,
            y: visibleFrame.minY + OverlayLayout.screenPadding,
            width: overlayWidth,
            height: overlayHeight
        )

        super.init(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel, .hudWindow],
            backing: .buffered,
            defer: false
        )

        // Configure panel
        self.isFloatingPanel = true
        self.level = .floating
        // Follow the active space — including full-screen apps — so the
        // overlay is visible wherever the capture was taken.
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = false
        self.isMovableByWindowBackground = false
        self.hidesOnDeactivate = false
        self.ignoresMouseEvents = false
        self.acceptsMouseMovedEvents = true
        self.contentMinSize = NSSize(width: overlayWidth, height: overlayHeight)
        self.contentMaxSize = NSSize(width: overlayWidth, height: overlayHeight)

        // Create SwiftUI view; action closures route through this window so
        // each overlay dismisses itself independently.
        let overlayView = OverlayView(
            image: image,
            size: CGSize(width: overlayWidth, height: overlayHeight),
            hasSavedFile: savedURL != nil,
            onCopy: { [weak self] in
                onCopy()
                self?.flashCopySuccessAndDismiss()
            },
            onSave: onSave,
            onAnnotate: { [weak self] in
                onAnnotate()
                self?.requestDismiss()
            },
            onDelete: { [weak self] in
                onDelete()
                self?.requestDismiss()
            },
            onPauseDismiss: { [weak self] in
                self?.pauseAutoDismiss()
            },
            onResumeDismiss: { [weak self] in
                self?.resumeAutoDismiss()
            },
            onDismiss: { [weak self] in
                self?.requestDismiss()
            }
        )

        hostingView = NSHostingView(rootView: overlayView)
        hostingView?.wantsLayer = true
        hostingView?.layer?.backgroundColor = NSColor.clear.cgColor
        hostingView?.layer?.cornerRadius = 10
        hostingView?.layer?.masksToBounds = true
        hostingView?.frame = NSRect(x: 0, y: 0, width: overlayWidth, height: overlayHeight)
        self.contentView = hostingView
    }

    // Allow the panel to become key to receive mouse events properly
    override var canBecomeKey: Bool { true }

    // MARK: - Auto-dismiss timer

    func startAutoDismissTimer() {
        dismissTimer?.invalidate()
        let delay = PreferencesManager.shared.overlayAutoDismissDelay

        // Don't create timer if delay is negative (never auto-dismiss)
        guard delay > 0 else { return }

        dismissTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            self?.requestDismiss()
        }
    }

    func pauseAutoDismiss() {
        dismissTimer?.invalidate()
        dismissTimer = nil
    }

    func resumeAutoDismiss() {
        startAutoDismissTimer()
    }

    private func requestDismiss() {
        onRequestDismiss?()
    }

    /// Escape dismisses the overlay (when it has key status, e.g. after a click).
    override func cancelOperation(_ sender: Any?) {
        requestDismiss()
    }

    // MARK: - Mouse handling for drag

    override func sendEvent(_ event: NSEvent) {
        switch event.type {
        case .leftMouseDown:
            let locationInWindow = event.locationInWindow

            // If click is in button areas, let SwiftUI handle it
            if actionBarRect.contains(locationInWindow) || closeButtonRect.contains(locationInWindow) {
                super.sendEvent(event)
                return
            }

            // Otherwise, track for potential drag
            mouseDownLocation = locationInWindow
            isDragging = false

        case .leftMouseDragged:
            guard let startLocation = mouseDownLocation else {
                super.sendEvent(event)
                return
            }

            // Check if we've dragged enough to start
            let currentLocation = event.locationInWindow
            let dx = currentLocation.x - startLocation.x
            let dy = currentLocation.y - startLocation.y
            let distance = sqrt(dx * dx + dy * dy)

            if !isDragging && distance > 3 {
                isDragging = true
                beginFileDrag(with: event)
            }
            return // Don't pass drag events to SwiftUI

        case .leftMouseUp:
            mouseDownLocation = nil
            if isDragging {
                isDragging = false
                return
            }

        default:
            break
        }

        super.sendEvent(event)
    }

    private func beginFileDrag(with event: NSEvent) {
        pauseAutoDismiss()

        // Gray out the overlay while dragging
        self.alphaValue = 0.5

        // The drag source outlives this window so slow drop targets still
        // get their file after the overlay is dismissed.
        let source = ScreenshotDragSource(
            image: image,
            savedURL: savedURL,
            filename: savedURL?.lastPathComponent ?? FileNaming.generateFilename(extension: "png")
        )
        source.retainUntilFulfilled()
        currentDragSource = source

        let provider = NSFilePromiseProvider(fileType: UTType.png.identifier, delegate: source)
        let draggingItem = NSDraggingItem(pasteboardWriter: provider)

        // Create a smaller drag image (like CleanShot)
        let dragImageSize = NSSize(width: 120, height: 80)
        let dragImage = NSImage(size: dragImageSize)
        dragImage.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: dragImageSize),
                   from: NSRect(origin: .zero, size: image.size),
                   operation: .copy, fraction: 0.9)
        dragImage.unlockFocus()

        // Position drag image centered on mouse
        let mouseLocation = event.locationInWindow
        let dragFrame = NSRect(
            x: mouseLocation.x - dragImageSize.width / 2,
            y: mouseLocation.y - dragImageSize.height / 2,
            width: dragImageSize.width,
            height: dragImageSize.height
        )
        draggingItem.setDraggingFrame(dragFrame, contents: dragImage)

        contentView?.beginDraggingSession(with: [draggingItem], event: event, source: self)
    }

    // MARK: - NSDraggingSource

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        .copy
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        // Restore opacity
        self.alphaValue = 1.0

        if operation != [] {
            // Dropped: the retained drag source fulfills the promise even
            // after this window is gone.
            currentDragSource = nil
            requestDismiss()
        } else {
            // No drop happened - nothing will ask for the file
            currentDragSource?.release()
            currentDragSource = nil
            resumeAutoDismiss()
        }
    }

    // MARK: - Window lifecycle

    func show() {
        self.orderFrontRegardless()

        // Animate in
        self.alphaValue = 0
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            self.animator().alphaValue = 1
        }
    }

    override func close() {
        dismissTimer?.invalidate()
        dismissTimer = nil

        // Animate out
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.15
            self.animator().alphaValue = 0
        }, completionHandler: {
            super.close()
        })
    }

    /// Brief visual confirmation that the copy happened, then dismiss.
    private func flashCopySuccessAndDismiss() {
        pauseAutoDismiss()
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.1
            self.animator().alphaValue = 0.5
        }, completionHandler: {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.1
                self.animator().alphaValue = 1
            }
        })
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            self?.requestDismiss()
        }
    }
}

struct OverlayView: View {
    let image: NSImage
    let size: CGSize
    let hasSavedFile: Bool
    let onCopy: () -> Void
    let onSave: () -> Void
    let onAnnotate: () -> Void
    let onDelete: () -> Void
    let onPauseDismiss: () -> Void
    let onResumeDismiss: () -> Void
    let onDismiss: () -> Void

    @State private var isHovering = false

    var body: some View {
        // Material card with the capture letterboxed inside, so the whole
        // capture is always visible regardless of aspect ratio
        ZStack {
            ActiveVisualEffectView(material: .hudWindow)
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: size.width, height: size.height)
                .allowsHitTesting(false)
        }
        .frame(width: size.width, height: size.height)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.white.opacity(0.2), lineWidth: 1)
        )
        .overlay(alignment: .topTrailing) {
            // Floating action bar (top-right, inside image)
            VStack(spacing: OverlayLayout.actionButtonSpacing) {
                OverlayActionButton(systemName: "doc.on.doc", action: onCopy)
                    .help("Copy")
                    .accessibilityLabel(Text("Copy"))
                // Show "Save" when no file exists, "Show in Finder" when file exists
                OverlayActionButton(
                    systemName: hasSavedFile ? "folder" : "square.and.arrow.down",
                    action: onSave
                )
                .help(hasSavedFile ? "Show in Finder" : "Save")
                .accessibilityLabel(Text(hasSavedFile ? "Show in Finder" : "Save"))
                OverlayActionButton(systemName: "pencil.tip.crop.circle", action: onAnnotate)
                    .help("Annotate")
                    .accessibilityLabel(Text("Annotate"))
                // Show "Discard" when no file exists, "Move to Trash" when file exists
                OverlayDeleteButton(action: onDelete)
                    .help(hasSavedFile ? "Move to Trash" : "Discard")
                    .accessibilityLabel(Text(hasSavedFile ? "Move to Trash" : "Discard"))
            }
            .padding(OverlayLayout.actionBarInnerPadding)
            .background(ActiveVisualEffectView(material: .hudWindow))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .padding(OverlayLayout.actionBarOuterPadding)
            .opacity(isHovering ? 1 : 0.7)
        }
        .overlay(alignment: .topLeading) {
            // Close button (top-left corner, inside image)
            Button(action: onDismiss) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(.white.opacity(0.8))
                    .background(Circle().fill(Color.black.opacity(0.5)))
            }
            .buttonStyle(.plain)
            .padding(10)
            .opacity(isHovering ? 1 : 0.6)
            .accessibilityLabel(Text("Dismiss"))
        }
        .shadow(radius: 8)
        .onHover { hovering in
            isHovering = hovering
            if hovering {
                onPauseDismiss()
            } else {
                onResumeDismiss()
            }
        }
    }
}

struct OverlayActionButton: View {
    let systemName: String
    let action: () -> Void
    var disabled: Bool = false
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 13, weight: .medium))
                .frame(width: OverlayLayout.actionButtonSize, height: OverlayLayout.actionButtonSize)
                .foregroundColor(disabled ? .secondary : (isHovering ? .primary : .secondary))
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.5 : 1)
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovering = hovering
        }
    }
}

struct OverlayDeleteButton: View {
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "trash")
                .font(.system(size: 13, weight: .medium))
                .frame(width: OverlayLayout.actionButtonSize, height: OverlayLayout.actionButtonSize)
                .foregroundColor(isHovering ? .red : .primary)
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovering = hovering
        }
    }
}

struct ActiveVisualEffectView: NSViewRepresentable {
    var material: NSVisualEffectView.Material
    var blendingMode: NSVisualEffectView.BlendingMode = .withinWindow

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
        nsView.state = .active
    }
}

#Preview {
    OverlayView(
        image: NSImage(systemSymbolName: "photo", accessibilityDescription: nil)!,
        size: CGSize(width: 280, height: 180),
        hasSavedFile: true,
        onCopy: {},
        onSave: {},
        onAnnotate: {},
        onDelete: {},
        onPauseDismiss: {},
        onResumeDismiss: {},
        onDismiss: {}
    )
    .padding(20)
    .background(Color.gray)
}
