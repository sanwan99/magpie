import AppKit
import Foundation

/// Watches global key presses and expands snippet shortcuts (e.g. `;sig` → signature).
///
/// Strategy:
///   1. NSEvent.addGlobalMonitorForEvents(.keyDown) observes every key press
///      across all apps (requires Accessibility / Input Monitoring permission).
///   2. We buffer the recent typed characters.
///   3. When the buffer's tail matches a snippet's shortcut, we:
///      - simulate Backspace × shortcut.count to remove the trigger string
///      - write the snippet body to the pasteboard
///      - simulate ⌘V to paste the body
///   4. `isExpanding` flag prevents the simulated keystrokes from re-triggering
///      ourselves (the simulated Backspace + ⌘V also pass through the global
///      monitor).
///
/// Notes:
///   - Modifier keys (⌘/⌃/⌥) reset the buffer — they're not text input.
///   - Special keys (Return/Esc/Backspace/arrows) also reset the buffer so
///     "type :sig in a previous edit, hit Enter, type more text" doesn't
///     accidentally match.
///   - CJK input methods deliver composition results (Chinese chars) to apps,
///     not the original ASCII keystrokes — so users in 中文 IM mode won't
///     trigger ASCII shortcuts. That's acceptable: switch to English IM
///     before typing the trigger. Native CJK shortcut support is later.
@MainActor
final class SnippetExpander {
    weak var snippetsViewModel: SnippetsViewModel?

    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var buffer: String = ""
    private let bufferLimit = 64
    /// True while we're posting our own backspace + ⌘V keystrokes.
    /// Stops the monitor from re-processing our simulated events.
    private var isExpanding = false

    func start() {
        let mask: NSEvent.EventTypeMask = .keyDown

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] event in
            Task { @MainActor [weak self] in
                self?.observe(event: event)
            }
        }
        // Local monitor catches keystrokes typed into Magpie's own panel —
        // not strictly needed for the in-the-wild use case but means the
        // expander also works inside Magpie's search field for testing.
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            self?.observe(event: event)
            return event
        }
        NSLog("[snippets] expander started (AX permission required for global key monitor)")
    }

    func stop() {
        if let m = globalMonitor { NSEvent.removeMonitor(m) }
        if let m = localMonitor { NSEvent.removeMonitor(m) }
        globalMonitor = nil
        localMonitor = nil
    }

    // MARK: - Observation

    private func observe(event: NSEvent) {
        if isExpanding { return }

        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        // Modifier-bearing events (shortcuts) are not text — reset & ignore.
        if mods.contains(.command) || mods.contains(.control) || mods.contains(.option) {
            buffer.removeAll()
            return
        }

        // Reset buffer on navigation / control keys.
        switch event.keyCode {
        case 36, 76, 53, 51, 117, 123, 124, 125, 126:
            // Return / Numpad Enter / Esc / Backspace / Forward Delete / Left / Right / Down / Up
            buffer.removeAll()
            return
        default:
            break
        }

        guard let chars = event.charactersIgnoringModifiers, !chars.isEmpty else { return }
        // Skip non-printable
        if chars.unicodeScalars.contains(where: { $0.value < 0x20 || $0.value == 0x7F }) {
            return
        }

        buffer.append(chars)
        if buffer.count > bufferLimit {
            buffer = String(buffer.suffix(bufferLimit))
        }

        if let matched = findMatch() {
            buffer.removeAll()
            // Tiny delay so the final trigger character has time to propagate
            // into the receiving app before we start backspacing.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) { [weak self] in
                self?.expand(matched)
            }
        }
    }

    private func findMatch() -> Snippet? {
        let snippets = snippetsViewModel?.snippets ?? []
        for snippet in snippets where !snippet.shortcut.isEmpty {
            if buffer.hasSuffix(snippet.shortcut) {
                return snippet
            }
        }
        return nil
    }

    // MARK: - Expansion

    private func expand(_ snippet: Snippet) {
        isExpanding = true
        let len = snippet.shortcut.count
        NSLog("[snippets] expanding %@ (len=%d) → %d chars", snippet.shortcut, len, snippet.body.count)

        simulateBackspace(times: len)

        // After backspaces propagate, write body and ⌘V.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) { [weak self] in
            guard let self else { return }
            let pb = NSPasteboard.general
            pb.clearContents()
            pb.setString(snippet.body, forType: .string)
            self.simulateCmdV()
            // Re-arm after our keystrokes are done.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.10) { [weak self] in
                self?.isExpanding = false
            }
        }
    }

    // MARK: - Synthetic keystrokes

    private func simulateBackspace(times: Int) {
        let src = CGEventSource(stateID: .privateState)
        let key: CGKeyCode = 0x33  // Delete (backspace)
        for _ in 0..<times {
            CGEvent(keyboardEventSource: src, virtualKey: key, keyDown: true)?.post(tap: .cghidEventTap)
            CGEvent(keyboardEventSource: src, virtualKey: key, keyDown: false)?.post(tap: .cghidEventTap)
        }
    }

    private func simulateCmdV() {
        let src = CGEventSource(stateID: .privateState)
        let cmdKey: CGKeyCode = 0x37
        let vKey: CGKeyCode = 0x09

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
