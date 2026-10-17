import SwiftUI
import Carbon

struct ShortcutsPane: View {
    let language: AppLanguage

    private var entries: [Entry] {
        let text = SettingsText(language: language)
        return [

            .init(keys: ["⌘", ","],          action: text.shortcutOpenSettings,       scope: text.scopeGlobal),
            .init(keys: ["↵"],               action: text.shortcutPasteFocused,       scope: text.scopePanel),
            .init(keys: ["⌘", "1"],          action: text.shortcutQuickPaste,         scope: text.scopePanel),
            .init(keys: [text.keyClick],     action: text.shortcutClickFocus,         scope: text.scopePanel),
            .init(keys: [text.keyDoubleClick], action: text.shortcutDoubleClickPaste, scope: text.scopePanel),
            .init(keys: ["←", "↑"],          action: text.shortcutMoveOlder,          scope: text.scopePanel),
            .init(keys: ["→", "↓"],          action: text.shortcutMoveNewer,          scope: text.scopePanel),
            .init(keys: ["⌘", "D"],          action: text.shortcutPin,                scope: text.scopePanel),
            .init(keys: ["⌘", "\\"],         action: text.shortcutCycleLayout,        scope: text.scopePanel),
            .init(keys: [text.keySpace],     action: text.shortcutToggleDetail,       scope: text.scopePanel),
            .init(keys: ["Esc"],             action: text.shortcutCancelCascade,      scope: text.scopePanel),
            .init(keys: ["V", "R", "O", "A"], action: language.pick(zh: "选区 / 矩形 / 椭圆 / 箭头", en: "Select / Rectangle / Ellipse / Arrow"), scope: language.pick(zh: "截图", en: "Capture")),
            .init(keys: ["P", "T", "M"], action: language.pick(zh: "画笔 / 文字 / 马赛克", en: "Pen / Text / Mosaic"), scope: language.pick(zh: "截图", en: "Capture")),
            .init(keys: ["C", "[", "]"], action: language.pick(zh: "颜色 / 减细 / 加粗", en: "Color / Thinner / Thicker"), scope: language.pick(zh: "截图", en: "Capture")),
            .init(keys: ["⌘", "Z"], action: language.pick(zh: "撤销；⇧⌘Z 重做", en: "Undo; ⇧⌘Z to redo"), scope: language.pick(zh: "截图", en: "Capture")),
            .init(keys: ["↵", "⌘C"], action: language.pick(zh: "复制截图", en: "Copy screenshot"), scope: language.pick(zh: "截图", en: "Capture")),
            .init(keys: ["⌘", "S"], action: language.pick(zh: "保存 PNG", en: "Save PNG"), scope: language.pick(zh: "截图", en: "Capture")),
            .init(keys: ["⌘", "A"], action: language.pick(zh: "选择当前整屏", en: "Select entire screen"), scope: language.pick(zh: "截图", en: "Capture")),
            .init(keys: ["↑", "↓", "←", "→"], action: language.pick(zh: "移动选区；⇧ 加速，⌥ 调整大小", en: "Move selection; ⇧ faster, ⌥ resize"), scope: language.pick(zh: "截图", en: "Capture")),
            .init(keys: ["Esc"], action: language.pick(zh: "取消截图", en: "Cancel screenshot"), scope: language.pick(zh: "截图", en: "Capture")),
            .init(keys: ["E"], action: language.pick(zh: "表情 / 自定义表情", en: "Stickers / custom emoji"), scope: language.pick(zh: "截图", en: "Capture")),
            .init(keys: ["X", "L"], action: language.pick(zh: "提取文字 / 系统翻译", en: "OCR / local translation"), scope: language.pick(zh: "截图", en: "Capture")),
            .init(keys: ["D", "N", "G"], action: language.pick(zh: "一键打码 / 贴图 / 长截图", en: "Redact / Pin / Scroll"), scope: language.pick(zh: "截图", en: "Capture")),
            .init(keys: ["⇧", "⌘", "S"], action: language.pick(zh: "系统分享", en: "System sharing"), scope: language.pick(zh: "截图", en: "Capture")),
            .init(keys: ["Delete"], action: language.pick(zh: "删除选中标注", en: "Delete selected annotation"), scope: language.pick(zh: "截图", en: "Capture")),
            .init(keys: ["⇧", "↵"], action: language.pick(zh: "文字换行", en: "New line in text"), scope: language.pick(zh: "截图", en: "Capture")),
        ]
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                GlobalShortcutEditor(action: .togglePanel, language: language)
                GlobalShortcutEditor(action: .captureScreenshot, language: language)
                Text(language.pick(zh: "请选择字母或数字及修饰键。占用冲突会拒绝保存；部分系统快捷键需在系统设置中检查。", en: "Choose a letter or digit and modifiers. Registration conflicts are rejected; check System Settings for reserved shortcuts."))
                    .font(.caption).foregroundStyle(.secondary).padding(.vertical, 8)
                ForEach(entries) { entry in
                    Row(entry: entry)
                    Divider().opacity(0.3)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private struct Entry: Identifiable {
        let keys: [String]
        let action: String
        let scope: String
        var id: String { keys.joined() + action }
    }

    private struct Row: View {
        let entry: Entry
        var body: some View {
            HStack(alignment: .center, spacing: 12) {
                HStack(spacing: 4) {
                    ForEach(entry.keys, id: \.self) { k in
                        Text(k)
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(Color.primary.opacity(0.08))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 4)
                                    .strokeBorder(Color.primary.opacity(0.10), lineWidth: 0.5)
                            )
                    }
                }
                .frame(width: 110, alignment: .leading)

                Text(entry.action)
                    .font(.system(size: 12))
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text(entry.scope)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .frame(width: 56, alignment: .trailing)
            }
            .padding(.vertical, 6)
        }
    }
}

