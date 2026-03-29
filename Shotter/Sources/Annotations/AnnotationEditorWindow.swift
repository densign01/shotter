import AppKit
import SwiftUI

/// The main annotation editor window
class AnnotationEditorWindow: NSWindow {
    private var state: AnnotationEditorState
    private var onSave: ((NSImage) -> Void)?
    private var onCancel: (() -> Void)?
    private var onClosed: (() -> Void)?
    private var savedURL: URL?
    private var isProgrammaticClose = false
    private var didInvokeCancel = false
    private var closeRetain: AnnotationEditorWindow?
    
    init(
        image: NSImage,
        savedURL: URL?,
        preferredScreen: NSScreen?,
        onSave: @escaping (NSImage) -> Void,
        onCancel: @escaping () -> Void,
        onClosed: @escaping () -> Void
    ) {
        self.state = AnnotationEditorState(image: image)
        self.onSave = onSave
        self.onCancel = onCancel
        self.onClosed = onClosed
        self.savedURL = savedURL
        
        // Calculate window size based on image
        let screenFrame = preferredScreen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1200, height: 800)
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
        DebugLogger.log("Annotation editor window initialized; savedURL=\(savedURL?.path ?? "nil")")
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
        DebugLogger.log("Save requested")
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
    
    private func saveToDisk(image: NSImage, url: URL, showInFinder: Bool = true) {
        DebugLogger.log("Saving to disk at \(url.path); showInFinder=\(showInFinder)")
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:]) else {
            showAlert(title: "Save Failed", message: "Could not convert image to PNG format.")
            return
        }

        do {
            try pngData.write(to: url)
            DebugLogger.log("Write succeeded at \(url.path)")
            onSave?(image)
            closeProgrammatically()

            if showInFinder {
                NSWorkspace.shared.activateFileViewerSelecting([url])
            }
        } catch {
            DebugLogger.log("Write failed at \(url.path): \(error.localizedDescription)")
            showAlert(title: "Save Failed", message: error.localizedDescription)
        }
    }
    
    private func copyToClipboard() {
        DebugLogger.log("Copy requested")
        guard let finalImage = state.renderFinalImage() else { return }

        // Convert image to PNG data
        guard let tiffData = finalImage.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:]) else {
            DebugLogger.log("Failed to convert image to PNG for clipboard")
            return
        }

        var savedFileURL = savedURL
        if let targetURL = savedURL {
            do {
                try pngData.write(to: targetURL)
                DebugLogger.log("Updated saved image at \(targetURL.path) before clipboard copy")
            } catch {
                DebugLogger.log("Failed to refresh saved image before clipboard copy: \(error.localizedDescription)")
                savedFileURL = nil
            }
        }

        // Copy to pasteboard with formats optimized for terminal apps (Ghostty, etc.)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        // Declare types (order matters - most preferred first)
        var types: [NSPasteboard.PasteboardType] = [.png, .tiff]
        if savedFileURL != nil {
            types.insert(.fileURL, at: 0)
        }
        pasteboard.declareTypes(types, owner: nil)

        // Write file URL if available (enables terminal apps like Ghostty)
        if let fileURL = savedFileURL {
            pasteboard.setString(fileURL.absoluteString, forType: .fileURL)
        }

        // Write PNG data explicitly (preferred by most apps)
        pasteboard.setData(pngData, forType: .png)

        // Write TIFF data for apps that prefer it
        pasteboard.setData(tiffData, forType: .tiff)

        DebugLogger.log("Copied to pasteboard\(savedFileURL != nil ? " with file URL: \(savedFileURL!.path)" : " (no file URL)")")

        // Close the editor
        onSave?(finalImage)
        closeProgrammatically()
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
        DebugLogger.log("Cancel requested; annotationCount=\(state.annotations.count)")
        // Check if there are unsaved changes
        if state.hasUnsavedChanges {
            let alert = NSAlert()
            alert.messageText = "Discard Changes?"
            alert.informativeText = "You have unsaved annotations. Are you sure you want to close?"
            alert.alertStyle = .warning
            alert.addButton(withTitle: "Discard")
            alert.addButton(withTitle: "Cancel")
            
            alert.beginSheetModal(for: self) { [weak self] response in
                if response == .alertFirstButtonReturn {
                    DebugLogger.log("Discard confirmed")
                    self?.notifyCancelIfNeeded()
                    self?.closeProgrammatically()
                }
            }
        } else {
            notifyCancelIfNeeded()
            closeProgrammatically()
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
        DebugLogger.log("Showing annotation editor window")
        makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        state.requestCanvasFocus()
    }

    private func closeProgrammatically() {
        DebugLogger.log("Closing annotation editor programmatically")
        isProgrammaticClose = true

        // Hold a temporary strong reference to self so AppKit can finish its close sequence.
        closeRetain = self

        // Break delegate cycle before closing.
        delegate = nil

        // Nil out callbacks to break closure retain cycles.
        onSave = nil
        onCancel = nil
        // Note: onClosed is called in windowWillClose, keep it for now

        // Hide window immediately to prevent further interaction.
        orderOut(nil)

        // Release SwiftUI content to break observation chain.
        contentView = nil
        DebugLogger.log("Released SwiftUI contentView and callbacks")

        // Wait several run loop turns for SwiftUI/Combine cleanup before close.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                DebugLogger.log("Calling close()")
                self.close()

                // Wait more turns before releasing self-retain.
                DispatchQueue.main.async { [weak self] in
                    DispatchQueue.main.async { [weak self] in
                        DispatchQueue.main.async { [weak self] in
                            self?.closeRetain = nil
                            DebugLogger.log("Released temporary close retain")
                        }
                    }
                }
            }
        }
    }

    private func notifyCancelIfNeeded() {
        guard !didInvokeCancel else { return }
        didInvokeCancel = true
        DebugLogger.log("Invoking onCancel callback")
        onCancel?()
    }

    deinit {
        DebugLogger.log("Annotation editor window deinitialized")
    }
}

