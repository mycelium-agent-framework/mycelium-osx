import Cocoa
import CoreGraphics

/// Listens for Right Option key press via CGEvent tap.
/// Requires Accessibility permission (CGRequestListenEventAccess).
final class GlobalHotkeyManager {
    private let onActivate: () -> Void
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    init(onActivate: @escaping () -> Void) {
        self.onActivate = onActivate
    }

    func start() {
        // Request accessibility permission if needed
        let trusted = CGRequestListenEventAccess()
        if !trusted {
            print("[Hotkey] Accessibility permission not granted. Waiting for user to grant it.")
            // The system will show a prompt. We'll retry on next app launch.
            return
        }

        let mask: CGEventMask = (1 << CGEventType.flagsChanged.rawValue)

        // The callback needs to be a C function pointer, so we use a static context
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
            print("[Hotkey] Failed to create event tap. Check Accessibility permissions.")
            return
        }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        print("[Hotkey] Event tap installed. Right Option key is active.")
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

    private func handleEvent(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        guard type == .flagsChanged else {
            return Unmanaged.passRetained(event)
        }

        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let flags = event.flags

        // Right Option key: keycode 61, check that Option is pressed
        // and that it's specifically the right option (no left option flag)
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

/// Request accessibility permission.
/// Returns true if already trusted, false if the user needs to grant permission.
private func CGRequestListenEventAccess() -> Bool {
    let options = [kAXTrustedCheckOptionPrompt.takeRetainedValue(): true] as CFDictionary
    return AXIsProcessTrustedWithOptions(options)
}
