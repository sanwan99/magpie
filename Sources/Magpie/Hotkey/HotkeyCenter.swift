import AppKit
import HotKey

/// Owns the global hotkeys. v0.1 wires only ⌘P (toggle panel).
/// Esc is handled inside the panel as a local key event, not a global hotkey.
@MainActor
final class HotkeyCenter {
    private var togglePanelHotKey: HotKey?
    private var keepAliveTimer: Timer?

    var onTogglePanel: (() -> Void)?

    init() {
        registerTogglePanel()
        startKeepAliveTimer()
    }

    deinit {
        keepAliveTimer?.invalidate()
    }

    private func registerTogglePanel() {
        let hotkey = HotKey(key: .p, modifiers: [.command])
        hotkey.keyDownHandler = { [weak self] in
            self?.onTogglePanel?()
        }
        self.togglePanelHotKey = hotkey
    }

    /// 重新注册全局热键。AppDelegate 在 sleep/wake / Space 切换 / 屏幕唤醒
    /// 后调用；此外内部 30s 心跳定时器主动调，盖系统通知没发出来的边缘情况。
    /// 释放旧 HotKey 实例（HotKey 库 deinit 时调 UnregisterEventHotKey）再
    /// 重建。无脑重注册成本极低（一次 Carbon API 调用），即便没失效也无副作用。
    func reregister() {
        NSLog("[hotkey] re-registering ⌘P (event-driven or keepAlive)")
        togglePanelHotKey = nil
        registerTogglePanel()
    }

    /// 心跳定时器：每 30s 主动重注册一次 ⌘P。
    ///
    /// 为什么需要：实测 NSWorkspace 的 didWake / activeSpaceDidChange /
    /// screensDidWake 三类通知**并不能覆盖所有让 Carbon RegisterEventHotKey
    /// 失效的场景**（尤其 macOS 14+ 在某些焦点切换 / 进程挂起恢复后），用户
    /// 多次反馈"过一会就唤不醒"。心跳兜底虽然粗糙但 100% 有效，30s 间隔也
    /// 不会有可观察的资源开销（单次重注册是 microsecond 级别）。
    private func startKeepAliveTimer() {
        keepAliveTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.reregister()
            }
        }
    }
}
