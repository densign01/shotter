# Shotter — Product Specification

A macOS screenshot utility inspired by CleanShot X, focused on fast capture and annotation workflows.

## Version 1.0 Scope

### Core Features

#### 1. Screenshot Capture
| Mode | Hotkey | Description |
|------|--------|-------------|
| Fullscreen | ⌘⇧3 | Captures entire screen (primary display) |
| Area | ⌘⇧4 | User drags to select rectangular region |

- Captures save to a configurable folder (default: `~/Pictures/Shotter/`)
- Filename format: `Shotter-YYYY-MM-DD-HHMMSS.png`
- PNG format for lossless quality

#### 2. Menu Bar App
- Lives in macOS status bar with a camera/screenshot icon
- Menu items:
  - Capture Fullscreen (⌘⇧3)
  - Capture Area (⌘⇧4)
  - Open Save Folder
  - Preferences...
  - Quit Shotter

#### 3. Quick Access Overlay
After each capture, a floating thumbnail appears in the **bottom-left corner**.

**Overlay behavior:**
- Shows thumbnail preview of captured image
- Auto-dismisses after 5 seconds (configurable)
- Click to expand/preview full size
- Drag thumbnail to other apps (drag & drop)

**Action buttons:**
- **Copy** — Copy image to clipboard
- **Save** — Already saved, but reveals in Finder
- **Annotate** — Opens annotation editor (disabled in v1, shows "Coming Soon")

**Overlay interactions:**
- Hover to pause auto-dismiss timer
- Swipe left to dismiss immediately
- Escape key to dismiss

#### 4. Global Hotkeys
- Replace/intercept standard macOS screenshot shortcuts
- Must request Accessibility permissions
- Configurable in Preferences (v1: hardcoded defaults)

### Preferences (v1)
- Save location (folder picker)
- Overlay auto-dismiss delay (seconds)
- Launch at login toggle

---

## Version 2.0 Pipeline — Annotation Editor

Full-featured annotation tools (design spec for future implementation):

### Annotation Tools
| Tool | Description |
|------|-------------|
| **Arrow** | 4 styles: straight, curved, thick, thin |
| **Rectangle** | Outlined or filled |
| **Ellipse** | Outlined or filled |
| **Line** | Straight line with configurable thickness |
| **Text** | Multiple font styles, sizes, colors |
| **Highlighter** | Semi-transparent marker effect |
| **Pencil** | Freehand drawing with auto-smoothing |
| **Blur** | Gaussian blur for redacting content |
| **Pixelate** | Mosaic effect for redacting (randomized for security) |
| **Spotlight** | Dims entire image except selected region |
| **Counter** | Numbered circles for step-by-step tutorials |
| **Crop** | With aspect ratio lock and edge snapping |

### Editor Features
- Undo/Redo (⌘Z / ⌘⇧Z)
- Layer management (reorder, delete annotations)
- Color picker with recent colors
- Save as PNG or copy to clipboard
- Cancel to discard changes

---

## Technical Architecture

### Platform Requirements
- macOS 14.0+ (Sonoma)
- Apple Silicon + Intel support

### Technology Stack
- **Language:** Swift 5.9+
- **UI Framework:** SwiftUI (primary) + AppKit (system integration)
- **Screen Capture:** ScreenCaptureKit (modern API, macOS 12.3+)
- **Global Hotkeys:** CGEvent tap via Accessibility API
- **Storage:** UserDefaults for preferences, FileManager for screenshots

### Key Components

```
Shotter/
├── ShotterApp.swift           # App entry point
├── MenuBarController.swift    # NSStatusItem management
├── CaptureEngine/
│   ├── CaptureEngine.swift    # ScreenCaptureKit wrapper
│   ├── FullscreenCapture.swift
│   └── AreaCapture.swift      # Selection overlay
├── Overlay/
│   ├── QuickAccessOverlay.swift
│   └── OverlayWindow.swift    # NSPanel for floating window
├── Hotkeys/
│   └── HotkeyManager.swift    # CGEvent tap handling
├── Preferences/
│   ├── PreferencesView.swift
│   └── PreferencesManager.swift
└── Utils/
    ├── FileNaming.swift
    └── Permissions.swift      # Accessibility & screen recording
```

### Permissions Required
1. **Screen Recording** — Required for ScreenCaptureKit
2. **Accessibility** — Required for global hotkey interception

App must gracefully handle permission denied states and guide user to System Preferences.

---

## UI Design Guidelines

### Visual Style
- Native macOS aesthetic
- Supports light and dark mode
- SF Symbols for icons
- Rounded corners on overlays (12pt radius)
- Subtle shadows for floating elements

### Overlay Design
```
┌─────────────────────────────────────┐
│  ┌─────────────┐                    │
│  │             │  [Copy] [Save]     │
│  │  Thumbnail  │  [Annotate ◌]      │
│  │             │                    │
│  └─────────────┘                    │
└─────────────────────────────────────┘
        ↑ Bottom-left corner
```

### Area Selection
- Crosshair cursor when active
- Draggable selection rectangle
- Dimension display (W × H pixels)
- Escape to cancel
- Click without drag = cancel

---

## Success Criteria

### v1 Complete When:
- [ ] App launches to menu bar (no dock icon)
- [ ] ⌘⇧3 captures fullscreen and shows overlay
- [ ] ⌘⇧4 allows area selection and shows overlay
- [ ] Overlay copy button works
- [ ] Overlay save button reveals file in Finder
- [ ] Preferences allow changing save location
- [ ] App handles missing permissions gracefully
- [ ] Works on both Apple Silicon and Intel Macs

---

## Open Questions

1. Multi-display support in v1? (Currently spec'd as primary display only)
2. Should area selection show magnifier for precise positioning?
3. Retina scaling — save at actual pixels or scaled?
