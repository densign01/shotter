import AppKit
import Carbon
import os.log

private let logger = Logger(subsystem: "com.densign.shotter", category: "Hotkeys")

class HotkeyManager {
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var shortcutObserver: NSObjectProtocol?
    
    private let onFullscreen: (Bool) -> Void  // Bool = directCopy (Option held)
    private let onArea: (Bool) -> Void
    private let onWindow: (Bool) -> Void
    
    // Cache shortcuts for performance
    private var fullscreenShortcut: ShortcutConfig
    private var areaShortcut: ShortcutConfig
    private var windowShortcut: ShortcutConfig
    
    init(
        onFullscreen: @escaping (Bool) -> Void,
        onArea: @escaping (Bool) -> Void,
        onWindow: @escaping (Bool) -> Void
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
        
        // Create event tap for key down events and tap disable notifications
        let eventMask: CGEventMask = (1 << CGEventType.keyDown.rawValue) |
                                      (1 << CGEventType.tapDisabledByTimeout.rawValue) |
                                      (1 << CGEventType.tapDisabledByUserInput.rawValue)
        
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
        // Handle tap being disabled by system - re-enable it
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            logger.warning("Event tap was disabled by system, re-enabling...")
            if let tap = eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passRetained(event)
        }

        guard type == .keyDown else {
            return Unmanaged.passRetained(event)
        }
        
        let keyCode = Int(event.getIntegerValueField(.keyboardEventKeycode))
        let flags = event.flags
        let optionHeld = flags.contains(.maskAlternate)

        // Check fullscreen shortcut (allow Option as extra modifier for direct-copy)
        if fullscreenShortcut.isEnabled && matchesShortcut(keyCode: keyCode, flags: flags, shortcut: fullscreenShortcut, allowExtraOption: true) {
            DispatchQueue.main.async {
                self.onFullscreen(optionHeld)
            }
            return nil // Consume the event
        }

        // Check area shortcut
        if areaShortcut.isEnabled && matchesShortcut(keyCode: keyCode, flags: flags, shortcut: areaShortcut, allowExtraOption: true) {
            DispatchQueue.main.async {
                self.onArea(optionHeld)
            }
            return nil // Consume the event
        }

        // Check window shortcut (only if enabled - disabled by default)
        if windowShortcut.isEnabled && matchesShortcut(keyCode: keyCode, flags: flags, shortcut: windowShortcut, allowExtraOption: true) {
            DispatchQueue.main.async {
                self.onWindow(optionHeld)
            }
            return nil // Consume the event
        }
        
        return Unmanaged.passRetained(event)
    }
    
    private func matchesShortcut(keyCode: Int, flags: CGEventFlags, shortcut: ShortcutConfig, allowExtraOption: Bool = false) -> Bool {
        guard keyCode == shortcut.keyCode else { return false }

        let requiredFlags = CGEventFlags(rawValue: UInt64(shortcut.modifiers))

        // Check that all required modifiers are present
        let hasCommand = flags.contains(.maskCommand) == requiredFlags.contains(.maskCommand)
        let hasShift = flags.contains(.maskShift) == requiredFlags.contains(.maskShift)
        let hasControl = flags.contains(.maskControl) == requiredFlags.contains(.maskControl)

        // For Option: if allowExtraOption is true, allow it to be held even if not required
        let hasOption: Bool
        if allowExtraOption && !requiredFlags.contains(.maskAlternate) {
            // Option can be either pressed or not pressed
            hasOption = true
        } else {
            hasOption = flags.contains(.maskAlternate) == requiredFlags.contains(.maskAlternate)
        }

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
