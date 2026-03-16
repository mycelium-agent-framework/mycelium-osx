import SwiftUI

@main
struct MyceliumApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // LSUIElement = true means no dock icon, so we use MenuBarExtra only
        MenuBarExtra {
            MenuBarView()
                .environment(appDelegate.appState)
        } label: {
            Image(systemName: "circle.hexagonpath.fill")
        }
        .menuBarExtraStyle(.menu)

        // Settings window for configuring ring paths, API keys, etc.
        Settings {
            SettingsView()
                .environment(appDelegate.appState)
        }
    }
}

struct MenuBarView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        Group {
            if appState.isConnected {
                Text("Connected to Gemini")
            } else {
                Text("Disconnected")
            }

            Divider()

            if let ring = appState.mountedRingName {
                Text("Ring: \(ring)")
            } else {
                Text("No ring mounted")
            }

            if let channel = appState.activeChannel {
                Text("Channel: \(channel.name)")
            }

            Divider()

            Button("Show Vivian") {
                appState.isPanelVisible = true
                NSApp.activate(ignoringOtherApps: true)
            }
            .keyboardShortcut("v", modifiers: [.command, .shift])

            Button("Settings...") {
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            }
            .keyboardShortcut(",", modifiers: .command)

            Divider()

            Button("Quit Mycelium") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q", modifiers: .command)
        }
    }
}

struct SettingsView: View {
    @Environment(AppState.self) private var appState
    @AppStorage("ring0Path") private var ring0PathString: String = ""
    @AppStorage("geminiApiKey") private var geminiApiKey: String = ""

    var body: some View {
        Form {
            Section("Ring 0 Path") {
                TextField("Path to vivian-core repo", text: $ring0PathString)
                Text("e.g. ~/git/chasemp/vivian-core")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Gemini API Key") {
                SecureField("API Key", text: $geminiApiKey)
                Text("Stored in UserDefaults. Keychain migration planned.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 450, height: 250)
    }
}
