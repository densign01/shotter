import AppKit

/// Controller for managing the annotation editor lifecycle
class AnnotationEditorController {
    static let shared = AnnotationEditorController()
    
    private var editorWindow: AnnotationEditorWindow?
    
    private init() {}
    
    /// Open the annotation editor with the given image
    /// - Parameters:
    ///   - image: The screenshot image to annotate
    ///   - savedURL: The URL where the image was saved (for overwriting)
    ///   - onComplete: Called when editing is complete with the final image
    ///   - onCancel: Called when editing is cancelled
    func openEditor(
        image: NSImage,
        savedURL: URL?,
        onComplete: @escaping (NSImage) -> Void,
        onCancel: @escaping () -> Void
    ) {
        DebugLogger.log("openEditor called; savedURL=\(savedURL?.path ?? "nil")")
        // Close any existing editor
        closeEditor()
        
        // Create new editor window
        var window: AnnotationEditorWindow? = nil
        window = AnnotationEditorWindow(
            image: image,
            savedURL: savedURL,
            onSave: { finalImage in
                DebugLogger.log("Annotation editor onSave callback")
                onComplete(finalImage)
            },
            onCancel: {
                DebugLogger.log("Annotation editor onCancel callback")
                onCancel()
            },
            onClosed: { [weak self] in
                DebugLogger.log("Annotation editor onClosed callback")
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    guard let window else {
                        DebugLogger.log("onClosed ran but window reference was nil")
                        return
                    }
                    // Only clear if this is still the active editor window.
                    if self.editorWindow === window {
                        self.editorWindow = nil
                        DebugLogger.log("Annotation editor window reference cleared after close")
                    } else {
                        DebugLogger.log("Skipped clearing editor window; a newer window is active")
                    }
                }
            }
        )

        editorWindow = window
        
        editorWindow?.show()
    }
    
    /// Close the annotation editor if open
    func closeEditor() {
        DebugLogger.log("closeEditor called; hasWindow=\(editorWindow != nil)")
        guard let window = editorWindow else { return }
        window.close()
        // Defer clearing to avoid releasing the window mid-close sequence.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if self.editorWindow === window {
                self.editorWindow = nil
                DebugLogger.log("Annotation editor window reference cleared after explicit close")
            }
        }
    }
    
    /// Check if the editor is currently open
    var isEditorOpen: Bool {
        editorWindow != nil
    }
}
