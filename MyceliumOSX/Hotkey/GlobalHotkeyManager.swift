import Cocoa
import CoreGraphics

/// Listens for Right Option key press via CGEvent tap.
/// Requires Accessibility permission.
final class GlobalHotkeyManager {
    private let onActivate: () -> Void
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var hasPrompted = false

    init(onActivate: @escaping () -> Void) {
        self.onActivate = onActivate
    }

    func start() {
        // Try to install the event tap directly.
        // If it succeeds, we have accessibility — no prompt needed.
        if installEventTap() {
            return
        }

        // Event tap failed — we need accessibility permission.
        // Only prompt once per app lifetime.
        if !hasPrompted {
            hasPrompted = true
            // Use the raw string key to avoid retain issues with the constant
            let key = "AXTrustedCheckOptionPrompt" as CFString
            let options = [key: true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
        }

        pollForAccessibility()
    }

    func stop() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
    }

    // MARK: - Private

    private func pollForAccessibility() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            guard let self, self.eventTap == nil else { return }
            if self.installEventTap() {
                print("[Hotkey] Accessibility granted — event tap installed.")
            } else {
                self.pollForAccessibility()
            }
        }
    }

    /// Try to create and install the event tap. Returns true on success.
    @discardableResult
    private func installEventTap() -> Bool {
        guard eventTap == nil else { return true }

        let mask: CGEventMask = (1 << CGEventType.flagsChanged.rawValue)

        let callback: CGEventTapCallBack = { _, type, event, userInfo in
            guard let userInfo else { return Unmanaged.passRetained(event) }
            let manager = Unmanaged<GlobalHotkeyManager>.fromOpaque(userInfo).takeUnretainedValue()
            return manager.handleEvent(type: type, event: event)
        }

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: callback,
            userInfo: selfPtr
        ) else {
            return false
        }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        print("[Hotkey] Event tap installed. Right Option key is active.")
        return true
    }

    private func handleEvent(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        guard type == .flagsChanged else {
            return Unmanaged.passRetained(event)
        }

        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let flags = event.flags

        // Right Option key: keycode 61, check that Option is pressed
        if keyCode == 61 && flags.contains(.maskAlternate) {
            DispatchQueue.main.async { [weak self] in
                self?.onActivate()
            }
        }

        return Unmanaged.passRetained(event)
    }

    deinit {
        stop()
    }
}
