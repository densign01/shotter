import AppKit
import SwiftUI

/// The main annotation editor window
class AnnotationEditorWindow: NSWindow {
    private var state: AnnotationEditorState
    private var canvasView: AnnotationCanvasView?
    private var onSave: ((NSImage) -> Void)?
    private var onCancel: (() -> Void)?
    private var savedURL: URL?
    
    init(
        image: NSImage,
        savedURL: URL?,
        onSave: @escaping (NSImage) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.state = AnnotationEditorState(image: image)
        self.onSave = onSave
        self.onCancel = onCancel
        self.savedURL = savedURL
        
        // Calculate window size based on image
        let screenFrame = NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1200, height: 800)
        let maxWidth = screenFrame.width * 0.85
        let maxHeight = screenFrame.height * 0.85
        
        let imageAspect = image.size.width / image.size.height
        var windowWidth: CGFloat
        var windowHeight: CGFloat
        
        if image.size.width > maxWidth || image.size.height > maxHeight {
            // Scale down to fit
            if imageAspect > maxWidth / maxHeight {
                windowWidth = maxWidth
                windowHeight = maxWidth / imageAspect
            } else {
                windowHeight = maxHeight
                windowWidth = maxHeight * imageAspect
            }
        } else {
            // Use image size with padding
            windowWidth = max(image.size.width + 100, 600)
            windowHeight = max(image.size.height + 150, 500)
        }
        
        // Add space for toolbar
        windowHeight += 60
        
        let contentRect = NSRect(
            x: (screenFrame.width - windowWidth) / 2 + screenFrame.origin.x,
            y: (screenFrame.height - windowHeight) / 2 + screenFrame.origin.y,
            width: windowWidth,
            height: windowHeight
        )
        
        super.init(
            contentRect: contentRect,
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        
        self.title = "Annotate Screenshot"
        self.minSize = NSSize(width: 500, height: 400)
        self.delegate = self
        
        setupContent()
    }
    
    private func setupContent() {
        // Create the SwiftUI content
        let editorView = AnnotationEditorView(
            state: state,
            onSave: { [weak self] in self?.saveImage() },
            onCopy: { [weak self] in self?.copyToClipboard() },
            onCancel: { [weak self] in self?.cancelAndClose() }
        )
        
        let hostingView = NSHostingView(rootView: editorView)
        self.contentView = hostingView
    }
    
    private func saveImage() {
        guard let finalImage = state.renderFinalImage() else { return }
        
        if let url = savedURL {
            // Overwrite existing file
            saveToDisk(image: finalImage, url: url)
        } else {
            // Show save panel
            let savePanel = NSSavePanel()
            savePanel.allowedContentTypes = [.png]
            savePanel.nameFieldStringValue = FileNaming.generateFilename()
            savePanel.directoryURL = PreferencesManager.shared.saveLocation
            
            savePanel.beginSheetModal(for: self) { [weak self] response in
                if response == .OK, let url = savePanel.url {
                    self?.saveToDisk(image: finalImage, url: url)
                }
            }
        }
    }
    
    private func saveToDisk(image: NSImage, url: URL) {
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:]) else {
            showAlert(title: "Save Failed", message: "Could not convert image to PNG format.")
            return
        }
        
        do {
            try pngData.write(to: url)
            onSave?(image)
            close()
            
            // Show in Finder
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } catch {
            showAlert(title: "Save Failed", message: error.localizedDescription)
        }
    }
    
    private func copyToClipboard() {
        guard let finalImage = state.renderFinalImage() else { return }
        
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([finalImage])
        
        // Visual feedback
        flashWindow()
    }
    
    private func flashWindow() {
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.1
            self.animator().alphaValue = 0.7
        }, completionHandler: {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.1
                self.animator().alphaValue = 1.0
            }
        })
    }
    
    private func cancelAndClose() {
        // Check if there are unsaved changes
        if !state.annotations.isEmpty {
            let alert = NSAlert()
            alert.messageText = "Discard Changes?"
            alert.informativeText = "You have unsaved annotations. Are you sure you want to close?"
            alert.alertStyle = .warning
            alert.addButton(withTitle: "Discard")
            alert.addButton(withTitle: "Cancel")
            
            alert.beginSheetModal(for: self) { [weak self] response in
                if response == .alertFirstButtonReturn {
                    self?.onCancel?()
                    self?.close()
                }
            }
        } else {
            onCancel?()
            close()
        }
    }
    
    private func showAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.beginSheetModal(for: self, completionHandler: nil)
    }
    
    func show() {
        makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

extension AnnotationEditorWindow: NSWindowDelegate {
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if !state.annotations.isEmpty {
            cancelAndClose()
            return false
        }
        onCancel?()
        return true
    }
}

