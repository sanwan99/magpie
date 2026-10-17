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
            return pb.setString(s, forType: .string) ? s : nil

        case .code(let s, _):
            guard !s.isEmpty else { return nil }
            return pb.setString(s, forType: .string) ? s : nil

        case .url(let url, _):
            let s = url.absoluteString
            return pb.setString(s, forType: .string) ? s : nil

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
            var wroteImage = false
            let tiff = nsimg.tiffRepresentation
            if let tiff { wroteImage = pb.setData(tiff, forType: .tiff) }
            if let tiff,
               let bitmap = NSBitmapImageRep(data: tiff),
               let png = bitmap.representation(using: .png, properties: [:]) {
                wroteImage = pb.setData(png, forType: .png) || wroteImage
            }
            return wroteImage ? "[image \(w)×\(h)]" : nil

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
            return pb.setString(path, forType: .string) ? path : nil
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
        PasteFeedback.dismiss()
    }

    /// Fails closed if focus or clipboard ownership changes during activation.
    /// `window` is captured before the panel opens, not after its hide animation.
    static func paste(into target: NSRunningApplication?, window: AXUIElement?,
                      expectedChangeCount: Int,
                      completion: ((Bool) -> Void)? = nil) {
        cancelPendingPaste()
        @MainActor func fail(_ reason: PasteFailure) {
            PasteFeedback.show(reason)
            completion?(false)
        }
        guard NSPasteboard.general.changeCount == expectedChangeCount else { fail(.clipboardChanged); return }
        guard let target, !target.isTerminated else { fail(.targetUnavailable); return }
        guard accessibilityTrusted(prompt: false) else { fail(.permissionDenied); return }
        guard let expectedWindow = window else { fail(.windowUnavailable); return }
        let pid = target.processIdentifier
        let currentPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        guard currentPID == pid || currentPID == ProcessInfo.processInfo.processIdentifier else {
            fail(.windowChanged)
            return
        }
        let generation = requestID
        guard target.activate() else { fail(.targetUnavailable); return }
        pendingPaste = Task { @MainActor in
            do { try await Task.sleep(for: .milliseconds(200)) }
            catch { completion?(false); return }
            let focused = focusedWindow(of: pid)
            if let failure = PasteValidation.failure(
                currentRequest: generation == requestID && !Task.isCancelled,
                targetAlive: !target.isTerminated,
                targetPID: pid,
                frontmostPID: NSWorkspace.shared.frontmostApplication?.processIdentifier,
                sameWindow: focused.map { CFEqual($0, expectedWindow) } ?? false,
                expectedChangeCount: expectedChangeCount,
                actualChangeCount: NSPasteboard.general.changeCount,
                trusted: accessibilityTrusted(prompt: false)) {
                if failure != .superseded { PasteFeedback.show(failure) }
                completion?(false)
                return
            }
            guard simulateCmdV(to: pid) else { fail(.eventUnavailable); return }
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
    private static func simulateCmdV(to pid: pid_t) -> Bool {
        guard let source = CGEventSource(stateID: .privateState),
              let commandDown = CGEvent(keyboardEventSource: source, virtualKey: 0x37, keyDown: true),
              let vDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true),
              let vUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false),
              let commandUp = CGEvent(keyboardEventSource: source, virtualKey: 0x37, keyDown: false) else { return false }
        for event in [commandDown, vDown, vUp] {
            event.flags = .maskCommand
            event.postToPid(pid)
        }
        commandUp.flags = []
        commandUp.postToPid(pid)
        return true
    }

}

/// Pure decision boundary, shared by runtime checks and deterministic race tests.
enum PasteValidation {
    static func maySend(currentRequest: Bool, targetAlive: Bool, targetPID: pid_t,
                        frontmostPID: pid_t?, sameWindow: Bool, expectedChangeCount: Int,
                        actualChangeCount: Int, trusted: Bool) -> Bool {
        failure(currentRequest: currentRequest, targetAlive: targetAlive, targetPID: targetPID,
                frontmostPID: frontmostPID, sameWindow: sameWindow, expectedChangeCount: expectedChangeCount,
                actualChangeCount: actualChangeCount, trusted: trusted) == nil
    }
}


