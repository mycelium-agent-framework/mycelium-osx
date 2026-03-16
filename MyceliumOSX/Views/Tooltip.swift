import AppKit
import SwiftUI

/// A tooltip modifier that works on non-activating panels where .help() doesn't.
/// Uses NSView's native tooltip mechanism via NSHostingView overlay.
struct TooltipModifier: ViewModifier {
    let text: String

    func body(content: Content) -> some View {
        content
            .overlay(TooltipView(text: text).allowsHitTesting(false))
    }
}

private struct TooltipView: NSViewRepresentable {
    let text: String

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.toolTip = text
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        nsView.toolTip = text
    }
}

extension View {
    func tooltip(_ text: String) -> some View {
        modifier(TooltipModifier(text: text))
    }
}
