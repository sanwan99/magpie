import AppKit

/// Borderless, non-activating panel anchored to the bottom of the active screen.
/// This is the Magpie panel chrome — the host where SwiftUI content (Stripe / Stack / Grid) renders.
final class PanelWindow: NSPanel {
    /// Invoked when the user presses Esc inside the panel (via the responder chain's cancelOperation).
    var onCancel: (() -> Void)?

    init(contentRect: NSRect = .zero) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        isMovableByWindowBackground = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }
}
