import AppKit
import Carbon
import os.log

private let logger = Logger(subsystem: "com.densign.shotter", category: "Hotkeys")

class HotkeyManager {
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var shortcutObserver: NSObjectProtocol?
    
    private let onFullscreen: () -> Void
    private let onArea: () -> Void
    private let onWindow: () -> Void
    
    // Cache shortcuts for performance
    private var fullscreenShortcut: ShortcutConfig
    private var areaShortcut: ShortcutConfig
    private var windowShortcut: ShortcutConfig
    
    init(
        onFullscreen: @escaping () -> Void,
        onArea: @escaping () -> Void,
        onWindow: @escaping () -> Void
    ) {
        self.onFullscreen = onFullscreen
        self.onArea = onArea
        self.onWindow = onWindow
        
        // Load initial shortcuts
        let prefs = PreferencesManager.shared
        self.fullscreenShortcut = prefs.shortcutFullscreen
        self.areaShortcut = prefs.shortcutArea
        self.windowShortcut = prefs.shortcutWindow
        
        setupEventTap()
        observeShortcutChanges()
    }
    
    deinit {
        removeEventTap()
        if let observer = shortcutObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }
    
    private func observeShortcutChanges() {
        shortcutObserver = NotificationCenter.default.addObserver(
            forName: .shortcutsDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.reloadShortcuts()
        }
    }
    
    private func reloadShortcuts() {
        let prefs = PreferencesManager.shared
        fullscreenShortcut = prefs.shortcutFullscreen
        areaShortcut = prefs.shortcutArea
        windowShortcut = prefs.shortcutWindow
        logger.info("Shortcuts reloaded")
    }
    
    private func setupEventTap() {
        // Check accessibility permissions
        guard Permissions.checkAccessibility() else {
            logger.warning("Accessibility permission not granted - hotkeys disabled")
            return
        }
        
        // Create event tap for key down events
        let eventMask: CGEventMask = (1 << CGEventType.keyDown.rawValue)
        
        // We need to use a callback that can capture self
        let callback: CGEventTapCallBack = { proxy, type, event, refcon in
            guard let refcon = refcon else { return Unmanaged.passRetained(event) }
            let manager = Unmanaged<HotkeyManager>.fromOpaque(refcon).takeUnretainedValue()
            return manager.handleEvent(proxy: proxy, type: type, event: event)
        }
        
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: callback,
            userInfo: refcon
        ) else {
            logger.error("Failed to create event tap - hotkeys will not work")
            return
        }
        
        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        
        if let source = runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
            logger.info("Hotkey event tap registered successfully")
        }
    }
    
    private func handleEvent(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        guard type == .keyDown else {
            return Unmanaged.passRetained(event)
        }
        
        let keyCode = Int(event.getIntegerValueField(.keyboardEventKeycode))
        let flags = event.flags
        
        // Check fullscreen shortcut
        if fullscreenShortcut.isEnabled && matchesShortcut(keyCode: keyCode, flags: flags, shortcut: fullscreenShortcut) {
            DispatchQueue.main.async {
                self.onFullscreen()
            }
            return nil // Consume the event
        }
        
        // Check area shortcut
        if areaShortcut.isEnabled && matchesShortcut(keyCode: keyCode, flags: flags, shortcut: areaShortcut) {
            DispatchQueue.main.async {
                self.onArea()
            }
            return nil // Consume the event
        }
        
        // Check window shortcut (only if enabled - disabled by default)
        if windowShortcut.isEnabled && matchesShortcut(keyCode: keyCode, flags: flags, shortcut: windowShortcut) {
            DispatchQueue.main.async {
                self.onWindow()
            }
            return nil // Consume the event
        }
        
        return Unmanaged.passRetained(event)
    }
    
    private func matchesShortcut(keyCode: Int, flags: CGEventFlags, shortcut: ShortcutConfig) -> Bool {
        guard keyCode == shortcut.keyCode else { return false }
        
        let requiredFlags = CGEventFlags(rawValue: UInt64(shortcut.modifiers))
        
        // Check that all required modifiers are present
        let hasCommand = flags.contains(.maskCommand) == requiredFlags.contains(.maskCommand)
        let hasShift = flags.contains(.maskShift) == requiredFlags.contains(.maskShift)
        let hasOption = flags.contains(.maskAlternate) == requiredFlags.contains(.maskAlternate)
        let hasControl = flags.contains(.maskControl) == requiredFlags.contains(.maskControl)
        
        return hasCommand && hasShift && hasOption && hasControl
    }
    
    private func removeEventTap() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
    }
}