// MARK: - SwiftUI Editor View

struct AnnotationEditorView: View {
    @ObservedObject var state: AnnotationEditorState
    let onSave: () -> Void
    let onCopy: () -> Void
    let onCancel: () -> Void
    
    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                // Toolbar
                AnnotationToolbar(state: state, onSave: onSave, onCopy: onCopy, onCancel: onCancel)
                
                Divider()
                
                // Canvas
                GeometryReader { geometry in
                    ZStack {
                        AnnotationCanvasRepresentable(state: state)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        
                        // Text editor overlay
                        if state.editingTextAnnotationId != nil {
                            TextEditorOverlay(
                                state: state,
                                canvasRect: geometry.frame(in: .local),
                                scale: calculateScale(for: geometry.size)
                            )
                        }
                    }
                }
                
                // Bottom bar with tool options
                if state.currentToolType != .select {
                    Divider()
                    ToolOptionsBar(state: state)
                }
            }
            .background(Color(NSColor.controlBackgroundColor))
        }
    }
    
    private func calculateScale(for viewSize: CGSize) -> CGFloat {
        let imageSize = state.imageSize
        let imageAspect = imageSize.width / imageSize.height
        let viewAspect = viewSize.width / viewSize.height
        
        if imageAspect > viewAspect {
            return viewSize.width / imageSize.width
        } else {
            return viewSize.height / imageSize.height
        }
    }
}

// MARK: - Toolbar

struct AnnotationToolbar: View {
    @ObservedObject var state: AnnotationEditorState
    let onSave: () -> Void
    let onCopy: () -> Void
    let onCancel: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            // Tool buttons
            HStack(spacing: 4) {
                ForEach(AnnotationToolType.allCases) { tool in
                    ToolButton(
                        tool: tool,
                        isSelected: state.currentToolType == tool,
                        action: { state.setTool(tool) }
                    )
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(NSColor.controlBackgroundColor))
            )
            
            Spacer()
            
            // Undo/Redo
            HStack(spacing: 4) {
                Button(action: { state.undo() }) {
                    Image(systemName: "arrow.uturn.backward")
                }
                .buttonStyle(ToolbarButtonStyle())
                .disabled(!state.canUndo)
                .help("Undo (⌘Z)")
                
                Button(action: { state.redo() }) {
                    Image(systemName: "arrow.uturn.forward")
                }
                .buttonStyle(ToolbarButtonStyle())
                .disabled(!state.canRedo)
                .help("Redo (⌘⇧Z)")
            }
            
            Divider()
                .frame(height: 24)
            
            // Action buttons
            HStack(spacing: 8) {
                Button("Cancel") {
                    onCancel()
                }
                .keyboardShortcut(.escape, modifiers: [])
                
                Button(action: onCopy) {
                    Label("Copy", systemImage: "doc.on.doc")
                }
                .keyboardShortcut("c", modifiers: [.command, .shift])
                .help("Copy to clipboard (⌘⇧C)")
                
                Button(action: onSave) {
                    Label("Save", systemImage: "square.and.arrow.down")
                }
                .keyboardShortcut("s", modifiers: .command)
                .buttonStyle(.borderedProminent)
                .help("Save image (⌘S)")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color(NSColor.windowBackgroundColor))
    }
}

struct ToolButton: View {
    let tool: AnnotationToolType
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Image(systemName: tool.icon)
                .font(.system(size: 14))
                .frame(width: 28, height: 28)
        }
        .buttonStyle(ToolButtonStyle(isSelected: isSelected))
        .help(tool.tooltip)
    }
}

struct ToolButtonStyle: ButtonStyle {
    let isSelected: Bool
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? Color.accentColor : (configuration.isPressed ? Color.gray.opacity(0.3) : Color.clear))
            )
            .foregroundColor(isSelected ? .white : .primary)
    }
}

