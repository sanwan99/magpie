import AppKit

/// Writes a clip to the system pasteboard and simulates ⌘V on the previously
/// frontmost application. Requires the user to grant Accessibility permission
/// for Magpie under System Settings → Privacy & Security → Accessibility.
@MainActor
enum Paster {
    /// Writes the clip's payload string into the system pasteboard.
    /// Returns the string that was written (caller may log).
    @discardableResult
    static func writeToPasteboard(_ clip: ClipDisplayItem, plainText: Bool = false) -> String? {
        let body: String?
        switch clip.preview {
        case .text(let s):
            body = s
        case .code(let s, _):
            body = s
        case .url(let url, _):
            body = url.absoluteString
        case .folder(let path, _):
            body = path
        case .file(let path, _, _):
            body = path
        case .unsupported:
            body = nil
        }
        guard let body, !body.isEmpty else { return nil }

        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(body, forType: .string)
        // `plainText` reserved for ⇧↵ behavior in v0.2; v0.1 always writes plain string,
        // which is already unstyled.
        _ = plainText
        return body
    }

    /// Activates the target app and posts a ⌘V keystroke. Honors a tiny activation
    /// delay so the system has time to make the target the key window.
    static func paste(into target: NSRunningApplication?) {
        guard let target else {
            NSLog("[paste] no frontmost target — skipping ⌘V (just wrote pasteboard)")
            return
        }
        target.activate()
        // Small delay to let the activation propagate before posting the keystroke.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) {
            simulateCmdV()
        }
    }

    private static func simulateCmdV() {
        let src = CGEventSource(stateID: .combinedSessionState)
        let vKey: CGKeyCode = 0x09 // ANSI V
        guard
            let down = CGEvent(keyboardEventSource: src, virtualKey: vKey, keyDown: true),
            let up = CGEvent(keyboardEventSource: src, virtualKey: vKey, keyDown: false)
        else {
            NSLog("[paste] failed to construct CGEvent — Accessibility permission missing?")
            return
        }
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }
}
