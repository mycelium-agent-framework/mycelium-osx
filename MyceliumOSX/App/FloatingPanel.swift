import AppKit

/// A non-activating floating panel that stays on top without stealing focus.
final class FloatingPanel: NSPanel {
    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 600),
            styleMask: [.nonactivatingPanel, .titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        isFloatingPanel = true
        level = .floating
        isMovableByWindowBackground = true
        titlebarAppearsTransparent = true
        titleVisibility = .hidden
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true

        // Don't show in Mission Control
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        // Position: top-right of screen
        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let panelFrame = frame
            let x = screenFrame.maxX - panelFrame.width - 20
            let y = screenFrame.maxY - panelFrame.height - 20
            setFrameOrigin(NSPoint(x: x, y: y))
        }

        // Minimum size
        minSize = NSSize(width: 300, height: 400)
    }
}