@MainActor
private struct GlobalShortcutEditor: View {
    let action: GlobalHotkeyAction
    let language: AppLanguage
    @State private var keyCode: UInt32 = 35
    @State private var command = true
    @State private var control = false
    @State private var option = false
    @State private var shift = false
    @State private var message = ""

    var body: some View {
        VStack(alignment: .leading) {
            Text(action == .togglePanel ? SettingsText(language: language).shortcutShowHidePanel
                 : SettingsText(language: language).shortcutCaptureScreenshot).font(.headline)
            HStack {
                Picker("Key", selection: $keyCode) {
                    ForEach(HotkeyBinding.letters.keys.sorted(), id: \.self) { code in
                        Text(HotkeyBinding.letters[code] ?? "?").tag(code)
                    }
                }.frame(width: 85)
                Toggle("⌘", isOn: $command)
                Toggle("⌃", isOn: $control)
                Toggle("⌥", isOn: $option)
                Toggle("⇧", isOn: $shift)
                Button(language.pick(zh: "保存", en: "Save")) { save() }
                Button(language.pick(zh: "默认", en: "Default")) {
                    restore(HotkeyBinding(keyCode: action.keyCode, modifiers: action.modifiers)); save()
                }
            }
            if !message.isEmpty { Text(message).font(.caption).foregroundStyle(.secondary) }
        }
        .padding(.vertical, 8)
        .onAppear {
            restore(HotkeyCenter.current?.binding(for: action)
                    ?? HotkeyBinding(keyCode: action.keyCode, modifiers: action.modifiers))
            if HotkeyCenter.current?.diagnosticsSnapshot.registrationFailures[action] != nil {
                message = language.pick(zh: "当前热键注册失败，请更换组合。", en: "Registration failed. Choose another shortcut.")
            }
        }
    }

    private func restore(_ binding: HotkeyBinding) {
        keyCode = binding.keyCode
        command = binding.modifiers & UInt32(cmdKey) != 0
        control = binding.modifiers & UInt32(controlKey) != 0
        option = binding.modifiers & UInt32(optionKey) != 0
        shift = binding.modifiers & UInt32(shiftKey) != 0
    }
    private func save() {
        let modifiers = (command ? UInt32(cmdKey) : 0) | (control ? UInt32(controlKey) : 0)
            | (option ? UInt32(optionKey) : 0) | (shift ? UInt32(shiftKey) : 0)
        let binding = HotkeyBinding(keyCode: keyCode, modifiers: modifiers)
        if HotkeyCenter.current?.setBinding(binding, for: action) == true {
            message = language.pick(zh: "已保存：", en: "Saved: ") + binding.displayName
        } else {
            message = language.pick(zh: "组合无效或已被占用，原快捷键保持不变。", en: "Invalid or unavailable shortcut. The previous binding is unchanged.")
        }
    }
}
