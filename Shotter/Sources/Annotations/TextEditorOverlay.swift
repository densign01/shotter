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
                editText = textAnnotation.text == "Text" ? "" : textAnnotation.text
                isFocused = true
            }
        }
    }
    
    private func convertToViewCoordinates(_ imageBounds: CGRect) -> CGRect {
        CGRect(
            x: imageRect.origin.x + imageBounds.origin.x * scale,
            y: imageRect.origin.y + imageBounds.origin.y * scale,
            width: imageBounds.width * scale,
            height: imageBounds.height * scale
        )
    }
    
    private func finishEditing() {
        guard let editingId = state.editingTextAnnotationId else { return }
        
        if editText.isEmpty {
            // Remove empty text annotations
            state.removeAnnotation(editingId)
        } else {
            state.updateTextAnnotation(id: editingId, text: editText)
        }
        
        state.finishTextEditing()
    }
    
    private func cancelEditing() {
        guard let editingId = state.editingTextAnnotationId else { return }
        
        // Check if this is a new annotation (text is "Text")
        if let anyAnnotation = state.annotations.first(where: { $0.id == editingId }),
           let textAnnotation = anyAnnotation.annotation as? TextAnnotation,
           textAnnotation.text == "Text" {
            // Remove the placeholder
            state.removeAnnotation(editingId)
        }
        
        state.finishTextEditing()
    }
}
