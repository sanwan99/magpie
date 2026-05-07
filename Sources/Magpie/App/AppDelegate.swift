import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var panelController: PanelController?
    private var hotkeyCenter: HotkeyCenter?
    private var statusItemController: StatusItemController?
    private var clipboardWatcher: ClipboardWatcher?
    private var clipboardIngestor: ClipboardIngestor?
    private var repository: ClipRepository?
    private var viewModel: ClipsViewModel?
    private var snippetsViewModel: SnippetsViewModel?
    private var snippetExpander: SnippetExpander?
    private var historyReaper: HistoryReaper?

    func applicationDidFinishLaunching(_ notification: Notification) {
        if Self.isRunningUnitTests {
            NSLog("[magpie] launched in unit test host; skipping app services")
            return
        }

        let repo = ClipRepository()
        let ingestor = ClipboardIngestor(repository: repo)
        let vm = ClipsViewModel(repository: repo)
        let snippetsVM = SnippetsViewModel()
        let panel = PanelController(viewModel: vm, snippetsViewModel: snippetsVM)
        let hotkeys = HotkeyCenter()
        hotkeys.onTogglePanel = { [weak panel] in
            panel?.toggle()
        }

        let reaper = HistoryReaper()
        reaper.reapInBackground()  // Apply retention on launch without blocking first wake.

        let watcher = ClipboardWatcher()
        watcher.onChange = { [weak vm, weak reaper, ingestor] snapshot in
            let store = SettingsStore.shared
            let policy = ClipboardIngestPolicy(
                appBundleIdentifier: NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
                ignoredApps: store.ignoredApps,
                skipSecretLooking: store.skipSecretLooking
            )
            Task {
                let changed = await ingestor.ingest(snapshot: snapshot, policy: policy)
                guard changed else { return }
                await MainActor.run {
                    vm?.refresh()
                    reaper?.scheduleReap()
                }
            }
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

        // 菜单栏图标：⌘P 失效时的兜底入口（也解决 LSUIElement 隐藏带来的可发现性问题）
        let statusItem = StatusItemController(panelController: panel)

        // Carbon 热键恢复链路：sleep 前释放旧 ref，wake / Space / session
        // active / app active 后做一次性重建，不再使用 30 秒心跳。
        let workspaceNC = NSWorkspace.shared.notificationCenter
        workspaceNC.addObserver(self, selector: #selector(handleHotkeyLifecycleNotification(_:)),
                                name: NSWorkspace.willSleepNotification, object: nil)
        workspaceNC.addObserver(self, selector: #selector(handleHotkeyLifecycleNotification(_:)),
                                name: NSWorkspace.didWakeNotification, object: nil)
        workspaceNC.addObserver(self, selector: #selector(handleHotkeyLifecycleNotification(_:)),
                                name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)
        workspaceNC.addObserver(self, selector: #selector(handleHotkeyLifecycleNotification(_:)),
                                name: NSWorkspace.screensDidWakeNotification, object: nil)
        workspaceNC.addObserver(self, selector: #selector(handleHotkeyLifecycleNotification(_:)),
                                name: NSWorkspace.sessionDidBecomeActiveNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleHotkeyLifecycleNotification(_:)),
                                               name: NSApplication.didBecomeActiveNotification, object: nil)

        self.repository = repo
        self.clipboardIngestor = ingestor
        self.viewModel = vm
        self.snippetsViewModel = snippetsVM
        self.panelController = panel
        self.hotkeyCenter = hotkeys
        self.statusItemController = statusItem
        self.clipboardWatcher = watcher
        self.snippetExpander = expander
        self.historyReaper = reaper

        NSLog("[magpie] launched. ⌘P toggles panel, Esc hides it. clips=%d snippets=%d",
              vm.clips.count, snippetsVM.snippets.count)

        // 辅助权限自检 — 没权限就 prompt=true 弹系统权限对话框。
        // 没有这个权限 CGEvent.post 会静默失败 → 粘贴看似执行了实际啥也没发出去。
        let prompt = "AXTrustedCheckOptionPrompt" as CFString
        let opts = [prompt: true] as CFDictionary
        let trusted = AXIsProcessTrustedWithOptions(opts)
        NSLog("[ax] trusted=%d — 模拟 ⌘V 需要辅助功能权限", trusted ? 1 : 0)
    }

    private static var isRunningUnitTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    @objc private func handleHotkeyLifecycleNotification(_ notification: Notification) {
        guard let event = HotkeyLifecycleEvent(notificationName: notification.name) else {
            NSLog("[hotkey] ignored lifecycle notification=%@", notification.name.rawValue)
            return
        }
        NSLog("[hotkey] lifecycle notification=%@ event=%@",
              notification.name.rawValue, event.rawValue)
        hotkeyCenter?.recover(after: event)
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

}

private extension HotkeyLifecycleEvent {
    init?(notificationName: Notification.Name) {
        switch notificationName {
        case NSWorkspace.willSleepNotification:
            self = .willSleep
        case NSWorkspace.didWakeNotification:
            self = .didWake
        case NSWorkspace.screensDidWakeNotification:
            self = .screensDidWake
        case NSWorkspace.activeSpaceDidChangeNotification:
            self = .activeSpaceDidChange
        case NSWorkspace.sessionDidBecomeActiveNotification:
            self = .sessionDidBecomeActive
        case NSApplication.didBecomeActiveNotification:
            self = .applicationDidBecomeActive
        default:
            return nil
        }
    }
}
