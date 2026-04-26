import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var panelController: PanelController?
    private var hotkeyCenter: HotkeyCenter?
    private var clipboardWatcher: ClipboardWatcher?
    private var repository: ClipRepository?
    private var viewModel: ClipsViewModel?
    private var snippetsViewModel: SnippetsViewModel?
    private var snippetExpander: SnippetExpander?
    private var historyReaper: HistoryReaper?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let repo = ClipRepository()
        let vm = ClipsViewModel(repository: repo)
        let snippetsVM = SnippetsViewModel()
        let panel = PanelController(viewModel: vm, snippetsViewModel: snippetsVM)
        let hotkeys = HotkeyCenter()
        hotkeys.onTogglePanel = { [weak panel] in
            panel?.toggle()
        }

        let reaper = HistoryReaper()
        reaper.reapNow()  // Apply retention on launch in case user changed settings while app was off.

        let watcher = ClipboardWatcher()
        watcher.onChange = { [weak vm, weak reaper] pasteboard in
            AppDelegate.ingest(pasteboard: pasteboard, repository: repo)
            vm?.refresh()
            reaper?.scheduleReap()
        }
        watcher.start()

        // Snippet auto-expansion (e.g. typing ;sig in any text field).
        // OFF by default — requires Input Monitoring permission. User opts in
        // via Settings → General → "Auto-expand snippet shortcuts".
        let expander = SnippetExpander()
        expander.snippetsViewModel = snippetsVM
        if SettingsStore.shared.autoExpandSnippets {
            expander.start()
        }
        observeAutoExpandToggle(expander: expander)

        self.repository = repo
        self.viewModel = vm
        self.snippetsViewModel = snippetsVM
        self.panelController = panel
        self.hotkeyCenter = hotkeys
        self.clipboardWatcher = watcher
        self.snippetExpander = expander
        self.historyReaper = reaper

        NSLog("[magpie] launched. ⌘P toggles panel, Esc hides it. clips=%d snippets=%d",
              vm.clips.count, snippetsVM.snippets.count)
    }

    /// React to user toggling autoExpandSnippets in Settings — start/stop the
    /// expander accordingly. One-shot withObservationTracking re-arms each fire.
    private func observeAutoExpandToggle(expander: SnippetExpander) {
        func track() {
            withObservationTracking {
                _ = SettingsStore.shared.autoExpandSnippets
            } onChange: { [weak expander] in
                Task { @MainActor in
                    guard let expander else { return }
                    if SettingsStore.shared.autoExpandSnippets {
                        expander.start()
                    } else {
                        expander.stop()
                    }
                    track()
                }
            }
        }
        track()
    }

    /// Detect type for the current pasteboard and write it to storage,
    /// honoring user privacy preferences (ignored apps, skip-secret).
    private static func ingest(pasteboard: NSPasteboard, repository: ClipRepository) {
        let app = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        let store = SettingsStore.shared

        // Ignored apps — never capture clipboard activity from these.
        if let app, store.ignoredApps.contains(app) {
            NSLog("[clipboard] count=%d skipped (ignored app: %@)",
                  pasteboard.changeCount, app)
            return
        }

        guard let detected = ClipDetector.detect(pasteboard: pasteboard, app: app) else {
            let types = pasteboard.types?.map(\.rawValue).joined(separator: ", ") ?? "nil"
            NSLog("[clipboard] count=%d skipped types=[%@]", pasteboard.changeCount, types)
            return
        }

        // Skip secret-looking content (default ON). Only checks textual clips —
        // image / file / folder don't carry credential strings in the body.
        if store.skipSecretLooking,
           let text = textBody(of: detected),
           SecretDetector.looksSecret(text) {
            NSLog("[clipboard] count=%d skipped (looks like secret)", pasteboard.changeCount)
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

    /// Extract the text body of a DetectedClip for SecretDetector matching.
    /// Returns nil for non-text clip types (image / folder / file).
    private static func textBody(of detected: DetectedClip) -> String? {
        switch detected.type {
        case .text:
            return (try? JSONDecoder().decode(TextPayload.self, from: detected.payload))?.body
        case .code:
            return (try? JSONDecoder().decode(CodePayload.self, from: detected.payload))?.body
        case .url:
            return (try? JSONDecoder().decode(URLPayload.self, from: detected.payload))?.url
        case .folder, .file, .image:
            return nil
        }
    }
}
