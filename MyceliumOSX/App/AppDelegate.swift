import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let appState = AppState()
    private var floatingPanel: FloatingPanel?
    private var hotkeyManager: GlobalHotkeyManager?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Preload all Keychain keys into memory (one prompt instead of many)
        KeychainManager.preloadAll()

        setupFloatingPanel()
        setupHotkey()

        if appState.isConfigured {
            loadConfiguration()
        } else {
            SettingsWindowController.shared.show(appState: appState)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotkeyManager?.stop()
        appState.endSession()
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
            appState.isPanelVisible = false
            if appState.mode == .voice {
                appState.stopVoiceMode()
            }
            return
        }

        simulateMediaPlayPause()
        appState.isPanelVisible = true
        NSApp.activate(ignoringOtherApps: true)
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

        // Auto-mount first allowed ring using user-configured path from Settings
        if let manifest = appState.manifest,
           let pop = manifest.pops.first(where: { $0.deviceId == appState.deviceId }),
           let firstRingName = pop.allowedRings.first {
            let userPath = defaults.string(forKey: "ringPath.\(firstRingName)") ?? ""
            if !userPath.isEmpty, FileManager.default.fileExists(atPath: userPath) {
                appState.mountRing(path: URL(fileURLWithPath: userPath), name: firstRingName)
            }
        }

        // Voice is configured automatically by mountRing → configureVoiceForCurrentRing
    }
}
