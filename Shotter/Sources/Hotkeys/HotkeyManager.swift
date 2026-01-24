import AppKit
import Carbon

class HotkeyManager {
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    
    private let onFullscreen: () -> Void
    private let onArea: () -> Void
    
    init(onFullscreen: @escaping () -> Void, onArea: @escaping () -> Void) {
        self.onFullscreen = onFullscreen
        self.onArea = onArea
        
        setupEventTap()
    }
    
    deinit {
        removeEventTap()
    }
    
    private func setupEventTap() {
        // Check accessibility permissions
        guard Permissions.checkAccessibility() else {
            print("Accessibility permission not granted - hotkeys disabled")
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
            print("Failed to create event tap")
            return
        }
        
        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        
        if let source = runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
        }
    }
    
    private func handleEvent(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        guard type == .keyDown else {
            return Unmanaged.passRetained(event)
        }
        
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let flags = event.flags
        
        // Check for Command + Shift modifier
        let hasCommandShift = flags.contains([.maskCommand, .maskShift]) &&
                             !flags.contains(.maskControl) &&
                             !flags.contains(.maskAlternate)
        
        guard hasCommandShift else {
            return Unmanaged.passRetained(event)
        }
        
        // Key code 20 = "3", Key code 21 = "4"
        switch keyCode {
        case 20: // ⌘⇧3 - Fullscreen
            DispatchQueue.main.async {
                self.onFullscreen()
            }
            return nil // Consume the event
            
        case 21: // ⌘⇧4 - Area
            DispatchQueue.main.async {
                self.onArea()
            }
            return nil // Consume the event
            
        default:
            return Unmanaged.passRetained(event)
        }
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
