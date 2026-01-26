import AppKit
import SwiftUI

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
        onDismiss: @escaping () -> Void
    ) {
        // Calculate position (bottom-left with padding)
        guard NSScreen.main != nil else {
            super.init(
                contentRect: .zero,
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            return
        }
        
        let overlayWidth: CGFloat = 300
        let overlayHeight: CGFloat = 100
        let padding: CGFloat = 20
        
        let frame = NSRect(
            x: padding,
            y: padding,
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
        self.isMovableByWindowBackground = true
        self.hidesOnDeactivate = false
        
        // Create SwiftUI view
        let overlayView = OverlayView(
            image: image,
            savedURL: savedURL,
            onCopy: onCopy,
            onSave: onSave,
            onAnnotate: onAnnotate,
            onDismiss: onDismiss
        )
        
        hostingView = NSHostingView(rootView: overlayView)
        hostingView?.frame = NSRect(x: 0, y: 0, width: overlayWidth, height: overlayHeight)
        // Prevent SwiftUI from collapsing the view below minimum size
        hostingView?.setContentHuggingPriority(.defaultLow, for: .horizontal)
        hostingView?.setContentHuggingPriority(.defaultLow, for: .vertical)
        self.contentView = hostingView
        
        // Enable dragging the image out
        self.registerForDraggedTypes([.fileURL, .png, .tiff])
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
    let onDismiss: () -> Void

    @State private var isHovering = false
    
    var body: some View {
        HStack(spacing: 12) {
            // Thumbnail - fixed frame ensures consistent sizing regardless of image dimensions
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(minWidth: 80, maxWidth: 80, minHeight: 60, maxHeight: 60, alignment: .center)
                .clipped()
                .cornerRadius(6)
                .shadow(radius: 2)
                .onDrag {
                    // Enable drag and drop
                    let provider = NSItemProvider(object: image)
                    return provider
                }
            
            // Action buttons
            VStack(alignment: .leading, spacing: 6) {
                Button(action: onCopy) {
                    Label("Copy", systemImage: "doc.on.doc")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(OverlayButtonStyle())
                
                Button(action: onSave) {
                    Label("Show in Finder", systemImage: "folder")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(OverlayButtonStyle(disabled: savedURL == nil))
                .disabled(savedURL == nil)
                
                Button(action: onAnnotate) {
                    Label("Annotate", systemImage: "pencil.tip.crop.circle")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(OverlayButtonStyle())
            }
            .frame(width: 130)
            
            // Close button
            Button(action: onDismiss) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .opacity(isHovering ? 1 : 0.5)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.2), lineWidth: 1)
        )
        .frame(minWidth: 300, minHeight: 100) // Enforce minimum size to prevent controls from being cut off
        .onHover { hovering in
            isHovering = hovering
        }
    }
}

struct OverlayButtonStyle: ButtonStyle {
    var disabled: Bool = false
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .medium))
            .foregroundColor(disabled ? .secondary : .primary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(configuration.isPressed ? Color.white.opacity(0.2) : Color.white.opacity(0.1))
            )
            .opacity(disabled ? 0.6 : 1)
    }
}

#Preview {
    OverlayView(
        image: NSImage(systemSymbolName: "photo", accessibilityDescription: nil)!,
        savedURL: URL(fileURLWithPath: "/tmp/test.png"),
        onCopy: {},
        onSave: {},
        onAnnotate: {},
        onDismiss: {}
    )
    .frame(width: 300, height: 100)
    .background(Color.gray)
}
