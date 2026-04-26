import SwiftUI

/// Top-level Settings tabbed modal — General + Shortcuts (v0.2 scope).
/// History + Privacy panes land in v0.3.
struct SettingsView: View {
    @Bindable var store: SettingsStore

    var body: some View {
        TabView {
            GeneralPane(store: store)
                .tabItem {
                    Label("General", systemImage: "gearshape")
                }

            ShortcutsPane()
                .tabItem {
                    Label("Shortcuts", systemImage: "command")
                }

            HistoryPane(store: store)
                .tabItem {
                    Label("History", systemImage: "clock.arrow.circlepath")
                }

            PrivacyPane(store: store)
                .tabItem {
                    Label("Privacy", systemImage: "lock.shield")
                }
        }
        .frame(width: 500, height: 480)
    }
}
