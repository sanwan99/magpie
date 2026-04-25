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
        let bid = target.bundleIdentifier ?? "?"
        NSLog("[paste] activating target=%@ active=%d", bid, target.isActive ? 1 : 0)
        target.activate()
        // Small delay to let the activation propagate before posting the keystroke.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) {
            let frontNow = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "?"
            NSLog("[paste] firing ⌘V (frontmost now=%@)", frontNow)
            simulateCmdV()
        }
    }

    /// Posts a full ⌘V key sequence: ⌘ down → V down → V up → ⌘ up.
    ///
    /// Why the full sequence (instead of just V down/up with .maskCommand):
    /// the user is often still physically holding ⌘ when this fires (it was
    /// part of the ⌘1-9 hotkey that triggered us). With CGEventSource
    /// `.combinedSessionState`, posted-event flags get merged with the live
    /// modifier state, which can race with user release/hold and produce
    /// inconsistent outcomes. We use `.privateState` so the event's flags are
    /// taken literally, and we send the explicit ⌘ press/release ourselves —
    /// this makes the sequence robust regardless of what the user is doing
    /// physically at the moment we fire.
    private static func simulateCmdV() {
        let src = CGEventSource(stateID: .privateState)
        let cmdKey: CGKeyCode = 0x37  // Left Command
        let vKey: CGKeyCode = 0x09    // ANSI V

        if let cmdDown = CGEvent(keyboardEventSource: src, virtualKey: cmdKey, keyDown: true) {
            cmdDown.flags = .maskCommand
            cmdDown.post(tap: .cghidEventTap)
        }
        if let vDown = CGEvent(keyboardEventSource: src, virtualKey: vKey, keyDown: true) {
            vDown.flags = .maskCommand
            vDown.post(tap: .cghidEventTap)
        }
        if let vUp = CGEvent(keyboardEventSource: src, virtualKey: vKey, keyDown: false) {
            vUp.flags = .maskCommand
            vUp.post(tap: .cghidEventTap)
        }
        if let cmdUp = CGEvent(keyboardEventSource: src, virtualKey: cmdKey, keyDown: false) {
            cmdUp.flags = []
            cmdUp.post(tap: .cghidEventTap)
        }
    }
}