extension AnnotationEditorWindow: NSWindowDelegate {
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        DebugLogger.log("windowShouldClose; isProgrammaticClose=\(isProgrammaticClose); annotationCount=\(state.annotations.count)")
        if isProgrammaticClose {
            return true
        }
        if state.hasUnsavedChanges {
            cancelAndClose()
            return false
        }
        notifyCancelIfNeeded()
        return true
    }

    func windowWillClose(_ notification: Notification) {
        DebugLogger.log("windowWillClose")
        onClosed?()
        onClosed = nil
    }
}

// MARK: - Key Event Handling

extension AnnotationEditorWindow {
    /// Handle Escape key explicitly to prevent default app termination behavior
    override func cancelOperation(_ sender: Any?) {
        cancelAndClose()
    }
}

// MARK: - SwiftUI Editor View

struct AnnotationEditorView: View {
    @ObservedObject var state: AnnotationEditorState
    let onSave: () -> Void
    let onCopy: () -> Void
    let onCancel: () -> Void

    @State private var showMockupEditor = false

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                // Toolbar
                AnnotationToolbar(
                    state: state,
                    onSave: onSave,
                    onCopy: onCopy,
                    onCancel: onCancel,
                    onMockup: { showMockupEditor = true }
                )

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
                                imageRect: annotationImageRect(in: geometry.size, imageSize: state.imageSize),
                                scale: calculateScale(for: geometry.size)
                            )
                        }
                    }
                }

                // Bottom bar with tool options (always visible for consistent layout)
                Divider()
                ToolOptionsBar(state: state)
                DragMeBar(state: state)
            }
            .background(Color(NSColor.controlBackgroundColor))
        }
        .sheet(isPresented: $showMockupEditor) {
            MockupEditorView(
                sourceImage: state.baseImage,
                onApply: { mockupImage in
                    state.applyMockup(mockupImage)
                    showMockupEditor = false
                },
                onCancel: {
                    showMockupEditor = false
                }
            )
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
    let onMockup: () -> Void

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
                HoverIconButton(icon: "arrow.uturn.backward", tooltip: "Undo (⌘Z)", action: { state.undo() })
                    .disabled(!state.canUndo)

                HoverIconButton(icon: "arrow.uturn.forward", tooltip: "Redo (⌘⇧Z)", action: { state.redo() })
                    .disabled(!state.canRedo)
            }

            // Mockup button
            HoverIconButton(icon: "macwindow", tooltip: "Add Mockup", action: onMockup)

            Divider()
                .frame(height: 24)

            // Action buttons (icon-only for compact layout)
            HStack(spacing: 4) {
                HoverIconButton(icon: "xmark", tooltip: "Cancel (Esc)", action: onCancel)
                    .keyboardShortcut(.escape, modifiers: [])

                HoverIconButton(icon: "doc.on.doc", tooltip: "Copy & Save (⌘⇧C)", action: onCopy)
                    .keyboardShortcut("c", modifiers: [.command, .shift])

                HoverIconButton(icon: "square.and.arrow.down", tooltip: "Save (⌘S)", isPrimary: true, action: onSave)
                    .keyboardShortcut("s", modifiers: .command)
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

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: tool.icon)
                .font(.system(size: 14))
                .frame(width: 28, height: 28)
        }
        .buttonStyle(ToolButtonStyle(isSelected: isSelected, isHovered: isHovered))
        .shadow(color: .black.opacity(isHovered && !isSelected ? 0.3 : 0), radius: isHovered ? 3 : 0, y: isHovered ? 1 : 0)
        .scaleEffect(isHovered && !isSelected ? 1.1 : 1.0)
        .animation(.easeInOut(duration: 0.15), value: isHovered)
        .onHover { hovering in
            isHovered = hovering
        }
        .help(tool.tooltip)
        .accessibilityLabel(Text(tool.rawValue))
        .accessibilityHint(Text(tool.tooltip))
        .accessibilityValue(Text(isSelected ? "Selected" : "Not selected"))
    }
}