struct ToolbarButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14))
            .frame(width: 28, height: 28)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(configuration.isPressed ? Color.gray.opacity(0.3) : Color.clear)
            )
            .foregroundColor(.primary)
    }
}

// MARK: - Tool Options Bar

struct ToolOptionsBar: View {
    @ObservedObject var state: AnnotationEditorState
    
    var body: some View {
        HStack(spacing: 20) {
            // Color picker
            HStack(spacing: 8) {
                Text("Color:")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                ColorPickerButton(selectedColor: state.currentColor) { color in
                    state.setColor(color)
                }
                
                // Recent colors
                HStack(spacing: 4) {
                    ForEach(Array(state.recentColors.enumerated()), id: \.offset) { _, color in
                        ColorSwatch(color: color, isSelected: state.currentColor == color) {
                            state.setColor(color)
                        }
                    }
                }
            }
            
            Divider()
                .frame(height: 20)
            
            // Stroke width (not for text or counter)
            if ![.text, .counter].contains(state.currentToolType) {
                HStack(spacing: 8) {
                    Text("Stroke:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Slider(value: Binding(
                        get: { state.strokeWidth },
                        set: { state.strokeWidth = $0 }
                    ), in: 1...10, step: 1)
                    .frame(width: 100)
                    
                    Text("\(Int(state.strokeWidth))px")
                        .font(.caption)
                        .frame(width: 30)
                }
            }
            
            // Fill toggle (for shapes)
            if [.rectangle, .ellipse].contains(state.currentToolType) {
                Divider()
                    .frame(height: 20)
                
                Toggle("Fill", isOn: Binding(
                    get: { state.fillEnabled },
                    set: { state.fillEnabled = $0 }
                ))
                .toggleStyle(.checkbox)
                .font(.caption)
            }
            
            // Font size (for text)
            if state.currentToolType == .text {
                Divider()
                    .frame(height: 20)
                
                HStack(spacing: 8) {
                    Text("Size:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Slider(value: Binding(
                        get: { state.fontSize },
                        set: { state.fontSize = $0 }
                    ), in: 10...48, step: 2)
                    .frame(width: 100)
                    
                    Text("\(Int(state.fontSize))pt")
                        .font(.caption)
                        .frame(width: 30)
                }
            }
            
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color(NSColor.windowBackgroundColor))
    }
}

// MARK: - Color Picker Components

struct ColorPickerButton: View {
    let selectedColor: NSColor
    let onColorSelected: (NSColor) -> Void
    
    @State private var showingPicker = false
    
    var body: some View {
        Button(action: { showingPicker.toggle() }) {
            RoundedRectangle(cornerRadius: 4)
                .fill(Color(selectedColor))
                .frame(width: 24, height: 24)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color.gray.opacity(0.5), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showingPicker) {
            ColorGridPicker(selectedColor: selectedColor) { color in
                onColorSelected(color)
                showingPicker = false
            }
            .padding()
        }
    }
}

struct ColorGridPicker: View {
    let selectedColor: NSColor
    let onColorSelected: (NSColor) -> Void
    
    private let colors: [[NSColor]] = [
        [.systemRed, .systemOrange, .systemYellow, .systemGreen, .systemMint],
        [.systemTeal, .systemCyan, .systemBlue, .systemIndigo, .systemPurple],
        [.systemPink, .systemBrown, .black, .darkGray, .white]
    ]
    
    var body: some View {
        VStack(spacing: 8) {
            ForEach(0..<colors.count, id: \.self) { row in
                HStack(spacing: 8) {
                    ForEach(0..<colors[row].count, id: \.self) { col in
                        let color = colors[row][col]
                        ColorSwatch(color: color, isSelected: selectedColor == color, size: 28) {
                            onColorSelected(color)
                        }
                    }
                }
            }
        }
    }
}

struct ColorSwatch: View {
    let color: NSColor
    let isSelected: Bool
    var size: CGFloat = 18
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            ZStack {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(color))
                    .frame(width: size, height: size)
                
                if isSelected {
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color.accentColor, lineWidth: 2)
                        .frame(width: size + 2, height: size + 2)
                }
            }
        }
        .buttonStyle(.plain)
    }
}
