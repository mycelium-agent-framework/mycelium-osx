import Cocoa
import CoreGraphics

/// Listens for Right Option key press/release via CGEvent tap.
/// Requires Accessibility permission.
final class GlobalHotkeyManager {
    private let onPress: () -> Void
    private let onRelease: () -> Void
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var hasPrompted = false
    private var isPressed = false

    init(onPress: @escaping () -> Void, onRelease: @escaping () -> Void) {
        self.onPress = onPress
        self.onRelease = onRelease
    }

    func start() {
        print("[Hotkey] Starting... AXIsProcessTrusted=\(AXIsProcessTrusted())")
        if installEventTap() { return }

        print("[Hotkey] Event tap failed. Requesting accessibility...")
        if !hasPrompted {
            hasPrompted = true
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
        ) else { return false }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        print("[Hotkey] Event tap installed. Right Option key is active.")
        return true
    }

    private func handleEvent(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // Re-enable tap if macOS disabled it due to timeout
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
                print("[Hotkey] Event tap re-enabled after system disable")
            }
            return Unmanaged.passRetained(event)
        }

        guard type == .flagsChanged else {
            return Unmanaged.passRetained(event)
        }

        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let flags = event.flags

        // Right Option key: keycode 61
        guard keyCode == 61 else {
            return Unmanaged.passRetained(event)
        }

        let optionDown = flags.contains(.maskAlternate)

        if optionDown && !isPressed {
            // Key pressed
            isPressed = true
            DispatchQueue.main.async { [weak self] in
                self?.onPress()
            }
        } else if !optionDown && isPressed {
            // Key released
            isPressed = false
            DispatchQueue.main.async { [weak self] in
                self?.onRelease()
            }
        }

        return Unmanaged.passRetained(event)
    }

    deinit {
        stop()
    }
}
