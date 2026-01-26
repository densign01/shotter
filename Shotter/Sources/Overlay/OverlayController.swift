import AppKit
import SwiftUI
import UniformTypeIdentifiers

private enum OverlayLayout {
    static let overlayWidth: CGFloat = 280
    static let overlayHeight: CGFloat = 180
    static let actionButtonSize: CGFloat = 28
    static let actionButtonSpacing: CGFloat = 8
    static let actionBarInnerPadding: CGFloat = 6
    static let actionBarOuterPadding: CGFloat = 8
}

class OverlayController {
    private var overlayWindow: OverlayWindow?
    private var dismissTimer: Timer?
    
    func showOverlay(
        image: NSImage,
        savedURL: URL?,
        onCopy: @escaping () -> Void,
        onSave: @escaping () -> Void,
        onAnnotate: @escaping () -> Void
    ) {
        // Dismiss existing overlay
        dismissOverlay()
        
        // Create overlay window
        overlayWindow = OverlayWindow(
            image: image,
            savedURL: savedURL,
            onCopy: { [weak self] in
                onCopy()
                self?.dismissOverlay()
            },
            onSave: onSave,
            onAnnotate: onAnnotate,
            onPauseDismiss: { [weak self] in
                self?.pauseDismissTimer()
            },
            onResumeDismiss: { [weak self] in
                self?.resumeDismissTimer()
            },
            onDragSuccess: { [weak self] in
                self?.dismissOverlay()
            },
            onDismiss: { [weak self] in
                self?.dismissOverlay()
            }
        )
        
        overlayWindow?.show()
        
        // Start auto-dismiss timer
        startDismissTimer()
    }
    
    private func startDismissTimer() {
        dismissTimer?.invalidate()
        let delay = PreferencesManager.shared.overlayAutoDismissDelay

        // Don't create timer if delay is negative (never auto-dismiss)
        guard delay > 0 else {
            return
        }

        dismissTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            self?.dismissOverlay()
        }
    }
    
    func pauseDismissTimer() {
        dismissTimer?.invalidate()
    }
    
    func resumeDismissTimer() {
        startDismissTimer()
    }
    
    func dismissOverlay() {
        dismissTimer?.invalidate()
        dismissTimer = nil
        overlayWindow?.close()
        overlayWindow = nil
    }
    
    private func flashSuccess() {
        // Brief visual feedback that copy succeeded
        overlayWindow?.flashCopySuccess()
    }
}

class OverlayWindow: NSPanel, NSDraggingSource, NSFilePromiseProviderDelegate {
    private var hostingView: NSHostingView<OverlayView>?

    // Drag state
    private var image: NSImage
    private var savedURL: URL?
    private var onPauseDismiss: () -> Void
    private var onResumeDismiss: () -> Void
    private var onDragSuccess: () -> Void
    private var isDragging = false
    private var mouseDownLocation: NSPoint?
    private var currentPromiseFilename: String?

    // Button exclusion zones (top-right action bar, top-left close button)
    private let actionBarRect: NSRect
    private let closeButtonRect: NSRect

