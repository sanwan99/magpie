import AppKit

/// Borderless, non-activating panel anchored to the bottom of the active screen.
/// This is the Magpie panel chrome — the host where SwiftUI content (Stripe / Stack / Grid) renders.
final class PanelWindow: NSPanel {
    /// Invoked when the user presses Esc inside the panel (via the responder chain's cancelOperation).
    var onCancel: (() -> Void)?
    /// Invoked when ↵ is pressed — paste the focused clip.
    var onPaste: (() -> Void)?
    /// Invoked when ←/↑ is pressed — move focus toward older clips.
    var onMoveBack: (() -> Void)?
    /// Invoked when →/↓ is pressed — move focus toward newer clips.
    var onMoveForward: (() -> Void)?
    /// Invoked when ⌘1…⌘9 is pressed — paste the Nth clip directly.
    var onPasteAtIndex: ((Int) -> Void)?
    /// Invoked when ⌘D is pressed — toggle pinned for the focused clip.
    var onTogglePin: (() -> Void)?

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

    override func keyDown(with event: NSEvent) {
        let cmdOnly = event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command

        if cmdOnly, let chars = event.charactersIgnoringModifiers {
            // ⌘1…⌘9 → quick paste at index
            if chars.count == 1,
               let scalar = chars.unicodeScalars.first,
               let digit = Int(String(scalar)),
               (1...9).contains(digit) {
                onPasteAtIndex?(digit - 1)
                return
            }
            // ⌘D → toggle pin
            if chars == "d" {
                onTogglePin?()
                return
            }
        }

        switch event.keyCode {
        case 36, 76:           // Return, Numpad Enter
            onPaste?()
            return
        case 123, 126:          // Left, Up
            onMoveBack?()
            return
        case 124, 125:          // Right, Down
            onMoveForward?()
            return
        default:
            break
        }

        super.keyDown(with: event)
    }
}
