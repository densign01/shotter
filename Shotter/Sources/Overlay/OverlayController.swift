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

class OverlayWindow: NSPanel {
    private var hostingView: NSHostingView<OverlayView>?
    
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

        let overlayWidth = OverlayLayout.overlayWidth
        let overlayHeight = OverlayLayout.overlayHeight
        let padding: CGFloat = 20

        // visibleFrame excludes dock and menu bar
        let visibleFrame = screen.visibleFrame

        // Check dock orientation from system preferences.
        // When dock is on left with auto-hide, visibleFrame.minX may be 0,
        // but dock can reappear and cover the overlay. Always reserve space.
        let dockOrientation = UserDefaults.standard.persistentDomain(forName: "com.apple.dock")?["orientation"] as? String ?? "bottom"
        let dockOnLeft = dockOrientation == "left"
        let dockReserve: CGFloat = 70  // Typical dock width

        // When dock is on left, use dockReserve as total offset (no extra padding)
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
        self.contentMinSize = NSSize(width: overlayWidth, height: overlayHeight)
        self.contentMaxSize = NSSize(width: overlayWidth, height: overlayHeight)
        
        // Create SwiftUI view
        let overlayView = OverlayView(
            image: image,
            savedURL: savedURL,
            onCopy: onCopy,
            onSave: onSave,
            onAnnotate: onAnnotate,
            onPauseDismiss: onPauseDismiss,
            onResumeDismiss: onResumeDismiss,
            onDragSuccess: onDragSuccess,
            onDismiss: onDismiss
        )
        
        hostingView = NSHostingView(rootView: overlayView)
        hostingView?.wantsLayer = true
        hostingView?.layer?.backgroundColor = NSColor.clear.cgColor
        hostingView?.frame = NSRect(x: 0, y: 0, width: overlayWidth, height: overlayHeight)
        self.contentView = hostingView
    }
    
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
        // Flash the window briefly to indicate success
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
    let savedURL: URL?
    let onCopy: () -> Void
    let onSave: () -> Void
    let onAnnotate: () -> Void
    let onPauseDismiss: () -> Void
    let onResumeDismiss: () -> Void
    let onDragSuccess: () -> Void
    let onDismiss: () -> Void

    @State private var isHovering = false
    @State private var isDragging = false

    var body: some View {
        // Image fills the fixed container (crops if needed), buttons anchor to image edges
        ZStack {
            OverlayDragSourceView(
                image: image,
                savedURL: savedURL,
                onDragStart: {
                    isDragging = true
                    onPauseDismiss()
                },
                onDragCancel: {
                    isDragging = false
                    if !isHovering {
                        onResumeDismiss()
                    }
                },
                onDropComplete: { success in
                    isDragging = false
                    if success {
                        onDragSuccess()
                    } else if !isHovering {
                        onResumeDismiss()
                    }
                }
            )
            .frame(width: OverlayLayout.overlayWidth, height: OverlayLayout.overlayHeight)

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
        }
        .frame(width: OverlayLayout.overlayWidth, height: OverlayLayout.overlayHeight)
        .overlay(alignment: .topTrailing) {
            // Floating action bar (top-right, inside image)
            VStack(spacing: OverlayLayout.actionButtonSpacing) {
                OverlayActionButton(systemName: "doc.on.doc", action: onCopy)
                    .help("Copy")
                OverlayActionButton(systemName: "folder", action: onSave, disabled: savedURL == nil)
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
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) { isHovering = hovering }
            if hovering {
                onPauseDismiss()
            } else if !isDragging {
                onResumeDismiss()
            }
        }
    }
}

private struct OverlayDragSourceView: NSViewRepresentable {
    let image: NSImage
    let savedURL: URL?
    let onDragStart: () -> Void
    let onDragCancel: () -> Void
    let onDropComplete: (Bool) -> Void

    func makeNSView(context: Context) -> OverlayDragSourceNSView {
        OverlayDragSourceNSView(
            image: image,
            savedURL: savedURL,
            onDragStart: onDragStart,
            onDragCancel: onDragCancel,
            onDropComplete: onDropComplete
        )
    }

    func updateNSView(_ nsView: OverlayDragSourceNSView, context: Context) {
        nsView.image = image
        nsView.savedURL = savedURL
        nsView.onDragStart = onDragStart
        nsView.onDragCancel = onDragCancel
        nsView.onDropComplete = onDropComplete
    }
}

