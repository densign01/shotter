# Shotter

A macOS screenshot utility inspired by CleanShot X.

**Status:** In Development

## Features (v1)

- 📸 **Fullscreen capture** — ⌘⇧3 (captures display at cursor)
- ✂️ **Area capture** — ⌘⇧4 (works across multiple displays)
- 🪟 **Window capture** — ⌘⇧5 (click any window to capture it)
- 🖥️ **Multi-display support** — Capture any connected display from menu
- 🔊 **Capture sound** — Subtle shutter sound feedback (can be disabled)
- 🎯 **Quick Access Overlay** — Floating thumbnail with copy/save actions
- 📁 **Custom save location** — Configure where screenshots go
- 🖥️ **Menu bar app** — Lives in your status bar

## Requirements

- macOS 14.0+ (Sonoma)
- Screen Recording permission
- Accessibility permission (for global hotkeys)

## Installation

```bash
# Clone the repo
git clone https://github.com/densign01/shotter.git
cd shotter

# Build release
swift build -c release

# Copy to app bundle
cp .build/release/Shotter Shotter.app/Contents/MacOS/

# Run
./Shotter.app/Contents/MacOS/Shotter
```

On first run, macOS will prompt for **Screen Recording** and **Accessibility** permissions. Grant both in System Settings → Privacy & Security.

To quit: Click the camera icon in the menu bar → Quit, or `pkill -f Shotter.app`

## Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| ⌘⇧3 | Capture fullscreen (current display) |
| ⌘⇧4 | Capture selected area |
| ⌘⇧5 | Capture window (click to select) |

## Building

```bash
# Build with Swift Package Manager
swift build

# Or build release
swift build -c release
```

## Roadmap

- [x] Fullscreen capture
- [x] Area capture  
- [x] Window capture
- [x] Multi-display support
- [x] Capture sound effect
- [x] Quick Access Overlay
- [x] Menu bar integration
- [ ] **v2:** Annotation editor (arrows, shapes, text, blur, etc.)

## License

Private — All rights reserved.
