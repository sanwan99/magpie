import AppKit

/// 菜单栏图标 — 即使全局 ⌘P 失效也能从这里召出面板 / 进设置 / 退出。
///
/// 设计取舍：
/// - **变宽 NSStatusItem**：只显示图标，不带文字，跟 macOS 主流剪切板工具
///   （Maccy / Paste / Raycast）一致。
/// - **NSMenu 而非 popover**：左键单击直接弹菜单是最低惊讶；不做"左键召面板
///   右键弹菜单"那种 split 行为，避免新用户找不到设置入口。
@MainActor
final class StatusItemController: NSObject {
    private let statusItem: NSStatusItem
    private weak var panelController: PanelController?

    init(panelController: PanelController) {
        self.panelController = panelController
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
        button.toolTip = "Magpie · 剪切板管理器（⌘P 召出面板）"
    }

    // MARK: - Menu

    private func configureMenu() {
        let menu = NSMenu()

        let show = NSMenuItem(title: "显示面板", action: #selector(togglePanel), keyEquivalent: "p")
        show.target = self
        show.keyEquivalentModifierMask = [.command]
        menu.addItem(show)

        menu.addItem(NSMenuItem.separator())

        let settings = NSMenuItem(title: "设置…", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        settings.keyEquivalentModifierMask = [.command]
        menu.addItem(settings)

        let about = NSMenuItem(title: "关于 Magpie", action: #selector(openAbout), keyEquivalent: "")
        about.target = self
        menu.addItem(about)

        menu.addItem(NSMenuItem.separator())

        let quit = NSMenuItem(title: "退出 Magpie", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        quit.keyEquivalentModifierMask = [.command]
        menu.addItem(quit)

        statusItem.menu = menu
    }

    // MARK: - Actions

    @objc private func togglePanel() {
        panelController?.toggle()
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
