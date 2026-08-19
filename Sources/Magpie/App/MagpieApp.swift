import SwiftUI

@main
struct MagpieApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("设置…") {
                    Task { @MainActor in
                        SettingsWindowController.shared.show()
                    }
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }
    }
}
