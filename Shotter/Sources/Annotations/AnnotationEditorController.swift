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
        // Close any existing editor
        closeEditor()
        
        // Create new editor window
        editorWindow = AnnotationEditorWindow(
            image: image,
            savedURL: savedURL,
            onSave: { [weak self] finalImage in
                onComplete(finalImage)
                self?.editorWindow = nil
            },
            onCancel: { [weak self] in
                onCancel()
                self?.editorWindow = nil
            }
        )
        
        editorWindow?.show()
    }
    
    /// Close the annotation editor if open
    func closeEditor() {
        editorWindow?.close()
        editorWindow = nil
    }
    
    /// Check if the editor is currently open
    var isEditorOpen: Bool {
        editorWindow != nil
    }
}
