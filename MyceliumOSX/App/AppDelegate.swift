import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let appState = AppState()
    private var floatingPanel: FloatingPanel?
    private var hotkeyManager: GlobalHotkeyManager?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupFloatingPanel()
        setupHotkey()

        if appState.isConfigured {
            loadConfiguration()
        } else {
            // First launch — show settings
            SettingsWindowController.shared.show(appState: appState)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotkeyManager?.stop()
        appState.endVoiceSession()
    }

    // MARK: - Floating Panel

    private func setupFloatingPanel() {
        let panel = FloatingPanel()
        let hostingView = NSHostingView(
            rootView: FloatingPanelView()
                .environment(appState)
        )
        panel.contentView = hostingView
        self.floatingPanel = panel

        Task { @MainActor in
            observePanelVisibility()
        }
    }

    @MainActor
    private func observePanelVisibility() {
        withObservationTracking {
            _ = appState.isPanelVisible
        } onChange: {
            Task { @MainActor [weak self] in
                guard let self else { return }
                if self.appState.isPanelVisible {
                    self.showPanel()
                } else {
                    self.hidePanel()
                }
                self.observePanelVisibility()
            }
        }
    }

    private func showPanel() {
        floatingPanel?.orderFrontRegardless()
        floatingPanel?.makeKey()
    }

    private func hidePanel() {
        floatingPanel?.orderOut(nil)
    }

    // MARK: - Global Hotkey

    private func setupHotkey() {
        hotkeyManager = GlobalHotkeyManager { [weak self] in
            Task { @MainActor in
                self?.handleHotkeyActivation()
            }
        }
        hotkeyManager?.start()
    }

    @MainActor
    private func handleHotkeyActivation() {
        if appState.isPanelVisible {
            // Dismiss panel and stop listening
            appState.isPanelVisible = false
            appState.isListening = false
            return
        }

        // Pause media
        simulateMediaPlayPause()

        // Show panel and start listening
        appState.isPanelVisible = true
        NSApp.activate(ignoringOtherApps: true)
        appState.isListening = true
    }

    private func simulateMediaPlayPause() {
        let keyCode: UInt32 = 16 // NX_KEYTYPE_PLAY

        if let event = NSEvent.otherEvent(
            with: .systemDefined, location: .zero, modifierFlags: [],
            timestamp: 0, windowNumber: 0, context: nil,
            subtype: 8, data1: Int((keyCode << 16) | (0xa << 8)), data2: -1
        ) {
            event.cgEvent?.post(tap: .cghidEventTap)
        }

        if let event = NSEvent.otherEvent(
            with: .systemDefined, location: .zero, modifierFlags: [],
            timestamp: 0, windowNumber: 0, context: nil,
            subtype: 8, data1: Int((keyCode << 16) | (0xb << 8)), data2: -1
        ) {
            event.cgEvent?.post(tap: .cghidEventTap)
        }
    }

    // MARK: - Configuration

    @MainActor
    private func loadConfiguration() {
        let defaults = UserDefaults.standard

        // Load Ring 0
        guard let pathString = defaults.string(forKey: "ring0Path"),
              !pathString.isEmpty else {
            print("[AppDelegate] No ring0Path configured. Open Settings.")
            return
        }

        let expandedPath = NSString(string: pathString).expandingTildeInPath
        let ring0URL = URL(fileURLWithPath: expandedPath)
        appState.bootstrap(ring0Path: ring0URL)

        // Auto-mount first allowed ring
        if let manifest = appState.manifest,
           let pop = manifest.pops.first(where: { $0.deviceId == appState.deviceId }),
           let firstRingName = pop.allowedRings.first,
           let ring = manifest.rings.first(where: { $0.name == firstRingName }),
           let hint = ring.localPathHint {
            let ringPath = URL(fileURLWithPath: NSString(string: hint).expandingTildeInPath)
            if FileManager.default.fileExists(atPath: ringPath.path) {
                appState.mountRing(path: ringPath, name: firstRingName)
            }
        }

        // Configure voice with API key
        let apiKey = defaults.string(forKey: "geminiApiKey") ?? ""
        if !apiKey.isEmpty {
            appState.configureVoice(apiKey: apiKey)
        }
    }
}
