import AppKit
import SwiftUI

/// Manages a standalone NSWindow for settings (works reliably with LSUIElement apps).
@MainActor
final class SettingsWindowController {
    static let shared = SettingsWindowController()

    private var window: NSWindow?

    func show(appState: AppState) {
        if let existing = window, existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let settingsView = SettingsView(onSave: { [weak self] in
            self?.window?.close()
            // Reload configuration after save
            appState.reloadConfiguration()
        })
        .environment(appState)

        let hostingView = NSHostingView(rootView: settingsView)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 340),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Mycelium Settings"
        window.contentView = hostingView
        window.center()
        window.isReleasedWhenClosed = false

        self.window = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

struct SettingsView: View {
    @Environment(AppState.self) private var appState
    @AppStorage("ring0Path") private var ring0PathString: String = ""
    @AppStorage("geminiApiKey") private var geminiApiKey: String = ""

    var onSave: (() -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("Ring 0 (vivian-core)") {
                    HStack {
                        TextField("Path to vivian-core repo", text: $ring0PathString)
                            .textFieldStyle(.roundedBorder)
                        Button("Browse...") {
                            browseForDirectory()
                        }
                    }
                    Text("The git repo containing SOUL.md and manifest.json")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if !ring0PathString.isEmpty {
                        let valid = isValidRing0(ring0PathString)
                        HStack(spacing: 4) {
                            Image(systemName: valid ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .foregroundStyle(valid ? .green : .red)
                            Text(valid ? "SOUL.md and manifest.json found" : "Missing SOUL.md or manifest.json")
                                .font(.caption)
                                .foregroundColor(valid ? .secondary : .red)
                        }
                    }
                }

                Section("Gemini API Key") {
                    SecureField("API Key", text: $geminiApiKey)
                        .textFieldStyle(.roundedBorder)
                    Text("Get one at makersuite.google.com/app/apikey")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button("Save & Connect") {
                    onSave?()
                }
                .buttonStyle(.borderedProminent)
                .disabled(ring0PathString.isEmpty || geminiApiKey.isEmpty)
            }
            .padding()
        }
        .frame(width: 500, height: 340)
    }

    private func browseForDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Select the vivian-core repository directory"

        if panel.runModal() == .OK, let url = panel.url {
            ring0PathString = url.path
        }
    }

    private func isValidRing0(_ path: String) -> Bool {
        let expanded = NSString(string: path).expandingTildeInPath
        let fm = FileManager.default
        return fm.fileExists(atPath: expanded + "/SOUL.md")
            && fm.fileExists(atPath: expanded + "/manifest.json")
    }
}
