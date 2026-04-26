import AppKit

/// Writes a clip to the system pasteboard and simulates ⌘V on the previously
/// frontmost application. Requires the user to grant Accessibility permission
/// for Magpie under System Settings → Privacy & Security → Accessibility.
@MainActor
enum Paster {
    /// Writes the clip's payload to the system pasteboard.
    /// Returns a brief description of what was written (for log).
    @discardableResult
    static func writeToPasteboard(_ clip: ClipDisplayItem, plainText: Bool = false) -> String? {
        // `plainText` reserved for ⇧↵ behavior in a future version.
        _ = plainText

        let pb = NSPasteboard.general
        pb.clearContents()

        switch clip.preview {
        case .text(let s):
            guard !s.isEmpty else { return nil }
            pb.setString(s, forType: .string)
            return s

        case .code(let s, _):
            guard !s.isEmpty else { return nil }
            pb.setString(s, forType: .string)
            return s

        case .url(let url, _):
            let s = url.absoluteString
            pb.setString(s, forType: .string)
            return s

        case .folder(let path, _):
            pb.setString(path, forType: .string)
            return path

        case .file(let path, _, _):
            pb.setString(path, forType: .string)
            return path

        case .image(let path, let w, let h, _):
            // Write both .tiff (preferred by image apps) and .png (broader support).
            // Path string fallback would be misleading (it's an internal cache path),
            // so omit it.
            guard let nsimg = NSImage(contentsOfFile: path) else {
                NSLog("[paste] image file missing: %@", path)
                return nil
            }
            if let tiff = nsimg.tiffRepresentation {
                pb.setData(tiff, forType: .tiff)
            }
            if let tiff = nsimg.tiffRepresentation,
               let bitmap = NSBitmapImageRep(data: tiff),
               let png = bitmap.representation(using: .png, properties: [:]) {
                pb.setData(png, forType: .png)
            }
            return "[image \(w)×\(h)]"

        case .unsupported:
            return nil
        }
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