private final class OverlayDragSourceNSView: NSView, NSDraggingSource, NSFilePromiseProviderDelegate {
    var image: NSImage
    var savedURL: URL?
    var onDragStart: (() -> Void)?
    var onDragCancel: (() -> Void)?
    var onDropComplete: ((Bool) -> Void)?

    private var isDraggingSession = false

    init(
        image: NSImage,
        savedURL: URL?,
        onDragStart: @escaping () -> Void,
        onDragCancel: @escaping () -> Void,
        onDropComplete: @escaping (Bool) -> Void
    ) {
        self.image = image
        self.savedURL = savedURL
        self.onDragStart = onDragStart
        self.onDragCancel = onDragCancel
        self.onDropComplete = onDropComplete
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) {
        return nil
    }

    override func mouseDown(with event: NSEvent) {
        isDraggingSession = false
        super.mouseDown(with: event)
    }

    override func mouseDragged(with event: NSEvent) {
        guard !isDraggingSession else { return }
        isDraggingSession = true
        beginFileDrag(with: event)
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        .copy
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        if operation == [] {
            onDragCancel?()
        }
        isDraggingSession = false
    }

    func filePromiseProvider(_ filePromiseProvider: NSFilePromiseProvider, fileNameForType fileType: String) -> String {
        savedURL?.lastPathComponent ?? FileNaming.generateFilename(extension: "png")
    }

    func filePromiseProvider(
        _ filePromiseProvider: NSFilePromiseProvider,
        writePromiseTo url: URL,
        completionHandler: @escaping (Error?) -> Void
    ) {
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let filename = filePromiseProvider.suggestedName
                    ?? self.savedURL?.lastPathComponent
                    ?? FileNaming.generateFilename(extension: "png")
                let destinationURL = url.appendingPathComponent(filename)
                try self.writePromise(to: destinationURL)
                completionHandler(nil)
                DispatchQueue.main.async {
                    self.onDropComplete?(true)
                }
            } catch {
                completionHandler(error)
                DispatchQueue.main.async {
                    self.onDropComplete?(false)
                }
            }
        }
    }

    private func beginFileDrag(with event: NSEvent) {
        onDragStart?()

        let provider = NSFilePromiseProvider(fileType: UTType.png.identifier, delegate: self)
        provider.suggestedName = savedURL?.lastPathComponent ?? FileNaming.generateFilename(extension: "png")

        let draggingItem = NSDraggingItem(pasteboardWriter: provider)
        draggingItem.setDraggingFrame(bounds, contents: image)
        beginDraggingSession(with: [draggingItem], event: event, source: self)
    }

    private enum DragWriteError: Error {
        case imageConversionFailed
    }

    private func writePromise(to destinationURL: URL) throws {
        let fileManager = FileManager.default

        if let savedURL = savedURL, fileManager.fileExists(atPath: savedURL.path) {
            do {
                try replaceItem(at: destinationURL, withItemAt: savedURL)
                return
            } catch {
                // Fall through to image conversion if copy fails.
            }
        }

        let tempURL = fileManager.temporaryDirectory.appendingPathComponent(
            FileNaming.generateFilename(extension: "png")
        )
        defer { try? fileManager.removeItem(at: tempURL) }

        try writeImage(to: tempURL)
        try replaceItem(at: destinationURL, withItemAt: tempURL)
    }

    private func replaceItem(at destinationURL: URL, withItemAt sourceURL: URL) throws {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }
        try fileManager.copyItem(at: sourceURL, to: destinationURL)
    }

    private func writeImage(to url: URL) throws {
        guard let pngData = pngData(from: image) else {
            throw DragWriteError.imageConversionFailed
        }
        try pngData.write(to: url, options: .atomic)
    }

    private func pngData(from image: NSImage) -> Data? {
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData) else {
            return nil
        }
        return bitmap.representation(using: .png, properties: [:])
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
        savedURL: URL(fileURLWithPath: "/tmp/test.png"),
        onCopy: {},
        onSave: {},
        onAnnotate: {},
        onPauseDismiss: {},
        onResumeDismiss: {},
        onDragSuccess: {},
        onDismiss: {}
    )
    .padding(20)
    .background(Color.gray)
}
