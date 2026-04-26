import AppKit
import SwiftUI

/// Manages the lifecycle of the Settings window.
/// Reuses a single window instance — opening Settings while it's already
/// visible just brings it to the front instead of stacking modals.
@MainActor
final class SettingsWindowController {
    static let shared = SettingsWindowController()

    private var window: NSWindow?

    private init() {}

    func show() {
        if let existing = window, existing.isVisible {
            NSApp.activate()
            existing.makeKeyAndOrderFront(nil)
            return
        }

        // Lazy-create on first open so we don't pay for SettingsView until needed.
        let host = NSHostingController(rootView: SettingsView(store: SettingsStore.shared))
        let win = NSWindow(contentViewController: host)
        win.title = SettingsText(language: SettingsStore.shared.language).windowTitle
        win.styleMask = [.titled, .closable, .miniaturizable]
        win.isReleasedWhenClosed = false
        win.center()
        win.setFrameAutosaveName("MagpieSettingsWindow")

        // Settings is a regular activating window — unlike the panel, we want
        // it to be the user's foreground app while they're tweaking preferences.
        NSApp.activate()
        win.makeKeyAndOrderFront(nil)
        self.window = win
        observeSettingsTitle()
    }

    private func observeSettingsTitle() {
        let store = SettingsStore.shared
        func track() {
            withObservationTracking {
                _ = store.language
            } onChange: { [weak self] in
                Task { @MainActor in
                    self?.window?.title = SettingsText(language: store.language).windowTitle
                    track()
                }
            }
        }
        track()
    }
}