struct ToolButtonStyle: ButtonStyle {
    let isSelected: Bool
    var isHovered: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(backgroundColor(isPressed: configuration.isPressed))
            )
            .foregroundColor(isSelected ? .white : .primary)
    }

    private func backgroundColor(isPressed: Bool) -> Color {
        if isSelected {
            return Color.accentColor
        } else if isPressed {
            return Color.gray.opacity(0.3)
        } else if isHovered {
            return Color.gray.opacity(0.15)
        }
        return Color.clear
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

struct ActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14))
            .frame(width: 28, height: 28)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(configuration.isPressed ? Color.accentColor.opacity(0.8) : Color.accentColor)
            )
            .foregroundColor(.white)
    }
}

struct HoverIconButton: View {
    let icon: String
    let tooltip: String
    var isPrimary: Bool = false
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(backgroundColor)
                )
                .foregroundColor(isPrimary ? .white : .primary)
        }
        .buttonStyle(.plain)
        .shadow(color: .black.opacity(isHovered ? 0.3 : 0), radius: isHovered ? 3 : 0, y: isHovered ? 1 : 0)
        .scaleEffect(isHovered ? 1.1 : 1.0)
        .animation(.easeInOut(duration: 0.15), value: isHovered)
        .onHover { hovering in
            isHovered = hovering
        }
        .help(tooltip)
        .accessibilityLabel(Text(tooltip))
    }

    private var backgroundColor: Color {
        if isPrimary {
            return Color.accentColor
        } else if isHovered {
            return Color.gray.opacity(0.2)
        }
        return Color.clear
    }
}

// MARK: - Color Swatch Button

struct ColorSwatchButton: View {
    let color: NSColor
    let isSelected: Bool
    let colorName: String
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Circle()
                .fill(Color(color))
                .frame(width: 22, height: 22)
                .overlay(
                    // Selection ring
                    Circle()
                        .stroke(Color.primary, lineWidth: isSelected ? 2 : 0)
                        .frame(width: 26, height: 26)
                )
        }
        .buttonStyle(.plain)
        .shadow(color: .black.opacity(isHovered ? 0.5 : 0), radius: isHovered ? 4 : 0, y: isHovered ? 2 : 0)
        .scaleEffect(isHovered ? 1.15 : 1.0)
        .animation(.easeInOut(duration: 0.15), value: isHovered)
        .onHover { hovering in
            isHovered = hovering
        }
        .help(colorName)
        .accessibilityLabel(Text(colorName))
        .accessibilityValue(Text(isSelected ? "Selected" : "Not selected"))
    }
}

// MARK: - Tool Options Bar

struct ToolOptionsBar: View {
    @ObservedObject var state: AnnotationEditorState

    private let presetColors: [NSColor] = [
        .systemRed, .systemOrange, .systemYellow, .systemGreen,
        .systemBlue, .systemPurple, .black, .white
    ]

    private let strokeSizes: [CGFloat] = [1, 2, 3, 5, 8]
    private let fontSizes: [CGFloat] = [12, 16, 24, 32, 48]

