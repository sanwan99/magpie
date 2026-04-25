import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var panelController: PanelController?
    private var hotkeyCenter: HotkeyCenter?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let panel = PanelController()
        let hotkeys = HotkeyCenter()
        hotkeys.onTogglePanel = { [weak panel] in
            panel?.toggle()
        }
        self.panelController = panel
        self.hotkeyCenter = hotkeys
        NSLog("Magpie launched. Press ⌘P to toggle panel; Esc to hide.")
    }
}
