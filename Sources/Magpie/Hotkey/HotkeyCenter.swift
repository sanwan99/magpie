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
}
