import AppKit

/// Writes a clip to the system pasteboard and simulates ⌘V on the previously
/// frontmost application. Requires the user to grant Accessibility permission
/// for Magpie under System Settings → Privacy & Security → Accessibility.
@MainActor
enum Paster {
    /// Writes the clip's payload to the system pasteboard.
    /// Returns the written value for success checks. Never log this value.
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

        case .folder(let path, _), .file(let path, _, _):
            return writeFileURLToPasteboard(path: path, pasteboard: pb)

        case .image(let path, let w, let h, _):
            // Write both .tiff (preferred by image apps) and .png (broader support).
            // Path string fallback would be misleading (it's an internal cache path),
            // so omit it.
            guard let nsimg = NSImage(contentsOfFile: path) else {
                NSLog("[paste] image unavailable")
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

    /// Writes the file/folder path as plain text. Used by the explicit
    /// "路径" action so it does not change the normal file/folder paste path.
    @discardableResult
    static func writePathToPasteboard(_ clip: ClipDisplayItem) -> String? {
        let pb = NSPasteboard.general
        pb.clearContents()

        switch clip.preview {
        case .folder(let path, _), .file(let path, _, _):
            pb.setString(path, forType: .string)
            return path
        default:
            return writeToPasteboard(clip)
        }
    }

    private static func writeFileURLToPasteboard(path: String, pasteboard: NSPasteboard) -> String? {
        let url = URL(fileURLWithPath: path)
        guard pasteboard.writeObjects([url as NSURL]) else {
            NSLog("[paste] file write failed")
            return nil
        }
        return path
    }

    private static var pendingPaste: Task<Void, Never>?
    private static var requestID = UUID()

    static func cancelPendingPaste() {
        pendingPaste?.cancel()
        pendingPaste = nil
        requestID = UUID()
    }

    /// Fails closed if focus or clipboard ownership changes during activation.
    /// `window` is captured before the panel opens, not after its hide animation.
    static func paste(into target: NSRunningApplication?, window: AXUIElement? = nil,
                      completion: ((Bool) -> Void)? = nil) {
        cancelPendingPaste()
        guard let target, !target.isTerminated, accessibilityTrusted(prompt: true),
              let expectedWindow = window ?? focusedWindow(of: target.processIdentifier) else {
            completion?(false)
            return
        }
        let pid = target.processIdentifier
        let currentPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        guard currentPID == pid || currentPID == ProcessInfo.processInfo.processIdentifier else {
            completion?(false)
            return
        }
        let generation = requestID
        let changeCount = NSPasteboard.general.changeCount
        guard target.activate() else { completion?(false); return }
        pendingPaste = Task { @MainActor in
            do { try await Task.sleep(for: .milliseconds(200)) }
            catch { completion?(false); return }
            let focused = focusedWindow(of: pid)
            guard PasteValidation.maySend(
                currentRequest: generation == requestID,
                targetAlive: !target.isTerminated,
                targetPID: pid,
                frontmostPID: NSWorkspace.shared.frontmostApplication?.processIdentifier,
                sameWindow: focused.map { CFEqual($0, expectedWindow) } ?? false,
                expectedChangeCount: changeCount,
                actualChangeCount: NSPasteboard.general.changeCount,
                trusted: accessibilityTrusted(prompt: false)), !Task.isCancelled else {
                completion?(false)
                return
            }
            simulateCmdV(to: pid)
            completion?(true)
        }
    }

    static func focusedWindow(of pid: pid_t) -> AXUIElement? {
        let application = AXUIElementCreateApplication(pid)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(application, kAXFocusedWindowAttribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    private static func accessibilityTrusted(prompt: Bool) -> Bool {
        guard prompt else { return AXIsProcessTrusted() }
        let promptKey = "AXTrustedCheckOptionPrompt" as CFString
        let options = [promptKey: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
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
    private static func simulateCmdV(to pid: pid_t) {
        let src = CGEventSource(stateID: .privateState)
        let cmdKey: CGKeyCode = 0x37  // Left Command
        let vKey: CGKeyCode = 0x09    // ANSI V

        if let cmdDown = CGEvent(keyboardEventSource: src, virtualKey: cmdKey, keyDown: true) {
            cmdDown.flags = .maskCommand
            cmdDown.postToPid(pid)
        }
        if let vDown = CGEvent(keyboardEventSource: src, virtualKey: vKey, keyDown: true) {
            vDown.flags = .maskCommand
            vDown.postToPid(pid)
        }
        if let vUp = CGEvent(keyboardEventSource: src, virtualKey: vKey, keyDown: false) {
            vUp.flags = .maskCommand
            vUp.postToPid(pid)
        }
        if let cmdUp = CGEvent(keyboardEventSource: src, virtualKey: cmdKey, keyDown: false) {
            cmdUp.flags = []
            cmdUp.postToPid(pid)
        }
    }
}

/// Pure decision boundary, shared by runtime checks and deterministic race tests.
enum PasteValidation {
    static func maySend(currentRequest: Bool, targetAlive: Bool, targetPID: pid_t,
                        frontmostPID: pid_t?, sameWindow: Bool, expectedChangeCount: Int,
                        actualChangeCount: Int, trusted: Bool) -> Bool {
        currentRequest && targetAlive && trusted && sameWindow
            && targetPID == frontmostPID && expectedChangeCount == actualChangeCount
    }
}
