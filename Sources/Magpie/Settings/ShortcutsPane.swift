import SwiftUI

struct ShortcutsPane: View {
    let language: AppLanguage

    private var entries: [Entry] {
        let text = SettingsText(language: language)
        return [
            .init(keys: ["⌘", "P"],          action: text.shortcutShowHidePanel,      scope: text.scopeGlobal),
            .init(keys: ["⌘", "J"],          action: text.shortcutCaptureScreenshot, scope: text.scopeGlobal),
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
