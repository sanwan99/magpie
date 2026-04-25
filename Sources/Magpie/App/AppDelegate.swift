import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var panelController: PanelController?
    private var hotkeyCenter: HotkeyCenter?
    private var clipboardWatcher: ClipboardWatcher?
    private var repository: ClipRepository?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let panel = PanelController()
        let hotkeys = HotkeyCenter()
        hotkeys.onTogglePanel = { [weak panel] in
            panel?.toggle()
        }

        let repo = ClipRepository()
        let watcher = ClipboardWatcher()
        watcher.onChange = { pasteboard in
            AppDelegate.ingest(pasteboard: pasteboard, repository: repo)
        }
        watcher.start()

        self.panelController = panel
        self.hotkeyCenter = hotkeys
        self.clipboardWatcher = watcher
        self.repository = repo

        let count = (try? repo.count()) ?? -1
        NSLog("[magpie] launched. ⌘P toggles panel, Esc hides it. Watcher polling 400ms. clips=%d", count)
    }

    /// Detect type for the current pasteboard and write it to storage.
    /// Logs one summary line per ingestion for v0.1 verification.
    private static func ingest(pasteboard: NSPasteboard, repository: ClipRepository) {
        let app = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        guard let detected = ClipDetector.detect(pasteboard: pasteboard, app: app) else {
            let types = pasteboard.types?.map(\.rawValue).joined(separator: ", ") ?? "nil"
            let strLen = pasteboard.string(forType: .string)?.count ?? -1
            let strPreview = pasteboard.string(forType: .string)?.prefix(40) ?? "<nil>"
            NSLog("[clipboard] count=%d skipped types=[%@] strLen=%d str=\"%@\"",
                  pasteboard.changeCount, types, strLen, String(strPreview))
            return
        }
        do {
            try repository.insert(detected)
            let titlePreview = detected.title?.prefix(60).replacingOccurrences(of: "\n", with: "↵") ?? ""
            NSLog("[clipboard] count=%d type=%@ from=%@ title=\"%@\" ingested",
                  pasteboard.changeCount,
                  detected.type.rawValue,
                  detected.app ?? "?",
                  String(titlePreview))
        } catch {
            NSLog("[clipboard] insert failed: %@", "\(error)")
        }
    }
}
