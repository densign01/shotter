import SwiftUI

struct PreferencesView: View {
    @ObservedObject private var prefs = PreferencesManager.shared
    
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
                        Text("Never").tag(Double.infinity)
                    }
                    .frame(width: 120)
                }
                
                Toggle("Launch at login", isOn: $prefs.launchAtLogin)
            } header: {
                Text("General")
            }
            
            Section {
                HStack {
                    Text("Fullscreen")
                    Spacer()
                    Text("⌘⇧3")
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.gray.opacity(0.2))
                        )
                }
                
                HStack {
                    Text("Area")
                    Spacer()
                    Text("⌘⇧4")
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.gray.opacity(0.2))
                        )
                }
            } header: {
                Text("Keyboard Shortcuts")
            } footer: {
                Text("Custom shortcuts coming in a future update.")
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
        .frame(width: 450, height: 350)
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

#Preview {
    PreferencesView()
}
