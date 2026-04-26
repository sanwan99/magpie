import Foundation
import Observation

/// Global app preferences. `@Observable` so SwiftUI views subscribe per-keypath.
/// Each property has a UserDefaults-backed `didSet` for persistence.
@MainActor
@Observable
final class SettingsStore {
    static let shared = SettingsStore()

    // MARK: - Appearance

    var theme: AppTheme = .system {
        didSet { UserDefaults.standard.set(theme.rawValue, forKey: Keys.theme) }
    }

    /// 0…60 — mapped to NSVisualEffectView material in `vibrancyMaterial`.
    var vibrancy: Double = 36 {
        didSet { UserDefaults.standard.set(vibrancy, forKey: Keys.vibrancy) }
    }

    var flavor: Flavor = .mono {
        didSet { UserDefaults.standard.set(flavor.rawValue, forKey: Keys.flavor) }
    }

    // MARK: - Behavior toggles

    var launchAtLogin: Bool = false {
        didSet { UserDefaults.standard.set(launchAtLogin, forKey: Keys.launchAtLogin) }
    }

    var showRecentFirst: Bool = true {
        didSet { UserDefaults.standard.set(showRecentFirst, forKey: Keys.showRecentFirst) }
    }

    var detectColorsAndLinks: Bool = true {
        didSet { UserDefaults.standard.set(detectColorsAndLinks, forKey: Keys.detectColorsAndLinks) }
    }

    /// v0.2-c only stores the toggle; actual URL-stripping logic lands in v0.3.
    var stripTrackingFromURLs: Bool = false {
        didSet { UserDefaults.standard.set(stripTrackingFromURLs, forKey: Keys.stripTracking) }
    }

    /// Snippets auto-expansion (typing `;sig` anywhere triggers replacement).
    /// Default OFF — needs Input Monitoring permission, may feel invasive
    /// to users who don't use snippets. Enable explicitly in Settings.
    var autoExpandSnippets: Bool = false {
        didSet { UserDefaults.standard.set(autoExpandSnippets, forKey: Keys.autoExpand) }
    }

    // MARK: - Init / restore

    private init() {
        let defaults = UserDefaults.standard
        if let raw = defaults.string(forKey: Keys.theme),
           let restored = AppTheme(rawValue: raw) {
            self.theme = restored
        }
        if defaults.object(forKey: Keys.vibrancy) != nil {
            let stored = defaults.double(forKey: Keys.vibrancy)
            // Clamp to valid range in case the user (or a stale write) put garbage in.
            self.vibrancy = max(0, min(60, stored))
        }
        if let raw = defaults.string(forKey: Keys.flavor),
           let restored = Flavor(rawValue: raw) {
            self.flavor = restored
        }
        if defaults.object(forKey: Keys.launchAtLogin) != nil {
            self.launchAtLogin = defaults.bool(forKey: Keys.launchAtLogin)
        }
        if defaults.object(forKey: Keys.showRecentFirst) != nil {
            self.showRecentFirst = defaults.bool(forKey: Keys.showRecentFirst)
        }
        if defaults.object(forKey: Keys.detectColorsAndLinks) != nil {
            self.detectColorsAndLinks = defaults.bool(forKey: Keys.detectColorsAndLinks)
        }
        if defaults.object(forKey: Keys.stripTracking) != nil {
            self.stripTrackingFromURLs = defaults.bool(forKey: Keys.stripTracking)
        }
        if defaults.object(forKey: Keys.autoExpand) != nil {
            self.autoExpandSnippets = defaults.bool(forKey: Keys.autoExpand)
        }
    }

    // MARK: - Keys

    private enum Keys {
        static let theme = "magpie.settings.theme"
        static let vibrancy = "magpie.settings.vibrancy"
        static let flavor = "magpie.settings.flavor"
        static let launchAtLogin = "magpie.settings.launchAtLogin"
        static let showRecentFirst = "magpie.settings.showRecentFirst"
        static let detectColorsAndLinks = "magpie.settings.detectColorsAndLinks"
        static let stripTracking = "magpie.settings.stripTracking"
        static let autoExpand = "magpie.settings.autoExpandSnippets"
    }
}
