import SwiftUI

struct MockupEditorView: View {
    let sourceImage: NSImage
    let onApply: (NSImage) -> Void
    let onCancel: () -> Void

    @State private var selectedBackground: BackgroundStyle = .gradientBlue
    @State private var selectedMockup: MockupFrame = .none
    @State private var padding: CGFloat = 60
    @State private var cornerRadius: CGFloat = 12
    @State private var previewImage: NSImage?

    var body: some View {
        VStack(spacing: 0) {
            // Preview
            Group {
                if let preview = previewImage {
                    Image(nsImage: preview)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxHeight: 350)
                } else {
                    Image(nsImage: sourceImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxHeight: 350)
                }
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            // Controls
            Form {
                Picker("Background", selection: $selectedBackground) {
                    ForEach(BackgroundStyle.allCases) { style in
                        Text(style.rawValue).tag(style)
                    }
                }

                Picker("Frame", selection: $selectedMockup) {
                    ForEach(MockupFrame.allCases) { frame in
                        Text(frame.rawValue).tag(frame)
                    }
                }

                if selectedBackground != .none {
                    HStack {
                        Text("Padding")
                        Slider(value: $padding, in: 20...120, step: 10)
                        Text("\(Int(padding))px")
                            .frame(width: 40)
                    }

                    HStack {
                        Text("Corner Radius")
                        Slider(value: $cornerRadius, in: 0...24, step: 2)
                        Text("\(Int(cornerRadius))px")
                            .frame(width: 40)
                    }
                }
            }
            .padding()

            Divider()

            // Action buttons
            HStack {
                Button("Cancel") { onCancel() }
                    .keyboardShortcut(.escape, modifiers: [])
                Spacer()
                Button("Apply") {
                    let result = renderFinal()
                    onApply(result)
                }
                .keyboardShortcut(.return, modifiers: [])
                .buttonStyle(.borderedProminent)
            }
            .padding()
        }
        .frame(width: 500, height: 600)
        .onChange(of: selectedBackground) { _ in updatePreview() }
        .onChange(of: selectedMockup) { _ in updatePreview() }
        .onChange(of: padding) { _ in updatePreview() }
        .onChange(of: cornerRadius) { _ in updatePreview() }
        .onAppear { updatePreview() }
    }

    private func updatePreview() {
        previewImage = renderFinal()
    }

    private func renderFinal() -> NSImage {
        var image = sourceImage

        // Apply mockup frame first
        image = selectedMockup.apply(to: image)

        // Then apply background
        if selectedBackground != .none {
            image = selectedBackground.render(screenshot: image, padding: padding, cornerRadius: cornerRadius)
        }

        return image
    }
}
