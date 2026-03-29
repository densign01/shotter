import SwiftUI
import AppKit

/// A sheet view that lets the user configure mockup settings (background, device frame, padding)
/// and preview the result before applying it to the annotation editor.
struct MockupEditorView: View {
    let sourceImage: NSImage
    let onApply: (NSImage) -> Void
    let onCancel: () -> Void

    @State private var config = MockupConfiguration()
    @State private var previewImage: NSImage?

    // Background style selection
    @State private var backgroundMode: Int = 0 // 0=none, 1=solid, 2=gradient
    @State private var solidColor: NSColor = NSColor(white: 0.95, alpha: 1)
    @State private var gradientTop: NSColor = NSColor(red: 0.16, green: 0.50, blue: 0.73, alpha: 1)
    @State private var gradientBottom: NSColor = NSColor(red: 0.07, green: 0.21, blue: 0.40, alpha: 1)

    var body: some View {
        HSplitView {
            // Left: Preview
            previewPanel
                .frame(minWidth: 400)

            // Right: Controls
            controlsPanel
                .frame(width: 280)
        }
        .frame(minWidth: 720, minHeight: 480)
        .onAppear {
            updatePreview()
        }
    }

    // MARK: - Preview Panel

    private var previewPanel: some View {
        VStack {
            Text("Preview")
                .font(.headline)
                .padding(.top, 12)

            if let preview = previewImage {
                Image(nsImage: preview)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .padding(16)
                    .background(
                        // Checkerboard pattern to show transparency
                        CheckerboardView()
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .padding(12)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            Spacer(minLength: 0)
        }
        .background(Color(NSColor.controlBackgroundColor))
    }

    // MARK: - Controls Panel

    private var controlsPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Mockup Settings")
                    .font(.headline)
                    .padding(.top, 12)

                // Background section
                backgroundSection

                Divider()

                // Device frame section
                deviceFrameSection

                Divider()

                // Appearance section
                appearanceSection

                Divider()

                // Preset backgrounds
                presetSection

                Spacer(minLength: 20)

                // Action buttons
                HStack {
                    Button("Cancel") {
                        onCancel()
                    }
                    .keyboardShortcut(.escape, modifiers: [])

                    Spacer()

                    Button("Apply") {
                        let rendered = BackgroundRenderer.render(screenshot: sourceImage, config: config)
                        onApply(rendered)
                    }
                    .keyboardShortcut(.return, modifiers: .command)
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(16)
        }
        .background(Color(NSColor.windowBackgroundColor))
    }

    // MARK: - Background Section

    private var backgroundSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Background")
                .font(.subheadline)
                .fontWeight(.medium)

            Picker("", selection: $backgroundMode) {
                Text("None").tag(0)
                Text("Solid").tag(1)
                Text("Gradient").tag(2)
            }
            .pickerStyle(.segmented)
            .onChange(of: backgroundMode) { _ in
                syncBackgroundToConfig()
            }

            if backgroundMode == 1 {
                ColorPicker("Color", selection: Binding(
                    get: { Color(solidColor) },
                    set: { newColor in
                        solidColor = NSColor(newColor)
                        syncBackgroundToConfig()
                    }
                ))
            }

            if backgroundMode == 2 {
                ColorPicker("Top", selection: Binding(
                    get: { Color(gradientTop) },
                    set: { newColor in
                        gradientTop = NSColor(newColor)
                        syncBackgroundToConfig()
                    }
                ))
                ColorPicker("Bottom", selection: Binding(
                    get: { Color(gradientBottom) },
                    set: { newColor in
                        gradientBottom = NSColor(newColor)
                        syncBackgroundToConfig()
                    }
                ))
            }
        }
    }

    // MARK: - Device Frame Section

    private var deviceFrameSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Device Frame")
                .font(.subheadline)
                .fontWeight(.medium)

            Picker("", selection: $config.deviceFrame) {
                ForEach(DeviceFrame.allCases) { frame in
                    Text(frame.displayName).tag(frame)
                }
            }
            .pickerStyle(.menu)
            .onChange(of: config.deviceFrame) { _ in
                updatePreview()
            }
        }
    }

    // MARK: - Appearance Section

    private var appearanceSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Appearance")
                .font(.subheadline)
                .fontWeight(.medium)

            HStack {
                Text("Padding")
                Slider(value: $config.padding, in: 0...100, step: 4) {
                    Text("Padding")
                }
                Text("\(Int(config.padding))")
                    .frame(width: 30, alignment: .trailing)
                    .monospacedDigit()
            }
            .onChange(of: config.padding) { _ in
                updatePreview()
            }

            HStack {
                Text("Corners")
                Slider(value: $config.cornerRadius, in: 0...24, step: 2) {
                    Text("Corner Radius")
                }
                Text("\(Int(config.cornerRadius))")
                    .frame(width: 30, alignment: .trailing)
                    .monospacedDigit()
            }
            .onChange(of: config.cornerRadius) { _ in
                updatePreview()
            }

            Toggle("Shadow", isOn: $config.shadow)
                .onChange(of: config.shadow) { _ in
                    updatePreview()
                }
        }
    }

    // MARK: - Preset Section

    private var presetSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Presets")
                .font(.subheadline)
                .fontWeight(.medium)

            LazyVGrid(columns: [
                GridItem(.adaptive(minimum: 44))
            ], spacing: 8) {
                ForEach(Array(MockupConfiguration.presetBackgrounds.enumerated()), id: \.offset) { index, preset in
                    PresetSwatchButton(
                        name: preset.0,
                        style: preset.1,
                        action: {
                            applyPresetBackground(preset.1)
                        }
                    )
                }
            }
        }
    }

    // MARK: - Helpers

    private func syncBackgroundToConfig() {
        switch backgroundMode {
        case 0:
            config.background = .none
        case 1:
            config.background = .solidColor(solidColor)
        case 2:
            config.background = .gradient(gradientTop, gradientBottom)
        default:
            break
        }
        updatePreview()
    }

    private func applyPresetBackground(_ style: BackgroundStyle) {
        config.background = style
        switch style {
        case .none:
            backgroundMode = 0
        case .solidColor(let color):
            backgroundMode = 1
            solidColor = color
        case .gradient(let top, let bottom):
            backgroundMode = 2
            gradientTop = top
            gradientBottom = bottom
        }
        updatePreview()
    }

    private func updatePreview() {
        // Generate preview on a background queue for responsiveness
        let currentConfig = config
        let source = sourceImage
        DispatchQueue.global(qos: .userInitiated).async {
            let rendered = BackgroundRenderer.render(screenshot: source, config: currentConfig)
            DispatchQueue.main.async {
                previewImage = rendered
            }
        }
    }
}

