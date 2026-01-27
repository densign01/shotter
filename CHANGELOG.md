# Changelog

All notable changes to Shotter will be documented in this file.

Format based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Fixed

- Screenshot overlay no longer shows square corners at edges (proper layer masking)
- Arrow and line annotations now move correctly when dragged (previously only selection box moved)
- Window capture uses correct display scale factor on multi-monitor setups
- Hotkeys automatically recover when system disables event tap due to timeout
- "Show in Finder" button disabled when screenshot save failed
- Window selection/highlighting works correctly on vertically stacked monitors
- Removed force unwraps on CIFilter creation that could cause crashes

### Changed

- Cached CIContext for blur rendering (performance improvement with multiple blur regions)
- Arrows and lines no longer show resize handles (only support moving, not resizing)
