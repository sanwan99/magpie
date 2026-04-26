import SwiftUI

struct ShortcutsPane: View {
    private let entries: [Entry] = [
        .init(keys: ["⌘", "P"],          action: "Show / hide panel",                               scope: "Global"),
        .init(keys: ["⌘", ","],          action: "Open Settings",                                    scope: "Global"),
        .init(keys: ["↵"],               action: "Paste focused clip",                               scope: "Panel"),
        .init(keys: ["⌘", "1"],          action: "Quick paste clip 1 (also ⌘2…⌘9)",                  scope: "Panel"),
        .init(keys: ["Click"],           action: "Focus + show Detail Pane",                         scope: "Panel"),
        .init(keys: ["Double-click"],    action: "Focus + paste",                                    scope: "Panel"),
        .init(keys: ["←", "↑"],          action: "Move focus toward older clips",                    scope: "Panel"),
        .init(keys: ["→", "↓"],          action: "Move focus toward newer clips",                    scope: "Panel"),
        .init(keys: ["⌘", "D"],          action: "Pin / unpin focused clip",                         scope: "Panel"),
        .init(keys: ["⌘", "\\"],         action: "Cycle layout (Stripe → Stack → Grid)",             scope: "Panel"),
        .init(keys: ["Space"],           action: "Toggle Detail Pane (when search field is empty)",  scope: "Panel"),
        .init(keys: ["Esc"],             action: "Cancel cascade (clear search → filter → close)",   scope: "Panel"),
    ]

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
