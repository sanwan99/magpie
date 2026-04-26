import SwiftUI

struct ShortcutsPane: View {
    let language: AppLanguage

    private var entries: [Entry] {
        let text = SettingsText(language: language)
        return [
            .init(keys: ["⌘", "P"],          action: text.shortcutShowHidePanel,      scope: text.scopeGlobal),
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