    var body: some View {
        HStack(spacing: 16) {
            // Tool-specific options (not for select, eraser, or crop tools)
            if ![.select, .eraser, .crop].contains(state.currentToolType) {
                // Color swatches with selection ring and hover effect
                HStack(spacing: 6) {
                    ForEach(presetColors, id: \.self) { color in
                        ColorSwatchButton(
                            color: color,
                            isSelected: state.currentColor == color,
                            colorName: colorName(for: color)
                        ) {
                            state.setColor(color)
                        }
                    }
                }

                Divider()
                    .frame(height: 20)

                // Stroke size dropdown (not for text or counter)
                if ![.text, .counter].contains(state.currentToolType) {
                    Picker("", selection: Binding(
                        get: { closestStrokeSize(state.strokeWidth) },
                        set: { state.strokeWidth = $0 }
                    )) {
                        ForEach(strokeSizes, id: \.self) { size in
                            Text("\(Int(size))px").tag(size)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 70)
                }

                // Fill toggle (for shapes)
                if [.rectangle, .ellipse].contains(state.currentToolType) {
                    Toggle("Fill", isOn: Binding(
                        get: { state.fillEnabled },
                        set: { state.fillEnabled = $0 }
                    ))
                    .toggleStyle(.checkbox)
                    .font(.caption)
                }

                // Font size dropdown (for text)
                if state.currentToolType == .text {
                    Picker("", selection: Binding(
                        get: { closestFontSize(state.fontSize) },
                        set: { state.fontSize = $0 }
                    )) {
                        ForEach(fontSizes, id: \.self) { size in
                            Text("\(Int(size))pt").tag(size)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 70)
                }
            }

            Spacer()

            // Keyboard shortcut hints (always visible)
            Text(keyboardHint)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .frame(height: 44)
        .background(Color(NSColor.windowBackgroundColor))
    }

    private func closestStrokeSize(_ value: CGFloat) -> CGFloat {
        strokeSizes.min(by: { abs($0 - value) < abs($1 - value) }) ?? 3
    }

    private func closestFontSize(_ value: CGFloat) -> CGFloat {
        fontSizes.min(by: { abs($0 - value) < abs($1 - value) }) ?? 16
    }

    private func colorName(for color: NSColor) -> String {
        switch color {
        case .systemRed: return "Red"
        case .systemOrange: return "Orange"
        case .systemYellow: return "Yellow"
        case .systemGreen: return "Green"
        case .systemBlue: return "Blue"
        case .systemPurple: return "Purple"
        case .black: return "Black"
        case .white: return "White"
        default: return "Color"
        }
    }

    private var keyboardHint: String {
        switch state.currentToolType {
        case .select:
            return "Click to select • Drag to move • Delete to remove"
        case .arrow:
            return "Drag to draw arrow"
        case .rectangle:
            return "Drag to draw rectangle • Hold ⇧ for square"
        case .ellipse:
            return "Drag to draw ellipse • Hold ⇧ for circle"
        case .line:
            return "Drag to draw line"
        case .text:
            return "Click to place text"
        case .blur:
            return "Drag to blur region"
        case .counter:
            return "Click to place counter"
        case .eraser:
            return "Click annotation to remove it"
        case .crop:
            if state.cropRect != nil {
                return "↩ Enter to apply crop • Esc to cancel"
            }
            return "Drag to select crop area"
        case .textHighlight:
            return "Drag to highlight"
        }
    }
}

// MARK: - Drag Me Bar

struct DragMeBar: View {
    @ObservedObject var state: AnnotationEditorState

    var body: some View {
        HStack(spacing: 8) {
            Spacer()
            Image(systemName: "hand.draw")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
            Text("Drag to any app")
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
        }
        .padding(.vertical, 6)
        .background(Color(NSColor.windowBackgroundColor))
        .onDrag {
            guard let image = state.renderFinalImage(),
                  let tiffData = image.tiffRepresentation,
                  let bitmap = NSBitmapImageRep(data: tiffData),
                  let pngData = bitmap.representation(using: .png, properties: [:]) else {
                return NSItemProvider()
            }
            let provider = NSItemProvider()
            provider.registerDataRepresentation(forTypeIdentifier: "public.png", visibility: .all) { completion in
                completion(pngData, nil)
                return nil
            }
            return provider
        }
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
        .accessibilityLabel(Text("Custom color"))
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
        .accessibilityLabel(Text(color.accessibilityName))
        .accessibilityValue(Text(isSelected ? "Selected" : "Not selected"))
    }
}

private extension NSColor {
    var accessibilityName: String {
        switch self {
        case .systemRed: return "Red"
        case .systemOrange: return "Orange"
        case .systemYellow: return "Yellow"
        case .systemGreen: return "Green"
        case .systemMint: return "Mint"
        case .systemTeal: return "Teal"
        case .systemCyan: return "Cyan"
        case .systemBlue: return "Blue"
        case .systemIndigo: return "Indigo"
        case .systemPurple: return "Purple"
        case .systemPink: return "Pink"
        case .systemBrown: return "Brown"
        case .black: return "Black"
        case .darkGray: return "Dark Gray"
        case .white: return "White"
        default: return "Color"
        }
    }
}
