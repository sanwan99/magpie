import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var panelController: PanelController?
    private var hotkeyCenter: HotkeyCenter?
    private var statusItemController: StatusItemController?
    private var clipboardWatcher: ClipboardWatcher?
    private let recording = ClipboardRecordingControl()
    private var clipboardIngestor: ClipboardIngestor?
    private var repository: ClipRepository?
    private var viewModel: ClipsViewModel?
    private var snippetsViewModel: SnippetsViewModel?
    private var snippetExpander: SnippetExpander?
    private var historyReaper: HistoryReaper?
    private var screenshotCoordinator: ScreenshotCoordinator?

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

        let reaper = HistoryReaper()
        reaper.reapInBackground()  // Apply retention on launch without blocking first wake.

        let watcher = ClipboardWatcher()
        watcher.allowsCapture = { [recording] in !recording.isPaused }
        recording.onChange = { [weak self, weak watcher] in
            repo.database.invalidatePendingIngests()
            watcher?.discardPendingChanges()
            self?.statusItemController?.refreshRecordingStatus()
        }
        SettingsStore.shared.onRecordingPolicyChange = recording.onChange
        watcher.onChange = { [weak vm, weak reaper, ingestor] snapshot, origin in
            let store = SettingsStore.shared
            let policy = ClipboardIngestPolicy.forChange(
                origin: origin,
                observedAppBundleIdentifier: NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
                magpieBundleIdentifier: Bundle.main.bundleIdentifier ?? "com.sanwan.magpie",
                ignoredApps: store.ignoredApps,
                skipSecretLooking: store.skipSecretLooking
            )
            let generation = repo.database.currentIngestGeneration
            Task {
                let changed = await ingestor.ingest(snapshot: snapshot, policy: policy, expectedGeneration: generation)
                guard changed else { return }
                await MainActor.run {
                    vm?.refresh()
                    reaper?.scheduleReap()
                }
            }
        }
        watcher.start()

        let screenshotCoordinator = ScreenshotCoordinator(
            panel: panel,
            clipboardRouter: watcher
        )
        hotkeys.onTogglePanel = { [weak panel, weak screenshotCoordinator] in
            guard screenshotCoordinator?.isCapturing != true else { return }
            panel?.toggle()
        }
        hotkeys.onCaptureScreenshot = { [weak screenshotCoordinator] in
            screenshotCoordinator?.capture()
        }

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
        let statusItem = StatusItemController(
            panelController: panel,
            recording: recording,
            onCaptureScreenshot: { [weak screenshotCoordinator] in
                screenshotCoordinator?.capture()
            },
            onScreenCapturePermissions: { [weak screenshotCoordinator] in
                screenshotCoordinator?.openPermissionSettings()
            }
        )

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
        self.screenshotCoordinator = screenshotCoordinator

        NSLog("[magpie] launched. ⌘P toggles panel, ⌘J captures screenshot, Esc hides panel. clips=%d snippets=%d",
              vm.clips.count, snippetsVM.snippets.count)

        // Explain permissions before requesting them; normal launches are quiet.
        if GettingStartedPreferences().needsPresentation {
            GettingStartedController.shared.show()
        }

    }

    private static var isRunningUnitTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    @objc private func handleHotkeyLifecycleNotification(_ notification: Notification) {
        guard let event = HotkeyLifecycleEvent(notificationName: notification.name) else {
            NSLog("[hotkey] ignored lifecycle")
            return
        }
        NSLog("[hotkey] lifecycle")
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
