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

    // MARK: - History (v0.3-c)

    /// 0 = keep forever; otherwise expire non-pinned clips older than this many days.
    var keepHistoryDays: Int = 0 {
        didSet { UserDefaults.standard.set(keepHistoryDays, forKey: Keys.keepDays) }
    }

    /// Max number of non-pinned clips. 0 = unlimited.
    var maxItems: Int = 2000 {
        didSet { UserDefaults.standard.set(maxItems, forKey: Keys.maxItems) }
    }

    /// Bundle identifiers whose clipboard activity is never ingested
    /// (e.g. com.agilebits.onepassword for 1Password).
    var ignoredApps: [String] = [] {
        didSet {
            UserDefaults.standard.set(ignoredApps, forKey: Keys.ignoredApps)
        }
    }

    // MARK: - Privacy (v0.3-c)

    /// Require Touch ID on first panel show after launch.
    var useTouchID: Bool = false {
        didSet { UserDefaults.standard.set(useTouchID, forKey: Keys.touchID) }
    }

    /// Filter out clips that look like API keys / tokens / passwords.
    var skipSecretLooking: Bool = true {
        didSet { UserDefaults.standard.set(skipSecretLooking, forKey: Keys.skipSecret) }
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
        if defaults.object(forKey: Keys.keepDays) != nil {
            self.keepHistoryDays = max(0, defaults.integer(forKey: Keys.keepDays))
        }
        if defaults.object(forKey: Keys.maxItems) != nil {
            self.maxItems = max(0, defaults.integer(forKey: Keys.maxItems))
        }
        if let arr = defaults.stringArray(forKey: Keys.ignoredApps) {
            self.ignoredApps = arr
        }
        if defaults.object(forKey: Keys.touchID) != nil {
            self.useTouchID = defaults.bool(forKey: Keys.touchID)
        }
        if defaults.object(forKey: Keys.skipSecret) != nil {
            self.skipSecretLooking = defaults.bool(forKey: Keys.skipSecret)
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
        static let keepDays = "magpie.settings.keepHistoryDays"
        static let maxItems = "magpie.settings.maxItems"
        static let ignoredApps = "magpie.settings.ignoredApps"
        static let touchID = "magpie.settings.useTouchID"
        static let skipSecret = "magpie.settings.skipSecretLooking"
    }
}
