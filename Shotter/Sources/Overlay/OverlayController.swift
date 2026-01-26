import AppKit
import SwiftUI

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

        let frame = NSRect(
            x: visibleFrame.minX + padding,
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
        self.isMovableByWindowBackground = true
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
            }
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
        onDismiss: {}
    )
    .padding(20)
    .background(Color.gray)
}
