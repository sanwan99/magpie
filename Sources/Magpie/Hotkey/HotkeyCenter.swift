import AppKit
import HotKey

/// Owns the global hotkeys. v0.1 wires only ⌘P (toggle panel).
/// Esc is handled inside the panel as a local key event, not a global hotkey.
@MainActor
final class HotkeyCenter {
    private var togglePanelHotKey: HotKey?

    var onTogglePanel: (() -> Void)?

    init() {
        registerTogglePanel()
    }

    private func registerTogglePanel() {
        let hotkey = HotKey(key: .p, modifiers: [.command])
        hotkey.keyDownHandler = { [weak self] in
            self?.onTogglePanel?()
        }
        self.togglePanelHotKey = hotkey
    }

    /// 重新注册全局热键。AppDelegate 在 sleep/wake 后调用，因为 Carbon
    /// `RegisterEventHotKey` 在某些 macOS 唤醒场景下会悄悄丢注册。
    /// 释放旧 HotKey 实例（HotKey 库 deinit 时调 UnregisterEventHotKey）
    /// 再重建。
    func reregister() {
        NSLog("[hotkey] re-registering ⌘P after wake/refresh")
        togglePanelHotKey = nil
        registerTogglePanel()
    }
}
