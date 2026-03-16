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
        loadRing0()
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotkeyManager?.stop()
        // Generate handoff spore on quit
        Task { @MainActor in
            generateHandoffSpore()
        }
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

        // Observe panel visibility
        Task { @MainActor in
            // Poll-free observation via withObservationTracking
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
            return
        }

        // Simulate media Play/Pause key to pause any playing media
        simulateMediaPlayPause()

        appState.isPanelVisible = true
        NSApp.activate(ignoringOtherApps: true)

        // Start listening
        appState.isListening = true
    }

    private func simulateMediaPlayPause() {
        // NX_KEYTYPE_PLAY = 16
        let keyCode: UInt32 = 16

        // Key down
        if let event = NSEvent.otherEvent(
            with: .systemDefined,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            subtype: 8, // NX_SUBTYPE_AUX_CONTROL_BUTTONS
            data1: Int((keyCode << 16) | (0xa << 8)), // key down
            data2: -1
        ) {
            event.cgEvent?.post(tap: .cghidEventTap)
        }

        // Key up
        if let event = NSEvent.otherEvent(
            with: .systemDefined,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            subtype: 8,
            data1: Int((keyCode << 16) | (0xb << 8)), // key up
            data2: -1
        ) {
            event.cgEvent?.post(tap: .cghidEventTap)
        }
    }

    // MARK: - Ring Loading

    @MainActor
    private func loadRing0() {
        guard let pathString = UserDefaults.standard.string(forKey: "ring0Path"),
              !pathString.isEmpty else { return }

        let expandedPath = NSString(string: pathString).expandingTildeInPath
        let url = URL(fileURLWithPath: expandedPath)
        appState.bootstrap(ring0Path: url)

        // Auto-mount the first allowed ring for this PoP
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
    }

    // MARK: - Handoff

    @MainActor
    private func generateHandoffSpore() {
        guard let store = appState.sporeStore, !appState.transcript.isEmpty else { return }

        let recentTopics = appState.transcript.suffix(10).map(\.text).joined(separator: " ")
        let recap = String(recentTopics.prefix(500))

        let spore = Spore(
            type: .handoff,
            status: .done,
            channel: appState.activeChannel?.name ?? "default",
            content: "Session ended on macOS.",
            contextRecap: recap,
            originPop: appState.deviceId
        )
        store.append(spore: spore)
    }
}