    init(
        image: NSImage,
        savedURL: URL?,
        onCopy: @escaping () -> Void,
        onSave: @escaping () -> Void,
        onAnnotate: @escaping () -> Void,
        onPauseDismiss: @escaping () -> Void,
        onResumeDismiss: @escaping () -> Void,
        onDragSuccess: @escaping () -> Void,
        onDismiss: @escaping () -> Void
    ) {
        self.image = image
        self.savedURL = savedURL
        self.onPauseDismiss = onPauseDismiss
        self.onResumeDismiss = onResumeDismiss
        self.onDragSuccess = onDragSuccess

        let overlayWidth = OverlayLayout.overlayWidth
        let overlayHeight = OverlayLayout.overlayHeight

        // Define button exclusion zones (in window coordinates, origin bottom-left)
        // Action bar: top-right corner
        let actionBarWidth: CGFloat = 50
        let actionBarHeight: CGFloat = 120
        self.actionBarRect = NSRect(
            x: overlayWidth - actionBarWidth - OverlayLayout.actionBarOuterPadding,
            y: overlayHeight - actionBarHeight - OverlayLayout.actionBarOuterPadding,
            width: actionBarWidth,
            height: actionBarHeight
        )
        // Close button: top-left corner
        self.closeButtonRect = NSRect(x: 0, y: overlayHeight - 40, width: 40, height: 40)

        // Fixed size container; position above dock using visibleFrame
        guard let screen = NSScreen.main else {
            super.init(
                contentRect: .zero,
                styleMask: [.borderless, .nonactivatingPanel, .hudWindow],
                backing: .buffered,
                defer: false
            )
            return
        }

        let padding: CGFloat = 20

        // visibleFrame excludes dock and menu bar
        let visibleFrame = screen.visibleFrame

        // Check dock orientation from system preferences.
        let dockOrientation = UserDefaults.standard.persistentDomain(forName: "com.apple.dock")?["orientation"] as? String ?? "bottom"
        let dockOnLeft = dockOrientation == "left"
        let dockReserve: CGFloat = 70

        let xOffset = dockOnLeft ? max(visibleFrame.minX + padding, dockReserve) : visibleFrame.minX + padding

        let frame = NSRect(
            x: xOffset,
            y: visibleFrame.minY + padding,
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
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = true
        self.isMovableByWindowBackground = false
        self.hidesOnDeactivate = false
        self.ignoresMouseEvents = false
        self.acceptsMouseMovedEvents = true
        self.contentMinSize = NSSize(width: overlayWidth, height: overlayHeight)
        self.contentMaxSize = NSSize(width: overlayWidth, height: overlayHeight)

        // Create SwiftUI view
        let overlayView = OverlayView(
            image: image,
            onCopy: onCopy,
            onSave: onSave,
            onAnnotate: onAnnotate,
            onPauseDismiss: onPauseDismiss,
            onResumeDismiss: onResumeDismiss,
            onDismiss: onDismiss
        )

        hostingView = NSHostingView(rootView: overlayView)
        hostingView?.wantsLayer = true
        hostingView?.layer?.backgroundColor = NSColor.clear.cgColor
        hostingView?.frame = NSRect(x: 0, y: 0, width: overlayWidth, height: overlayHeight)
        self.contentView = hostingView
    }

    // Allow the panel to become key to receive mouse events properly
    override var canBecomeKey: Bool { true }

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
        onPauseDismiss()

        // Gray out the overlay while dragging
        self.alphaValue = 0.5

        let provider = NSFilePromiseProvider(fileType: UTType.png.identifier, delegate: self)
        currentPromiseFilename = savedURL?.lastPathComponent ?? FileNaming.generateFilename(extension: "png")

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
            onDragSuccess()
        } else {
            onResumeDismiss()
        }
    }

    // MARK: - NSFilePromiseProviderDelegate

    func filePromiseProvider(_ filePromiseProvider: NSFilePromiseProvider, fileNameForType fileType: String) -> String {
        currentPromiseFilename ?? savedURL?.lastPathComponent ?? FileNaming.generateFilename(extension: "png")
    }

    func filePromiseProvider(
        _ filePromiseProvider: NSFilePromiseProvider,
        writePromiseTo url: URL,
        completionHandler: @escaping (Error?) -> Void
    ) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else {
                completionHandler(nil)
                return
            }
            do {
                try self.writePromise(to: url)
                completionHandler(nil)
            } catch {
                completionHandler(error)
            }
        }
    }

    private func writePromise(to destinationURL: URL) throws {
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
            return
        }
        try pngData.write(to: destinationURL, options: .atomic)
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
        // Animate out
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.15
            self.animator().alphaValue = 0
        }, completionHandler: {
            super.close()
        })
    }

    func flashCopySuccess() {
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.1
            self.animator().alphaValue = 0.5
        }, completionHandler: {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.1
                self.animator().alphaValue = 1
            }
        })
    }
}

struct OverlayView: View {
    let image: NSImage
    let onCopy: () -> Void
    let onSave: () -> Void
    let onAnnotate: () -> Void
    let onPauseDismiss: () -> Void
    let onResumeDismiss: () -> Void
    let onDismiss: () -> Void

    @State private var isHovering = false

    var body: some View {
        // Image fills the fixed container (crops if needed), buttons anchor to image edges
        Image(nsImage: image)
            .resizable()
            .aspectRatio(contentMode: .fill)
            .frame(width: OverlayLayout.overlayWidth, height: OverlayLayout.overlayHeight)
            .cornerRadius(10)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.white.opacity(0.2), lineWidth: 1)
            )
            .allowsHitTesting(false)
            .frame(width: OverlayLayout.overlayWidth, height: OverlayLayout.overlayHeight)
            .overlay(alignment: .topTrailing) {
                // Floating action bar (top-right, inside image)
                VStack(spacing: OverlayLayout.actionButtonSpacing) {
                    OverlayActionButton(systemName: "doc.on.doc", action: onCopy)
                        .help("Copy")
                    OverlayActionButton(systemName: "folder", action: onSave)
                        .help("Show in Finder")
                    OverlayActionButton(systemName: "pencil.tip.crop.circle", action: onAnnotate)
                        .help("Annotate")
                }
                .padding(OverlayLayout.actionBarInnerPadding)
                .background(ActiveVisualEffectView(material: .hudWindow))
                .cornerRadius(8)
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
            }
            .shadow(radius: 8)
    }
}

struct OverlayActionButton: View {
    let systemName: String
    let action: () -> Void
    var disabled: Bool = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 13, weight: .medium))
                .frame(width: OverlayLayout.actionButtonSize, height: OverlayLayout.actionButtonSize)
                .foregroundColor(disabled ? .secondary : .primary)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.5 : 1)
        .contentShape(Rectangle())
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
        onCopy: {},
        onSave: {},
        onAnnotate: {},
        onPauseDismiss: {},
        onResumeDismiss: {},
        onDismiss: {}
    )
    .padding(20)
    .background(Color.gray)
}
