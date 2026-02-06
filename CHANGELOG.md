# Changelog

All notable changes to Shotter will be documented in this file.

Format based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [1.5.0] - 2026-02-05

### Added

- Crop tool in annotation editor (Enter to apply, Escape to cancel)
- Eraser tool to remove annotations with a click (shortcut: X)
- Drag-me bar at bottom of annotation editor to drag images into other apps
- Close prompt now detects cropped-but-unsaved state

## [1.4.0] - 2026-01-28

### Added

- Option to disable automatic screenshot saving in Preferences
- Keyboard shortcut hint when auto-copy is disabled

### Changed

- Cleaner About dialog layout with GitHub button

## [1.3.0] - 2026-01-27

### Added

- Clipboard now includes file URL for terminal app compatibility (Ghostty, iTerm2, etc.)
- Build number shown in About dialog for easier debugging

### Fixed

- Screenshot overlay no longer shows square corners at edges (proper layer masking)
- Clipboard copy now works even when save to disk fails (graceful fallback)
- Arrow and line annotations now move correctly when dragged (previously only selection box moved)
- Window capture uses correct display scale factor on multi-monitor setups
- Hotkeys automatically recover when system disables event tap due to timeout
- "Show in Finder" button disabled when screenshot save failed
- Window selection/highlighting works correctly on vertically stacked monitors
- Removed force unwraps on CIFilter creation that could cause crashes

### Changed

- Cached CIContext for blur rendering (performance improvement with multiple blur regions)
- Arrows and lines no longer show resize handles (only support moving, not resizing)
- Screenshot save now happens before clipboard copy (ensures file URL is available)
