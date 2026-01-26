#!/usr/bin/env swift

import AppKit
import Foundation

// Generate a screenshot-themed icon with selection corners

func drawIcon(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()

    let bounds = NSRect(x: 0, y: 0, width: size, height: size)
    let scale = size / 512.0

    // Background - rounded square with gradient
    let bgPath = NSBezierPath(roundedRect: bounds.insetBy(dx: size * 0.02, dy: size * 0.02),
                               xRadius: size * 0.18, yRadius: size * 0.18)

    // Gradient from purple-blue to blue
    let gradient = NSGradient(colors: [
        NSColor(red: 0.4, green: 0.3, blue: 0.9, alpha: 1.0),  // Purple
        NSColor(red: 0.2, green: 0.5, blue: 0.95, alpha: 1.0)  // Blue
    ])!
    gradient.draw(in: bgPath, angle: -45)

    // Inner "screen" area - darker rounded rect
    let screenInset = size * 0.15
    let screenRect = bounds.insetBy(dx: screenInset, dy: screenInset)
    let screenPath = NSBezierPath(roundedRect: screenRect, xRadius: size * 0.08, yRadius: size * 0.08)

    NSColor(white: 0.1, alpha: 0.4).setFill()
    screenPath.fill()

    // Selection corners (the main visual element)
    let cornerLength = size * 0.12
    let cornerThickness = size * 0.035
    let cornerInset = size * 0.22
    let cornerRadius = size * 0.015

    NSColor.white.setFill()

    // Helper to draw a corner
    func drawCorner(x: CGFloat, y: CGFloat, flipH: Bool, flipV: Bool) {
        let hDir: CGFloat = flipH ? -1 : 1
        let vDir: CGFloat = flipV ? -1 : 1

        // Horizontal part
        let hRect = NSRect(
            x: flipH ? x - cornerLength : x,
            y: y - cornerThickness / 2,
            width: cornerLength,
            height: cornerThickness
        )
        NSBezierPath(roundedRect: hRect, xRadius: cornerRadius, yRadius: cornerRadius).fill()

        // Vertical part
        let vRect = NSRect(
            x: x - cornerThickness / 2,
            y: flipV ? y - cornerLength : y,
            width: cornerThickness,
            height: cornerLength
        )
        NSBezierPath(roundedRect: vRect, xRadius: cornerRadius, yRadius: cornerRadius).fill()
    }

    // Four corners
    drawCorner(x: cornerInset, y: cornerInset, flipH: false, flipV: false)  // Bottom-left
    drawCorner(x: size - cornerInset, y: cornerInset, flipH: true, flipV: false)  // Bottom-right
    drawCorner(x: cornerInset, y: size - cornerInset, flipH: false, flipV: true)  // Top-left
    drawCorner(x: size - cornerInset, y: size - cornerInset, flipH: true, flipV: true)  // Top-right

    // Center crosshair (subtle)
    let centerX = size / 2
    let centerY = size / 2
    let crossSize = size * 0.06
    let crossThickness = size * 0.02

    NSColor(white: 1.0, alpha: 0.7).setFill()

    // Horizontal line
    NSBezierPath(roundedRect: NSRect(x: centerX - crossSize, y: centerY - crossThickness/2,
                                      width: crossSize * 2, height: crossThickness),
                 xRadius: crossThickness/2, yRadius: crossThickness/2).fill()

    // Vertical line
    NSBezierPath(roundedRect: NSRect(x: centerX - crossThickness/2, y: centerY - crossSize,
                                      width: crossThickness, height: crossSize * 2),
                 xRadius: crossThickness/2, yRadius: crossThickness/2).fill()

    image.unlockFocus()
    return image
}

func savePNG(image: NSImage, to path: String) {
    guard let tiffData = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiffData),
          let pngData = bitmap.representation(using: .png, properties: [:]) else {
        print("Failed to create PNG for \(path)")
        return
    }
    try? pngData.write(to: URL(fileURLWithPath: path))
}

// Main
let projectDir = FileManager.default.currentDirectoryPath
let iconsetPath = "\(projectDir)/Shotter/Resources/AppIcon.iconset"

// Create iconset directory
try? FileManager.default.removeItem(atPath: iconsetPath)
try? FileManager.default.createDirectory(atPath: iconsetPath, withIntermediateDirectories: true)

// Required sizes for macOS icons
let sizes: [(name: String, size: CGFloat)] = [
    ("icon_16x16", 16),
    ("icon_16x16@2x", 32),
    ("icon_32x32", 32),
    ("icon_32x32@2x", 64),
    ("icon_128x128", 128),
    ("icon_128x128@2x", 256),
    ("icon_256x256", 256),
    ("icon_256x256@2x", 512),
    ("icon_512x512", 512),
    ("icon_512x512@2x", 1024)
]

print("Generating icon images...")
for (name, size) in sizes {
    let image = drawIcon(size: size)
    let path = "\(iconsetPath)/\(name).png"
    savePNG(image: image, to: path)
    print("  Created \(name).png (\(Int(size))x\(Int(size)))")
}

print("\nConverting to icns...")
let icnsPath = "\(projectDir)/Shotter/Resources/AppIcon.icns"

let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", iconsetPath, "-o", icnsPath]
try? task.run()
task.waitUntilExit()

if task.terminationStatus == 0 {
    print("Created AppIcon.icns")
    // Clean up iconset
    try? FileManager.default.removeItem(atPath: iconsetPath)
    print("\nDone! Icon saved to Shotter/Resources/AppIcon.icns")
} else {
    print("Failed to create icns file")
}
