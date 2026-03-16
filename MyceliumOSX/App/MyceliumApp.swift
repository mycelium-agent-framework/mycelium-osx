import SwiftUI

@main
struct MyceliumApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environment(appDelegate.appState)
        } label: {
            Image(systemName: "circle.hexagonpath.fill")
        }
        .menuBarExtraStyle(.menu)
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
                SettingsWindowController.shared.show(appState: appState)
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
