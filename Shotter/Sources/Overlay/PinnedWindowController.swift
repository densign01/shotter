import AppKit
import SwiftUI

/// Manages floating "pinned" screenshot windows that stay on top of every
/// other app, so a capture can be kept on screen as a reference while working.
final class PinnedWindowController {
    private var windows: [PinnedWindow] = []

    /// Pins `image` as a new always-on-top floating window near `screen`.
    @discardableResult
    func pin(image: NSImage, near screen: NSScreen?) -> PinnedWindow {
        let window = PinnedWindow(
            image: image,
            preferredScreen: screen,
            cascadeIndex: windows.count
        )
        window.onClosed = { [weak self, weak window] in
            guard let self, let window else { return }
            self.windows.removeAll { $0 === window }
        }
        windows.append(window)
        window.show()
        DebugLogger.log("Pinned screenshot (\(windows.count) pinned)")
        return window
    }

    /// Closes every pinned window (used on quit / cleanup).
    func closeAll() {
        windows.forEach { $0.close() }
        windows.removeAll()
    }
}

// MARK: - Pinned Window

final class PinnedWindow: NSPanel {
    private let image: NSImage
    private var hostingView: NSHostingView<PinnedView>?
    private var isClosing = false

    /// Called once when the window has finished closing, so the controller
    /// can drop its reference.
    var onClosed: (() -> Void)?

    /// Longest on-screen side of a freshly pinned window, in points. Images
    /// smaller than this are never upscaled.
    private static let maxPinnedSide: CGFloat = 480

    init(image: NSImage, preferredScreen: NSScreen?, cascadeIndex: Int) {
        self.image = image

        let screen = preferredScreen ?? NSScreen.main
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)

        // Scale so the longest side fits a comfortable pinned size (never upscale).
        let longest = max(image.size.width, image.size.height, 1)
        let scale = min(1, Self.maxPinnedSide / longest)
        let width = max(image.size.width * scale, 80)
        let height = max(image.size.height * scale, 60)

        // Cascade so several pins don't land exactly on top of each other.
        let step = CGFloat(cascadeIndex % 8) * 28
        let origin = NSPoint(
            x: visible.midX - width / 2 + step,
            y: visible.midY - height / 2 - step
        )

        super.init(
            contentRect: NSRect(origin: origin, size: CGSize(width: width, height: height)),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        self.isFloatingPanel = true
        self.level = .floating
        // Stay visible across spaces and full-screen apps.
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = true
        self.isMovableByWindowBackground = true
        self.hidesOnDeactivate = false

        let view = PinnedView(
            image: image,
            size: CGSize(width: width, height: height),
            onCopy: { [weak self] in self?.copyToClipboard() },
            onClose: { [weak self] in self?.close() }
        )
        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(x: 0, y: 0, width: width, height: height)
        self.hostingView = hosting
        self.contentView = hosting
    }

    override var canBecomeKey: Bool { true }

    func show() {
        orderFrontRegardless()
        alphaValue = 0
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            animator().alphaValue = 1
        }
    }

    /// Escape unpins the window when it has key status.
    override func cancelOperation(_ sender: Any?) {
        close()
    }

    override func close() {
        // Guard against re-entrancy (Escape + close button, or double close).
        guard !isClosing else { return }
        isClosing = true
        onClosed?()
        onClosed = nil

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.12
            animator().alphaValue = 0
        }, completionHandler: {
            super.close()
        })
    }

    private func copyToClipboard() {
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:]) else {
            DebugLogger.log("Pinned copy failed: could not convert image")
            return
        }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.declareTypes([.png, .tiff], owner: nil)
        pasteboard.setData(pngData, forType: .png)
        pasteboard.setData(tiffData, forType: .tiff)

        // Brief flash to confirm the copy.
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.1
            animator().alphaValue = 0.6
        }, completionHandler: { [weak self] in
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.1
                self?.animator().alphaValue = 1
            }
        })
    }
}

// MARK: - Pinned View

struct PinnedView: View {
    let image: NSImage
    let size: CGSize
    let onCopy: () -> Void
    let onClose: () -> Void

    @State private var isHovering = false

    var body: some View {
        Image(nsImage: image)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: size.width, height: size.height)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.white.opacity(0.18), lineWidth: 1)
            )
            .overlay(alignment: .topLeading) {
                if isHovering {
                    Button(action: onClose) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 17))
                            .foregroundStyle(.white.opacity(0.9))
                            .background(Circle().fill(Color.black.opacity(0.55)))
                    }
                    .buttonStyle(.plain)
                    .padding(8)
                    .help("Unpin")
                    .accessibilityLabel(Text("Unpin"))
                }
            }
            .overlay(alignment: .topTrailing) {
                if isHovering {
                    Button(action: onCopy) {
                        Image(systemName: "doc.on.doc.fill")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.white.opacity(0.9))
                            .frame(width: 26, height: 26)
                            .background(Circle().fill(Color.black.opacity(0.55)))
                    }
                    .buttonStyle(.plain)
                    .padding(8)
                    .help("Copy")
                    .accessibilityLabel(Text("Copy"))
                }
            }
            .shadow(radius: 10)
            .onHover { isHovering = $0 }
    }
}
