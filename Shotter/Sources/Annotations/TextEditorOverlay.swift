import AppKit
import SwiftUI

/// A text field overlay for editing text annotations
struct TextEditorOverlay: View {
    @ObservedObject var state: AnnotationEditorState
    let imageRect: CGRect
    let scale: CGFloat
    
    @State private var editText: String = ""
    @FocusState private var isFocused: Bool
    
    var body: some View {
        if let editingId = state.editingTextAnnotationId,
           let anyAnnotation = state.annotations.first(where: { $0.id == editingId }),
           let textAnnotation = anyAnnotation.annotation as? TextAnnotation {
            
            let viewBounds = convertToViewCoordinates(textAnnotation.bounds)
            
            ZStack {
                // Semi-transparent overlay
                Color.black.opacity(0.3)
                    .onTapGesture {
                        finishEditing()
                    }
                
                // Text field positioned at annotation location
                VStack(spacing: 8) {
                    TextField("Enter text", text: $editText, onCommit: {
                        finishEditing()
                    })
                    .textFieldStyle(.plain)
                    .font(.system(size: state.fontSize, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color(state.currentColor))
                    )
                    .frame(minWidth: 100, maxWidth: 400)
                    .focused($isFocused)
                    
                    HStack(spacing: 12) {
                        Button("Cancel") {
                            cancelEditing()
                        }
                        .keyboardShortcut(.escape, modifiers: [])
                        
                        Button("Done") {
                            finishEditing()
                        }
                        .keyboardShortcut(.return, modifiers: [])
                        .buttonStyle(.borderedProminent)
                    }
                }
                .position(
                    x: viewBounds.midX,
                    y: viewBounds.midY
                )
            }
            .onAppear {
                editText = textAnnotation.text
                isFocused = true
            }
        }
    }

    private func convertToViewCoordinates(_ imageBounds: CGRect) -> CGRect {
        // Annotation bounds are bottom-left origin (y-up, matching the
        // non-flipped canvas); SwiftUI positions are top-left origin (y-down).
        // Flip Y so the editor appears exactly where the user clicked.
        CGRect(
            x: imageRect.origin.x + imageBounds.origin.x * scale,
            y: imageRect.maxY - imageBounds.maxY * scale,
            width: imageBounds.width * scale,
            height: imageBounds.height * scale
        )
    }

    /// A freshly placed annotation still has its empty placeholder text.
    private func isNewAnnotation(_ id: AnnotationID) -> Bool {
        guard let anyAnnotation = state.annotations.first(where: { $0.id == id }),
              let textAnnotation = anyAnnotation.annotation as? TextAnnotation else {
            return false
        }
        return textAnnotation.text.isEmpty
    }

    private func finishEditing() {
        guard let editingId = state.editingTextAnnotationId else { return }
        let isNew = isNewAnnotation(editingId)

        if editText.isEmpty {
            // Remove empty text annotations; for a never-committed placeholder
            // also drop its creation checkpoint so undo can't resurrect it
            if isNew {
                state.removeFailedCreation(editingId)
            } else {
                state.removeAnnotation(editingId)
            }
        } else {
            // Creation already pushed a checkpoint for new annotations, so
            // create + first text commit undoes as a single action
            state.updateTextAnnotation(id: editingId, text: editText, recordUndo: !isNew)
        }

        state.finishTextEditing()
    }

    private func cancelEditing() {
        guard let editingId = state.editingTextAnnotationId else { return }

        // Remove a never-committed placeholder without leaving an undo entry
        if isNewAnnotation(editingId) {
            state.removeFailedCreation(editingId)
        }

        state.finishTextEditing()
    }
}
