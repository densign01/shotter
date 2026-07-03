import AppKit

// MARK: - Background Kind

/// The fill behind the screenshot when beautify is active.
enum BackgroundKind: String, Codable {
    case none      // transparent (no fill) — useful with a frame/shadow for overlays
    case solid
    case gradient
}

/// Optional window chrome drawn around the screenshot.
enum FrameStyle: String, Codable {
    case none
    case macOSLight
    case macOSDark
    case browserLight
    case browserDark

    var isMacOS: Bool { self == .macOSLight || self == .macOSDark }
    var isBrowser: Bool { self == .browserLight || self == .browserDark }
    var isDark: Bool { self == .macOSDark || self == .browserDark }

    /// Title bar height in screenshot-point space (0 when no frame).
    func titleBarHeight(imageWidth: CGFloat) -> CGFloat {
        switch self {
        case .none:
            return 0
        case .macOSLight, .macOSDark:
            return max(26, imageWidth * 0.028)
        case .browserLight, .browserDark:
            return max(40, imageWidth * 0.05)
        }
    }

    var barColor: NSColor {
        isDark ? NSColor(hex: "#2B2B2E") : NSColor(hex: "#EDEDED")
    }
}

// MARK: - Gradient Presets

struct GradientPreset: Identifiable, Equatable {
    let id: String
    let name: String
    let hexStops: [String]

    var colors: [NSColor] { hexStops.map { NSColor(hex: $0) } }

    static let all: [GradientPreset] = [
        GradientPreset(id: "sunset", name: "Sunset", hexStops: ["#FF7E5F", "#FEB47B"]),
        GradientPreset(id: "grape", name: "Grape", hexStops: ["#667EEA", "#764BA2"]),
        GradientPreset(id: "ocean", name: "Ocean", hexStops: ["#2193B0", "#6DD5ED"]),
        GradientPreset(id: "mint", name: "Mint", hexStops: ["#43E97B", "#38F9D7"]),
        GradientPreset(id: "peach", name: "Peach", hexStops: ["#FFD3A5", "#FD6585"]),
        GradientPreset(id: "sky", name: "Sky", hexStops: ["#A1C4FD", "#C2E9FB"]),
        GradientPreset(id: "rose", name: "Rose", hexStops: ["#F4C4F3", "#FC67FA"]),
        GradientPreset(id: "slate", name: "Slate", hexStops: ["#3A3D40", "#181A1B"]),
    ]

    static func preset(id: String) -> GradientPreset {
        all.first(where: { $0.id == id }) ?? all[0]
    }
}

/// Curated solid background colors (hex).
enum SolidPreset {
    static let hexes: [String] = [
        "#FFFFFF", "#F2F2F7", "#D9DDE3", "#1C1C1E", "#000000",
        "#2563EB", "#059669", "#DC2626", "#7C3AED", "#EA580C",
    ]
}

// MARK: - Background Style

/// Global "beautify" style for the editor — a presentation frame composited
/// around the annotated screenshot. All stored fields are primitives so the
/// struct is trivially Codable for persistence.
struct BackgroundStyle: Codable, Equatable {
    var kind: BackgroundKind = .none
    var solidHex: String = "#F2F2F7"
    var gradientID: String = "sunset"
    /// Padding as a fraction of the screenshot's larger dimension (0…0.22).
    var paddingFraction: Double = 0.07
    /// Corner radius as a fraction of the screenshot's smaller dimension (0…0.08).
    var cornerFraction: Double = 0.022
    /// Drop-shadow strength (0 = off … 1 = strong).
    var shadowStrength: Double = 0.35
    var frame: FrameStyle = .none

    var solidColor: NSColor { NSColor(hex: solidHex) }
    var gradient: GradientPreset { GradientPreset.preset(id: gradientID) }

    /// Whether beautify deviates from the raw screenshot at all.
    var isActive: Bool {
        kind != .none || paddingFraction > 0.001 || frame != .none || shadowStrength > 0.001
    }

    /// The default, inactive style — identical output to a raw screenshot.
    static let disabled = BackgroundStyle(
        kind: .none, paddingFraction: 0, cornerFraction: 0, shadowStrength: 0, frame: .none
    )

    func titleBarHeight(imageWidth: CGFloat) -> CGFloat {
        isActive ? frame.titleBarHeight(imageWidth: imageWidth) : 0
    }
}

