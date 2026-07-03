import AppKit
import SwiftUI

/// An AppKit-backed text field that reliably grabs keyboard focus when it
/// appears. SwiftUI's @FocusState loses the race against the canvas NSView
/// (which is the window's first responder), so we claim first responder
/// directly once the field is in the window (#69).
private struct AnnotationTextField: NSViewRepresentable {
    @Binding var text: String
    let fontSize: CGFloat
    let onCommit: () -> Void
    let onCancel: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        field.stringValue = text
        field.placeholderString = "Enter text"
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: fontSize, weight: .bold)
        field.textColor = .white
        field.lineBreakMode = .byClipping
        field.cell?.wraps = false
        field.cell?.isScrollable = true
        field.delegate = context.coordinator

        DispatchQueue.main.async {
            guard let window = field.window else { return }
            window.makeFirstResponder(field)
            if let editor = field.currentEditor() as? NSTextView {
                editor.insertionPointColor = .white
                editor.selectedRange = NSRange(location: field.stringValue.count, length: 0)
            }
        }
        return field
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {
        context.coordinator.parent = self
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
        nsView.font = .systemFont(ofSize: fontSize, weight: .bold)
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: AnnotationTextField

        init(_ parent: AnnotationTextField) {
            self.parent = parent
        }

        func controlTextDidChange(_ obj: Notification) {
            guard let field = obj.object as? NSTextField else { return }
            parent.text = field.stringValue
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            switch commandSelector {
            case #selector(NSResponder.insertNewline(_:)):
                parent.onCommit()
                return true
            case #selector(NSResponder.cancelOperation(_:)):
                parent.onCancel()
                return true
            default:
                return false
            }
        }
    }
}

/// A text field overlay for editing text annotations
struct TextEditorOverlay: View {
    @ObservedObject var state: AnnotationEditorState
    let imageRect: CGRect
    let scale: CGFloat

    @State private var editText: String = ""

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
                    AnnotationTextField(
                        text: $editText,
                        fontSize: state.fontSize,
                        onCommit: { finishEditing() },
                        onCancel: { cancelEditing() }
                    )
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color(state.currentColor))
                    )
                    .frame(minWidth: 100, maxWidth: 400)

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
