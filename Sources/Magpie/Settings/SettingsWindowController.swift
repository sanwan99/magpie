import AppKit
import SwiftUI

/// Manages the lifecycle of the Settings window.
/// Reuses a single window instance — opening Settings while it's already
/// visible just brings it to the front instead of stacking modals.
@MainActor
final class SettingsWindowController {
    static let shared = SettingsWindowController()

    private var window: NSWindow?

    private init() {}

    func show() {
        if let existing = window {
            NSApp.activate()
            existing.makeKeyAndOrderFront(nil)
            return
        }

        // Lazy-create on first open so we don't pay for SettingsView until needed.
        let host = NSHostingController(rootView: SettingsView(store: SettingsStore.shared))
        let win = NSWindow(contentViewController: host)
        win.title = SettingsText(language: SettingsStore.shared.language).windowTitle
        win.styleMask = [.titled, .closable, .miniaturizable]
        win.isReleasedWhenClosed = false
        win.center()
        win.setFrameAutosaveName("MagpieSettingsWindow")

        // Settings is a regular activating window — unlike the panel, we want
        // it to be the user's foreground app while they're tweaking preferences.
        NSApp.activate()
        win.makeKeyAndOrderFront(nil)
        self.window = win
        observeSettingsTitle()
    }

    private func observeSettingsTitle() {
        let store = SettingsStore.shared
        func track() {
            withObservationTracking {
                _ = store.language
            } onChange: { [weak self] in
                Task { @MainActor in
                    self?.window?.title = SettingsText(language: store.language).windowTitle
                    track()
                }
            }
        }
        track()
    }
}

struct GettingStartedPreferences {
    var defaults: UserDefaults = .standard
    var needsPresentation: Bool { !defaults.bool(forKey: "magpie.onboarding.completed") }
    func complete() { defaults.set(true, forKey: "magpie.onboarding.completed") }
}

@MainActor
final class GettingStartedController {
    static let shared = GettingStartedController()
    private var window: NSWindow?

    func show() {
        if let window {
            NSApp.activate()
            window.makeKeyAndOrderFront(nil)
            return
        }
        let view = GettingStartedView(store: .shared) { [weak self] in
            GettingStartedPreferences().complete()
            self?.window?.close()
        }
        let window = NSWindow(contentViewController: NSHostingController(rootView: view))
        window.title = "Magpie"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.center()
        self.window = window
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }
}

private struct GettingStartedView: View {
    @Bindable var store: SettingsStore
    let onComplete: () -> Void
    @State private var accessibilityGranted = AXIsProcessTrusted()

    var body: some View {
        let language = store.language
        VStack(alignment: .leading, spacing: 18) {
            Text(language.pick(zh: "欢迎使用 Magpie", en: "Welcome to Magpie"))
                .font(.title.bold())
            Text(language.pick(
                zh: "复制一段普通文字，从菜单栏打开面板，选中记录后按回车粘贴。默认 ⌘P 打开历史，⌘J 截图；冲突时可在设置中更改。",
                en: "Copy some ordinary text, open the panel from the menu bar, and press Return on a record to paste. Defaults: ⌘P for history, ⌘J for capture. Change conflicting shortcuts in Settings."))
            Divider()
            Label(language.pick(
                zh: accessibilityGranted ? "辅助功能已授权" : "自动粘贴需要辅助功能权限",
                en: accessibilityGranted ? "Accessibility is enabled" : "Automatic paste needs Accessibility"),
                systemImage: accessibilityGranted ? "checkmark.circle" : "hand.raised")
            Text(language.pick(
                zh: "不授权也能浏览历史并复制后手动 ⌘V。仅在你主动截图时请求屏幕录制权限。",
                en: "You can browse and copy history without granting access, then paste manually with ⌘V. Screen Recording is requested only when you capture."))
                .foregroundStyle(.secondary)
            HStack {
                Button(language.pick(zh: "请求辅助功能权限", en: "Request Accessibility")) {
                    let key = "AXTrustedCheckOptionPrompt" as CFString
                    accessibilityGranted = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
                }
                .disabled(accessibilityGranted)
                Button(language.pick(zh: "打开权限设置", en: "Open Permission Settings")) {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
            Divider()
            Text(language.pick(
                zh: "历史保存在本机，当前未加密。秘密过滤可能漏判；菜单栏可暂停记录 15 分钟／1 小时，或忽略当前应用。暂停期间的内容不会在恢复后补录。",
                en: "History stays in local, unencrypted storage. Secret detection can miss sensitive data. Use the menu bar to pause for 15 minutes / 1 hour or ignore the current app. Paused copies are not imported on resume."))
            HStack {
                Button(language.pick(zh: "打开设置", en: "Open Settings")) { SettingsWindowController.shared.show() }
                Spacer()
                Button(language.pick(zh: "开始使用", en: "Get Started"), action: onComplete)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(28)
        .frame(width: 540)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            accessibilityGranted = AXIsProcessTrusted()
        }
    }
}