// MARK: - Preset Swatch Button

private struct PresetSwatchButton: View {
    let name: String
    let style: BackgroundStyle
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            RoundedRectangle(cornerRadius: 6)
                .fill(swatchFill)
                .frame(width: 44, height: 32)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.primary.opacity(0.2), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .scaleEffect(isHovered ? 1.08 : 1.0)
        .animation(.easeInOut(duration: 0.12), value: isHovered)
        .onHover { hovering in
            isHovered = hovering
        }
        .help(name)
    }

    @ViewBuilder
    private var swatchFill: some ShapeStyle {
        switch style {
        case .none:
            Color.clear
        case .solidColor(let color):
            Color(color)
        case .gradient(let top, let bottom):
            LinearGradient(
                colors: [Color(top), Color(bottom)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }
}

// MARK: - Checkerboard Background (transparency indicator)

private struct CheckerboardView: View {
    var body: some View {
        Canvas { context, size in
            let tileSize: CGFloat = 10
            let rows = Int(ceil(size.height / tileSize))
            let cols = Int(ceil(size.width / tileSize))
            for row in 0..<rows {
                for col in 0..<cols {
                    let isLight = (row + col) % 2 == 0
                    let rect = CGRect(
                        x: CGFloat(col) * tileSize,
                        y: CGFloat(row) * tileSize,
                        width: tileSize,
                        height: tileSize
                    )
                    context.fill(
                        Path(rect),
                        with: .color(isLight ? Color(white: 0.9) : Color(white: 0.8))
                    )
                }
            }
        }
    }
}
