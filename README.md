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
