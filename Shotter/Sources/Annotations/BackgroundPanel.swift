import AppKit
import SwiftUI

// MARK: - Toolbar Button

/// Pill button in the editor toolbar that opens the beautify/background panel.
struct BackgroundButton: View {
    @ObservedObject var state: AnnotationEditorState

    @State private var showingPanel = false
    @State private var isHovered = false

    private var isActive: Bool { state.background.isActive }

    var body: some View {
        Button(action: { showingPanel.toggle() }) {
            HStack(spacing: 5) {
                BackgroundPreviewSwatch(style: state.background, size: 16)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 8)
            .frame(height: 30)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(isActive ? Color.accentColor.opacity(isHovered ? 0.22 : 0.15)
                                   : Color.primary.opacity(isHovered ? 0.12 : 0.06))
            )
            .foregroundColor(isActive ? Color.accentColor : .primary)
        }
        .buttonStyle(.plain)
        .fixedSize()
        .onHover { isHovered = $0 }
        .help("Add a background, padding, and window frame")
        .accessibilityLabel(Text("Background style"))
        .popover(isPresented: $showingPanel, arrowEdge: .bottom) {
            BackgroundPanel(state: state)
        }
    }
}

/// A tiny rounded preview of the current background (gradient / solid / none).
struct BackgroundPreviewSwatch: View {
    let style: BackgroundStyle
    var size: CGFloat = 16

    var body: some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(fill)
            .frame(width: size, height: size)
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(Color.primary.opacity(0.2), lineWidth: 1)
            )
            .overlay {
                if case .none = style.kind {
                    Image(systemName: "circle.slash")
                        .font(.system(size: size * 0.7))
                        .foregroundColor(.secondary)
                }
            }
    }

    private var fill: AnyShapeStyle {
        switch style.kind {
        case .none:
            return AnyShapeStyle(Color.primary.opacity(0.05))
        case .solid:
            return AnyShapeStyle(Color(nsColor: style.solidColor))
        case .gradient:
            let colors = style.gradient.colors.map { Color(nsColor: $0) }
            return AnyShapeStyle(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing))
        }
    }
}

// MARK: - Panel

struct BackgroundPanel: View {
    @ObservedObject var state: AnnotationEditorState

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Background")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Button("Reset") { state.background = .disabled }
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.accentColor)
                    .disabled(!state.background.isActive)
            }

            // Fill selection
            sectionHeader("Fill")
            fillSwatches

            Divider()

            // Frame
            sectionHeader("Window Frame")
            frameControls

            Divider()

            // Sliders
            slider("Padding", value: paddingBinding, range: 0...0.22)
            slider("Corners", value: cornerBinding, range: 0...0.08)
            slider("Shadow", value: shadowBinding, range: 0...1)
        }
        .padding(16)
        .frame(width: 300)
    }

    // MARK: Fill swatches

    private var fillSwatches: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Row 1: None + solids
            let cols = [GridItem(.adaptive(minimum: 30, maximum: 30), spacing: 8)]
            LazyVGrid(columns: cols, alignment: .leading, spacing: 8) {
                // None
                SwatchButton(isSelected: state.background.kind == .none) {
                    state.background.kind = .none
                } content: {
                    Image(systemName: "circle.slash")
                        .font(.system(size: 16))
                        .foregroundColor(.secondary)
                }

                ForEach(SolidPreset.hexes, id: \.self) { hex in
                    SwatchButton(isSelected: state.background.kind == .solid && state.background.solidHex == hex) {
                        state.background.kind = .solid
                        state.background.solidHex = hex
                    } content: {
                        RoundedRectangle(cornerRadius: 5)
                            .fill(Color(nsColor: NSColor(hex: hex)))
                    }
                }
            }

            // Row 2: gradients
            LazyVGrid(columns: cols, alignment: .leading, spacing: 8) {
                ForEach(GradientPreset.all) { preset in
                    SwatchButton(isSelected: state.background.kind == .gradient && state.background.gradientID == preset.id) {
                        state.background.kind = .gradient
                        state.background.gradientID = preset.id
                    } content: {
                        RoundedRectangle(cornerRadius: 5)
                            .fill(LinearGradient(colors: preset.colors.map { Color(nsColor: $0) },
                                                 startPoint: .topLeading, endPoint: .bottomTrailing))
                    }
                }
            }
        }
    }

    // MARK: Frame

    private var frameControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                frameChip("None", isSelected: state.background.frame == .none) {
                    state.background.frame = .none
                }
                frameChip("macOS", isSelected: state.background.frame.isMacOS) {
                    state.background.frame = state.background.frame.isDark ? .macOSDark : .macOSLight
                }
                frameChip("Browser", isSelected: state.background.frame.isBrowser) {
                    state.background.frame = state.background.frame.isDark ? .browserDark : .browserLight
                }
            }

            if state.background.frame != .none {
                Picker("", selection: darkBinding) {
                    Text("Light").tag(false)
                    Text("Dark").tag(true)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
        }
    }

    private func frameChip(_ title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .padding(.horizontal, 12)
                .frame(height: 26)
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isSelected ? Color.accentColor : Color.primary.opacity(0.06))
                )
                .foregroundColor(isSelected ? .white : .primary)
        }
        .buttonStyle(.plain)
    }

    // MARK: Helpers

    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .foregroundColor(.secondary)
            .tracking(0.5)
    }

    private func slider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.system(size: 11))
                .frame(width: 58, alignment: .leading)
            Slider(value: value, in: range)
            Text("\(Int((value.wrappedValue / range.upperBound * 100).rounded()))%")
                .font(.system(size: 10, design: .rounded))
                .monospacedDigit()
                .foregroundColor(.secondary)
                .frame(width: 34, alignment: .trailing)
        }
    }

    private var paddingBinding: Binding<Double> {
        Binding(get: { state.background.paddingFraction },
                set: { state.background.paddingFraction = $0 })
    }
    private var cornerBinding: Binding<Double> {
        Binding(get: { state.background.cornerFraction },
                set: { state.background.cornerFraction = $0 })
    }
    private var shadowBinding: Binding<Double> {
        Binding(get: { state.background.shadowStrength },
                set: { state.background.shadowStrength = $0 })
    }
    private var darkBinding: Binding<Bool> {
        Binding(
            get: { state.background.frame.isDark },
            set: { isDark in
                switch state.background.frame {
                case .macOSLight, .macOSDark:
                    state.background.frame = isDark ? .macOSDark : .macOSLight
                case .browserLight, .browserDark:
                    state.background.frame = isDark ? .browserDark : .browserLight
                case .none:
                    break
                }
            })
    }
}

// MARK: - Swatch Button

private struct SwatchButton<Content: View>: View {
    let isSelected: Bool
    let action: () -> Void
    @ViewBuilder let content: () -> Content

    var body: some View {
        Button(action: action) {
            content()
                .frame(width: 30, height: 30)
                .overlay(
                    RoundedRectangle(cornerRadius: 5)
                        .stroke(Color.primary.opacity(0.15), lineWidth: 1)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 5)
                        .stroke(Color.accentColor, lineWidth: isSelected ? 2.5 : 0)
                )
        }
        .buttonStyle(.plain)
    }
}