extension PasteValidation {
    static func failure(currentRequest: Bool, targetAlive: Bool, targetPID: pid_t,
                        frontmostPID: pid_t?, sameWindow: Bool, expectedChangeCount: Int,
                        actualChangeCount: Int, trusted: Bool) -> PasteFailure? {
        if !currentRequest { return .superseded }
        if expectedChangeCount != actualChangeCount { return .clipboardChanged }
        if !targetAlive { return .targetUnavailable }
        if !trusted { return .permissionDenied }
        if targetPID != frontmostPID || !sameWindow { return .windowChanged }
        return nil
    }
}

enum PasteFailure: Equatable, CaseIterable {
    case permissionDenied, targetUnavailable, windowUnavailable, windowChanged
    case clipboardChanged, writeFailed, eventUnavailable, superseded

    func message(language: AppLanguage) -> String? {
        let recovery = language.pick(zh: "内容已复制，可回到目标窗口手动 ⌘V。", en: "Content copied. Return to your target window and paste with ⌘V.")
        switch self {
        case .permissionDenied:
            return language.pick(zh: "自动粘贴需要辅助功能权限。可从菜单栏打开“使用入门与权限”。", en: "Automatic paste needs Accessibility. Open Getting Started & Permissions from the menu bar.") + " " + recovery
        case .targetUnavailable:
            return language.pick(zh: "目标应用不可用。", en: "The target app is unavailable.") + " " + recovery
        case .windowUnavailable:
            return language.pick(zh: "无法可靠识别目标窗口，已取消自动粘贴。", en: "The target window could not be identified; automatic paste was cancelled.") + " " + recovery
        case .windowChanged:
            return language.pick(zh: "目标窗口已变化，已取消自动粘贴。", en: "The target window changed; automatic paste was cancelled.") + " " + recovery
        case .clipboardChanged:
            return language.pick(zh: "剪贴板已被其他内容替换，已取消粘贴。请重新选择记录。", en: "The clipboard was replaced; paste was cancelled. Select the record again.")
        case .writeFailed:
            return language.pick(zh: "无法复制这条记录，请检查原文件或图片是否仍可访问。", en: "This record could not be copied. Check that its original file or image is still accessible.")
        case .eventUnavailable:
            return language.pick(zh: "系统未能创建粘贴操作。", en: "The system could not create the paste event.") + " " + recovery
        case .superseded: return nil
        }
    }
}

/// Content-free feedback that never activates Magpie or steals keyboard focus.
@MainActor
enum PasteFeedback {
    private static var panel: NSPanel?
    private static var dismissal: Task<Void, Never>?

    static func dismiss() {
        dismissal?.cancel()
        dismissal = nil
        panel?.orderOut(nil)
        panel = nil
    }

    static func show(_ failure: PasteFailure) {
        guard let message = failure.message(language: SettingsStore.shared.language) else { return }
        dismiss()
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 460, height: 108),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true
        panel.isReleasedWhenClosed = false
        panel.backgroundColor = .windowBackgroundColor
        panel.hasShadow = true
        let label = NSTextField(wrappingLabelWithString: message)
        label.font = .systemFont(ofSize: 13)
        label.frame = NSRect(x: 18, y: 14, width: 424, height: 80)
        panel.contentView?.addSubview(label)
        if let frame = NSScreen.main?.visibleFrame {
            panel.setFrameOrigin(NSPoint(x: frame.midX - 230, y: frame.minY + 90))
        }
        self.panel = panel
        panel.orderFrontRegardless()
        dismissal = Task { @MainActor in
            do { try await Task.sleep(for: .seconds(6)) } catch { return }
            dismiss()
        }
    }
}
