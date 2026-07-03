import SwiftUI

struct PreferencesView: View {
    @ObservedObject private var prefs = PreferencesManager.shared
    @State private var recordingShortcut: ShortcutType?
    
    enum ShortcutType {
        case fullscreen
        case area
        case window
    }
    
    var body: some View {
        Form {
            Section {
                HStack {
                    Text("Save Location:")
                    Spacer()
                    Text(prefs.saveLocation.path)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Button("Choose...") {
                        chooseSaveLocation()
                    }
                }
                
                HStack {
                    Text("Auto-dismiss delay:")
                    Spacer()
                    Picker("", selection: $prefs.overlayAutoDismissDelay) {
                        Text("3 seconds").tag(3.0)
                        Text("5 seconds").tag(5.0)
                        Text("10 seconds").tag(10.0)
                        Text("Never").tag(-1.0)
                    }
                    .frame(width: 120)
                }

                HStack {
                    Text("Overlay position:")
                    Spacer()
                    Picker("", selection: $prefs.overlayPosition) {
                        ForEach(OverlayPosition.allCases, id: \.self) { position in
                            Text(position.displayName).tag(position)
                        }
                    }
                    .frame(width: 120)
                }

                Toggle("Play capture sound", isOn: $prefs.playCaptureSound)

                VStack(alignment: .leading, spacing: 4) {
                    Toggle("Auto-copy to clipboard", isOn: $prefs.autoCopyToClipboard)
                    if !prefs.autoCopyToClipboard {
                        Text("Hold ⌥ Option with your shortcut to copy")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Toggle("Save screenshots automatically", isOn: $prefs.autoSaveScreenshots)

                Toggle("Launch at login", isOn: $prefs.launchAtLogin)
            } header: {
                Text("General")
            }
            
            Section {
                ShortcutRow(
                    label: "Fullscreen",
                    shortcut: $prefs.shortcutFullscreen,
                    isRecording: recordingShortcut == .fullscreen,
                    onStartRecording: { recordingShortcut = .fullscreen },
                    onStopRecording: { recordingShortcut = nil }
                )
                
                VStack(alignment: .leading, spacing: 4) {
                    ShortcutRow(
                        label: "Area / Window",
                        shortcut: $prefs.shortcutArea,
                        isRecording: recordingShortcut == .area,
                        onStartRecording: { recordingShortcut = .area },
                        onStopRecording: { recordingShortcut = nil }
                    )
                    Text("Press Space during selection to toggle window mode")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Toggle("Direct Window", isOn: Binding(
                            get: { prefs.shortcutWindow.isEnabled },
                            set: { enabled in
                                var config = prefs.shortcutWindow
                                config.isEnabled = enabled
                                prefs.shortcutWindow = config
                            }
                        ))
                        Spacer()
                        if prefs.shortcutWindow.isEnabled {
                            if recordingShortcut == .window {
                                ShortcutRecorder(shortcut: $prefs.shortcutWindow, onComplete: { recordingShortcut = nil })
                            } else {
                                ShortcutBadge(shortcut: prefs.shortcutWindow)
                                Button("Change") {
                                    recordingShortcut = .window
                                }
                                .buttonStyle(.borderless)
                                .font(.caption)
                            }
                        }
                    }
                    Text("Optional: Skip area selection and go straight to window mode")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Button("Reset to Defaults") {
                    prefs.shortcutFullscreen = .defaultFullscreen
                    prefs.shortcutArea = .defaultArea
                    prefs.shortcutWindow = .defaultWindow
                }
                .foregroundColor(.secondary)
            } header: {
                Text("Keyboard Shortcuts")
            } footer: {
                Text("Click a shortcut to record a new one. Modifiers + key required.")
                    .foregroundColor(.secondary)
            }
            
            Section {
                Button("Check Screen Recording Permission") {
                    Task {
                        await Permissions.requestScreenRecording()
                    }
                }
                
                Button("Check Accessibility Permission") {
                    Permissions.requestAccessibility()
                }
            } header: {
                Text("Permissions")
            }
        }
        .formStyle(.grouped)
        .frame(width: 480, height: 480)
        .alert("Launch at Login Failed", isPresented: Binding(
            get: { prefs.launchAtLoginErrorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    prefs.clearLaunchAtLoginError()
                }
            }
        )) {
            Button("OK", role: .cancel) {
                prefs.clearLaunchAtLoginError()
            }
        } message: {
            Text(prefs.launchAtLoginErrorMessage ?? "Shotter could not update its launch-at-login registration.")
        }
    }
    
    private func chooseSaveLocation() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = "Choose"
        
        if panel.runModal() == .OK, let url = panel.url {
            prefs.saveLocation = url
        }
    }
}

