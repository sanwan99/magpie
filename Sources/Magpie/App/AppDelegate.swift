import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var panelController: PanelController?
    private var hotkeyCenter: HotkeyCenter?
    private var clipboardWatcher: ClipboardWatcher?
    private var repository: ClipRepository?
    private var viewModel: ClipsViewModel?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let repo = ClipRepository()
        let vm = ClipsViewModel(repository: repo)
        let panel = PanelController(viewModel: vm)
        let hotkeys = HotkeyCenter()
        hotkeys.onTogglePanel = { [weak panel] in
            panel?.toggle()
        }

        let watcher = ClipboardWatcher()
        watcher.onChange = { [weak vm] pasteboard in
            AppDelegate.ingest(pasteboard: pasteboard, repository: repo)
            vm?.refresh()
        }
        watcher.start()

        self.repository = repo
        self.viewModel = vm
        self.panelController = panel
        self.hotkeyCenter = hotkeys
        self.clipboardWatcher = watcher

        NSLog("[magpie] launched. ⌘P toggles panel, Esc hides it. clips=%d", vm.clips.count)
    }

    /// Detect type for the current pasteboard and write it to storage.
    private static func ingest(pasteboard: NSPasteboard, repository: ClipRepository) {
        let app = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        guard let detected = ClipDetector.detect(pasteboard: pasteboard, app: app) else {
            let types = pasteboard.types?.map(\.rawValue).joined(separator: ", ") ?? "nil"
            NSLog("[clipboard] count=%d skipped types=[%@]", pasteboard.changeCount, types)
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
