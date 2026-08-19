import AppKit

/// Borderless, non-activating panel anchored to the bottom of the active screen.
/// This is the Magpie panel chrome — the host where SwiftUI content (Stripe / Stack / Grid) renders.
final class PanelWindow: NSPanel {
    /// Invoked when the user presses Esc inside the panel (via the responder chain's cancelOperation).
    var onCancel: (() -> Void)?
    /// Invoked when ↵ is pressed — paste the focused clip.
    var onPaste: (() -> Void)?
    /// Invoked when an arrow key is pressed — focus movement is layout-aware.
    var onMoveFocus: ((FocusNavigationDirection) -> Void)?
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
        collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
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
        if isTextInputActive {
            super.keyDown(with: event)
            return
        }

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
        case 123:               // Left
            onMoveFocus?(.left)
            return
        case 124:               // Right
            onMoveFocus?(.right)
            return
        case 126:               // Up
            onMoveFocus?(.up)
            return
        case 125:               // Down
            onMoveFocus?(.down)
            return
        default:
            break
        }

        super.keyDown(with: event)
    }

    private var isTextInputActive: Bool {
        guard let responder = firstResponder else { return false }
        return responder is NSTextView || responder is NSTextField || responder is NSSearchField
    }
}