struct ShortcutRow: View {
    let label: String
    @Binding var shortcut: ShortcutConfig
    let isRecording: Bool
    let onStartRecording: () -> Void
    let onStopRecording: () -> Void
    
    var body: some View {
        HStack {
            Text(label)
            Spacer()
            
            if isRecording {
                ShortcutRecorder(shortcut: $shortcut, onComplete: onStopRecording)
            } else {
                ShortcutBadge(shortcut: shortcut)
                Button("Change") {
                    onStartRecording()
                }
                .buttonStyle(.borderless)
                .font(.caption)
            }
        }
    }
}

struct ShortcutBadge: View {
    let shortcut: ShortcutConfig
    
    var body: some View {
        Text(shortcut.displayString)
            .foregroundColor(shortcut.isEnabled ? .primary : .secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.gray.opacity(0.2))
            )
    }
}

struct ShortcutRecorder: View {
    @Binding var shortcut: ShortcutConfig
    let onComplete: () -> Void
    
    @State private var recordedKeyCode: Int?
    @State private var recordedModifiers: Int?
    
    var body: some View {
        HStack {
            Text("Press shortcut...")
                .foregroundColor(.orange)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color.orange, lineWidth: 1)
                )
            
            Button("Cancel") {
                onComplete()
            }
            .buttonStyle(.borderless)
            .font(.caption)
        }
        .background(
            ShortcutRecorderHelper(onKeyEvent: { keyCode, modifiers in
                // Require at least one modifier
                let flags = CGEventFlags(rawValue: UInt64(modifiers))
                let hasModifier = flags.contains(.maskCommand) ||
                                  flags.contains(.maskShift) ||
                                  flags.contains(.maskAlternate) ||
                                  flags.contains(.maskControl)
                
                if hasModifier {
                    shortcut = ShortcutConfig(
                        keyCode: keyCode,
                        modifiers: modifiers,
                        isEnabled: true
                    )
                    onComplete()
                }
            })
        )
    }
}

struct ShortcutRecorderHelper: NSViewRepresentable {
    let onKeyEvent: (Int, Int) -> Void
    
    func makeNSView(context: Context) -> ShortcutRecorderView {
        let view = ShortcutRecorderView()
        view.onKeyEvent = onKeyEvent
        return view
    }
    
    func updateNSView(_ nsView: ShortcutRecorderView, context: Context) {
        nsView.onKeyEvent = onKeyEvent
    }
}

class ShortcutRecorderView: NSView {
    var onKeyEvent: ((Int, Int) -> Void)?
    
    private var eventMonitor: Any?
    
    override var acceptsFirstResponder: Bool { true }
    
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        
        if window != nil {
            // Start monitoring for key events
            eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                let keyCode = Int(event.keyCode)
                
                // Convert NSEvent modifiers to CGEventFlags
                var cgFlags: UInt64 = 0
                if event.modifierFlags.contains(.command) { cgFlags |= CGEventFlags.maskCommand.rawValue }
                if event.modifierFlags.contains(.shift) { cgFlags |= CGEventFlags.maskShift.rawValue }
                if event.modifierFlags.contains(.option) { cgFlags |= CGEventFlags.maskAlternate.rawValue }
                if event.modifierFlags.contains(.control) { cgFlags |= CGEventFlags.maskControl.rawValue }
                
                self?.onKeyEvent?(keyCode, Int(cgFlags))
                return nil  // Consume the event
            }
        } else {
            // Stop monitoring
            if let monitor = eventMonitor {
                NSEvent.removeMonitor(monitor)
                eventMonitor = nil
            }
        }
    }
    
    deinit {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }
}

#Preview {
    PreferencesView()
}
