import AppKit

/// 菜单栏图标 — 即使全局 ⌘P 失效也能从这里召出面板 / 进设置 / 退出。
///
/// 设计取舍：
/// - **变宽 NSStatusItem**：只显示图标，不带文字，跟 macOS 主流剪切板工具
///   （Maccy / Paste / Raycast）一致。
/// - **NSMenu 而非 popover**：左键单击直接弹菜单是最低惊讶；不做"左键召面板
///   右键弹菜单"那种 split 行为，避免新用户找不到设置入口。
@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    private let statusItem: NSStatusItem
    private weak var panelController: PanelController?
    private let recording: ClipboardRecordingControl
    private var ignoredApplication: NSRunningApplication?
    private var recordingItem: NSMenuItem?
    private var resumeItem: NSMenuItem?
    private var ignoreItem: NSMenuItem?
    private let onCaptureScreenshot: () -> Void
    private let onScreenCapturePermissions: () -> Void

    init(panelController: PanelController, recording: ClipboardRecordingControl,
         onCaptureScreenshot: @escaping () -> Void,
         onScreenCapturePermissions: @escaping () -> Void) {
        self.panelController = panelController
        self.recording = recording
        self.onCaptureScreenshot = onCaptureScreenshot
        self.onScreenCapturePermissions = onScreenCapturePermissions
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        configureButton()
        configureMenu()
    }

    // MARK: - Button

    private func configureButton() {
        guard let button = statusItem.button else { return }
        // SF Symbol：剪切板上叠一只笔，比较切"剪切板管理器"主题；找不到时
        // 退到剪刀（最通用的剪切板隐喻）。
        let primary = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: "Magpie")
        button.image = primary ?? NSImage(systemSymbolName: "scissors", accessibilityDescription: "Magpie")
        button.image?.isTemplate = true  // 跟随系统暗 / 亮主题反色
        button.toolTip = "Magpie · 剪切板管理器"
    }

    // MARK: - Menu

    private func configureMenu() {
        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false

        let show = NSMenuItem(title: "显示面板", action: #selector(togglePanel), keyEquivalent: "p")
        show.target = self
        show.keyEquivalentModifierMask = [.command]
        menu.addItem(show)

        let language = SettingsStore.shared.language
        let capture = NSMenuItem(
            title: language.pick(zh: "截图…", en: "Capture Screenshot…"),
            action: #selector(captureScreenshot),
            keyEquivalent: "j"
        )
        capture.target = self
        capture.keyEquivalentModifierMask = [.command]
        menu.addItem(capture)
        let permission = NSMenuItem(title: language.pick(zh: "屏幕录制权限…", en: "Screen Recording Permission…"),
                                    action: #selector(openScreenCapturePermissions), keyEquivalent: "")
        permission.target = self
        menu.addItem(permission)

        menu.addItem(NSMenuItem.separator())
        let recordingState = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        recordingState.isEnabled = false
        menu.addItem(recordingState)
        recordingItem = recordingState
        for (minutes, title) in [(15, language.pick(zh: "暂停记录 15 分钟", en: "Pause Recording for 15 Minutes")),
                                  (60, language.pick(zh: "暂停记录 1 小时", en: "Pause Recording for 1 Hour"))] {
            let item = NSMenuItem(title: title, action: #selector(pauseRecording(_:)), keyEquivalent: "")
            item.tag = minutes
            item.target = self
            menu.addItem(item)
        }
        let resume = NSMenuItem(title: language.pick(zh: "恢复记录", en: "Resume Recording"), action: #selector(resumeRecording), keyEquivalent: "")
        resume.target = self
        menu.addItem(resume)
        resumeItem = resume
        let ignore = NSMenuItem(title: "", action: #selector(ignoreCurrentApplication), keyEquivalent: "")
        ignore.target = self
        menu.addItem(ignore)
        ignoreItem = ignore
        menu.addItem(NSMenuItem.separator())
        let guide = NSMenuItem(title: language.pick(zh: "使用入门与权限…", en: "Getting Started & Permissions…"),
                               action: #selector(openGettingStarted), keyEquivalent: "")
        guide.target = self
        menu.addItem(guide)

        let settings = NSMenuItem(title: "设置…", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        settings.keyEquivalentModifierMask = [.command]
        menu.addItem(settings)

        let about = NSMenuItem(title: "关于 Magpie", action: #selector(openAbout), keyEquivalent: "")
        about.target = self
        menu.addItem(about)

        menu.addItem(NSMenuItem.separator())

        let quit = NSMenuItem(title: "退出 Magpie", action: #selector(quit), keyEquivalent: "")
        quit.target = self
        menu.addItem(quit)

        statusItem.menu = menu
        refreshRecordingStatus()
    }

    func menuWillOpen(_ menu: NSMenu) {
        let language = SettingsStore.shared.language
        for item in menu.items {
            if item.action == #selector(togglePanel) { item.title = language.pick(zh: "显示面板", en: "Show Panel") }
            if item.action == #selector(captureScreenshot) { item.title = language.pick(zh: "截图…", en: "Capture Screenshot…") }
            if item.action == #selector(openScreenCapturePermissions) { item.title = language.pick(zh: "屏幕录制权限…", en: "Screen Recording Permission…") }
            if item.action == #selector(openSettings) { item.title = language.pick(zh: "设置…", en: "Settings…") }
            if item.action == #selector(openAbout) { item.title = language.pick(zh: "关于 Magpie", en: "About Magpie") }
            if item.action == #selector(quit) { item.title = language.pick(zh: "退出 Magpie", en: "Quit Magpie") }
            if item.action == #selector(openGettingStarted) { item.title = language.pick(zh: "使用入门与权限…", en: "Getting Started & Permissions…") }
            if item.action == #selector(resumeRecording) { item.title = language.pick(zh: "恢复记录", en: "Resume Recording") }
            if item.action == #selector(pauseRecording(_:)) {
                item.title = item.tag == 15
                    ? language.pick(zh: "暂停记录 15 分钟", en: "Pause Recording for 15 Minutes")
                    : language.pick(zh: "暂停记录 1 小时", en: "Pause Recording for 1 Hour")
            }
        }
        let frontmost = NSWorkspace.shared.frontmostApplication
        ignoredApplication = frontmost?.processIdentifier == ProcessInfo.processInfo.processIdentifier ? nil : frontmost
        let id = ignoredApplication?.bundleIdentifier
        let canIgnore = id != nil && !SettingsStore.shared.ignoredApps.contains(id!)
        ignoreItem?.title = canIgnore
            ? language.pick(zh: "忽略当前应用：", en: "Ignore Current App: ") + (ignoredApplication?.localizedName ?? id!)
            : language.pick(zh: "当前应用已忽略或不可识别", en: "Current App Ignored or Unavailable")
        ignoreItem?.isEnabled = canIgnore
        refreshRecordingStatus()
        guard let center = HotkeyCenter.current else { return }
        for (index, action) in [GlobalHotkeyAction.togglePanel, .captureScreenshot].enumerated() {
            let binding = center.binding(for: action)
            menu.items[index].keyEquivalent = HotkeyBinding.letters[binding.keyCode]?.lowercased() ?? ""
            menu.items[index].keyEquivalentModifierMask = binding.cocoaModifiers
        }
    }

    func refreshRecordingStatus() {
        let paused = recording.isPaused
        let language = SettingsStore.shared.language
        let title: String
        if paused, let deadline = recording.pausedUntil {
            let time = DateFormatter.localizedString(from: deadline, dateStyle: .none, timeStyle: .short)
            title = language.pick(zh: "记录已暂停，恢复时间：", en: "Recording paused until ") + time
        } else {
            title = language.pick(zh: "剪贴板记录中", en: "Clipboard Recording On")
        }
        recordingItem?.title = title
        resumeItem?.isHidden = !paused
        statusItem.button?.toolTip = "Magpie · " + title
        statusItem.button?.image = NSImage(systemSymbolName: paused ? "pause.circle" : "doc.on.clipboard", accessibilityDescription: title)
        statusItem.button?.image?.isTemplate = true
    }

    @objc private func pauseRecording(_ sender: NSMenuItem) {
        recording.pause(for: TimeInterval(sender.tag * 60))
    }

    @objc private func resumeRecording() { recording.resume() }

    @objc private func ignoreCurrentApplication() {
        guard let app = ignoredApplication, !app.isTerminated,
              let id = app.bundleIdentifier,
              !SettingsStore.shared.ignoredApps.contains(id) else { return }
        SettingsStore.shared.ignoredApps.append(id)
    }

    @objc private func openGettingStarted() { GettingStartedController.shared.show() }

    // MARK: - Actions

    @objc private func togglePanel() {
        panelController?.toggle()
    }

    @objc private func captureScreenshot() {
        onCaptureScreenshot()
    }

    @objc private func openScreenCapturePermissions() {
        onScreenCapturePermissions()
    }

    @objc private func openSettings() {
        SettingsWindowController.shared.show()
    }

    @objc private func openAbout() {
        NSApp.orderFrontStandardAboutPanel(nil)
        NSApp.activate()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