// MARK: - Persistence

/// Remembers the last-used beautify style across captures (like CleanShot).
enum BackgroundStore {
    private static let key = "annotationBackgroundStyle"

    static func load() -> BackgroundStyle {
        guard let data = UserDefaults.standard.data(forKey: key),
              let style = try? JSONDecoder().decode(BackgroundStyle.self, from: data) else {
            return .disabled
        }
        return style
    }

    static func save(_ style: BackgroundStyle) {
        if let data = try? JSONEncoder().encode(style) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}

// MARK: - Layout

/// Resolved geometry for one beautify render, in the target coordinate space
/// (view points for the live canvas, or output points for export).
struct BeautifyLayout {
    let canvasRect: CGRect   // full beautified area (background fill)
    let windowRect: CGRect   // the card (screenshot + title bar) — shadow + rounding
    let contentRect: CGRect  // the screenshot area (annotation coordinate anchor)
    let scale: CGFloat       // contentRect.width / imageSize.width
    let cornerRadius: CGFloat
    let titleBarHeight: CGFloat
}

/// Computes beautify geometry that aspect-fits the whole composited canvas into
/// `viewSize`. When the style is inactive this degenerates to a plain
/// aspect-fit of the screenshot (identical to `annotationImageRect`).
func beautifyLayout(viewSize: CGSize, imageSize: CGSize, style: BackgroundStyle) -> BeautifyLayout {
    guard imageSize.width > 0, imageSize.height > 0,
          viewSize.width > 0, viewSize.height > 0 else {
        return BeautifyLayout(canvasRect: .zero, windowRect: .zero, contentRect: .zero,
                              scale: 1, cornerRadius: 0, titleBarHeight: 0)
    }

    let active = style.isActive
    let refDim = max(imageSize.width, imageSize.height)
    let padPts = active ? CGFloat(style.paddingFraction) * refDim : 0
    let titlePts = style.titleBarHeight(imageWidth: imageSize.width)

    let canvasW = imageSize.width + 2 * padPts
    let canvasH = imageSize.height + titlePts + 2 * padPts

    let s = min(viewSize.width / canvasW, viewSize.height / canvasH)
    let frameW = canvasW * s
    let frameH = canvasH * s
    let ox = (viewSize.width - frameW) / 2
    let oy = (viewSize.height - frameH) / 2
    let pad = padPts * s

    let canvasRect = CGRect(x: ox, y: oy, width: frameW, height: frameH)
    let contentRect = CGRect(x: ox + pad, y: oy + pad,
                             width: imageSize.width * s, height: imageSize.height * s)
    let windowRect = CGRect(x: ox + pad, y: oy + pad,
                            width: imageSize.width * s,
                            height: (imageSize.height + titlePts) * s)
    let corner = active ? CGFloat(style.cornerFraction) * min(imageSize.width, imageSize.height) * s : 0

    return BeautifyLayout(
        canvasRect: canvasRect,
        windowRect: windowRect,
        contentRect: contentRect,
        scale: s,
        cornerRadius: corner,
        titleBarHeight: titlePts * s
    )
}

// MARK: - Hex Color

extension NSColor {
    /// Creates a color from a `#RRGGBB` or `#RRGGBBAA` hex string. Falls back to
    /// gray on malformed input.
    convenience init(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        var value: UInt64 = 0
        Scanner(string: s).scanHexInt64(&value)

        let r, g, b, a: CGFloat
        if s.count == 8 {
            r = CGFloat((value >> 24) & 0xFF) / 255
            g = CGFloat((value >> 16) & 0xFF) / 255
            b = CGFloat((value >> 8) & 0xFF) / 255
            a = CGFloat(value & 0xFF) / 255
        } else {
            r = CGFloat((value >> 16) & 0xFF) / 255
            g = CGFloat((value >> 8) & 0xFF) / 255
            b = CGFloat(value & 0xFF) / 255
            a = 1
        }
        self.init(srgbRed: r, green: g, blue: b, alpha: a)
    }

    var hexString: String {
        guard let c = usingColorSpace(.sRGB) else { return "#000000" }
        let r = Int((c.redComponent * 255).rounded())
        let g = Int((c.greenComponent * 255).rounded())
        let b = Int((c.blueComponent * 255).rounded())
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}
