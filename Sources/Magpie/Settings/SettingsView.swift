import SwiftUI

/// Top-level Settings tabbed modal — General + Shortcuts (v0.2 scope).
/// History + Privacy panes land in v0.3.
struct SettingsView: View {
    @Bindable var store: SettingsStore

    var body: some View {
        let text = SettingsText(language: store.language)

        TabView {
            GeneralPane(store: store)
                .tabItem {
                    Label(text.generalTab, systemImage: "gearshape")
                }

            ShortcutsPane(language: store.language)
                .tabItem {
                    Label(text.shortcutsTab, systemImage: "command")
                }

            HistoryPane(store: store)
                .tabItem {
                    Label(text.historyTab, systemImage: "clock.arrow.circlepath")
                }

            PrivacyPane(store: store)
                .tabItem {
                    Label(text.privacyTab, systemImage: "lock.shield")
                }
        }
        .frame(width: 500, height: 480)
    }
}
