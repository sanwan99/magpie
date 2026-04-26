import Foundation
import Observation

enum AppLanguage: String, Codable, Sendable, CaseIterable {
    case zhHans
    case en

    var displayName: String {
        switch self {
        case .zhHans: return "中文"
        case .en:     return "English"
        }
    }

    func pick(zh: String, en: String) -> String {
        switch self {
        case .zhHans: return zh
        case .en:     return en
        }
    }
}

/// Global app preferences. `@Observable` so SwiftUI views subscribe per-keypath.
/// Each property has a UserDefaults-backed `didSet` for persistence.
@MainActor
@Observable
final class SettingsStore {
    static let shared = SettingsStore()

    // MARK: - Language

    var language: AppLanguage = .zhHans {
        didSet { UserDefaults.standard.set(language.rawValue, forKey: Keys.language) }
    }

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
        if let raw = defaults.string(forKey: Keys.language),
           let restored = AppLanguage(rawValue: raw) {
            self.language = restored
        }
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
        static let language = "magpie.settings.language"
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

struct SettingsText {
    let language: AppLanguage

    var windowTitle: String { language.pick(zh: "Magpie 设置", en: "Magpie Settings") }

    var generalTab: String { language.pick(zh: "通用", en: "General") }
    var shortcutsTab: String { language.pick(zh: "快捷键", en: "Shortcuts") }
    var historyTab: String { language.pick(zh: "历史", en: "History") }
    var privacyTab: String { language.pick(zh: "隐私", en: "Privacy") }

    var appearance: String { language.pick(zh: "外观", en: "Appearance") }
    var languageLabel: String { language.pick(zh: "语言", en: "Language") }
    var theme: String { language.pick(zh: "主题", en: "Theme") }
    var vibrancy: String { language.pick(zh: "毛玻璃强度", en: "Vibrancy") }
    var flavor: String { language.pick(zh: "风格", en: "Flavor") }
    var behavior: String { language.pick(zh: "行为", en: "Behavior") }
    var launchAtLogin: String { language.pick(zh: "开机时启动", en: "Launch at login") }
    var showRecentFirst: String { language.pick(zh: "最近项目优先显示", en: "Show recent first") }
    var detectColorsAndLinks: String { language.pick(zh: "检测颜色和链接", en: "Detect colors and links") }
    var stripTracking: String { language.pick(zh: "移除 URL 跟踪参数", en: "Strip tracking parameters from URLs") }
    var autoExpand: String {
        language.pick(
            zh: "自动展开片段快捷词（例如 `;sig`）",
            en: "Auto-expand snippet shortcuts (e.g. `;sig`)"
        )
    }
    var autoExpandNote: String {
        language.pick(
            zh: "需要 macOS 输入监控权限。首次启用时 macOS 会弹出权限提示。",
            en: "Requires macOS Input Monitoring permission. macOS will prompt the first time you enable this."
        )
    }

    var retention: String { language.pick(zh: "保留策略", en: "Retention") }
    var keepHistoryFor: String { language.pick(zh: "历史保留时间", en: "Keep history for") }
    var forever: String { language.pick(zh: "永久", en: "Forever") }
    func days(_ count: Int) -> String {
        language.pick(zh: "\(count) 天", en: "\(count) days")
    }
    var maxItems: String { language.pick(zh: "最大条目数", en: "Max items") }
    var unlimitedPlaceholder: String { language.pick(zh: "0 = 不限制", en: "0 = unlimited") }
    var pinnedNeverDeleted: String {
        language.pick(
            zh: "已固定的剪切板记录不会被自动删除，不受这些限制影响。",
            en: "Pinned clips are never auto-deleted, regardless of these limits."
        )
    }
    var ignoredApps: String { language.pick(zh: "忽略的应用", en: "Ignored apps") }
    var ignoredAppsDescription: String {
        language.pick(
            zh: "填写 Bundle ID（例如 `com.agilebits.onepassword`、`com.lastpass.macos`）。这些应用产生的剪切板内容不会被记录。",
            en: "Bundle identifiers (e.g. `com.agilebits.onepassword`, `com.lastpass.macos`). Clipboard activity from these apps will not be ingested."
        )
    }
    var dangerZone: String { language.pick(zh: "危险操作", en: "Danger zone") }
    var clearAllClips: String { language.pick(zh: "清空所有剪切板记录", en: "Clear all clips") }
    var clearAllClipsQuestion: String { language.pick(zh: "清空所有剪切板记录？", en: "Clear all clips?") }
    var cancel: String { language.pick(zh: "取消", en: "Cancel") }
    var clear: String { language.pick(zh: "清空", en: "Clear") }
    var clearAllClipsMessage: String {
        language.pick(
            zh: "这会永久删除所有剪切板记录（包括已固定和未固定）以及本地图片缓存。此操作无法撤销。",
            en: "This permanently deletes all clips (pinned and unpinned) and the on-disk image cache. Cannot be undone."
        )
    }

    var authentication: String { language.pick(zh: "认证", en: "Authentication") }
    var requireTouchID: String { language.pick(zh: "需要 Touch ID 解锁", en: "Require Touch ID to unlock") }
    var touchIDNote: String {
        language.pick(
            zh: "启用后，每次启动 App 后首次呼出面板时，Magpie 会要求 Touch ID。解锁后本次会话内保持可用。",
            en: "When enabled, Magpie prompts for Touch ID the first time you summon the panel after launching the app. Once unlocked, stays unlocked for the session."
        )
    }
    var filters: String { language.pick(zh: "过滤", en: "Filters") }
    var skipSecret: String { language.pick(zh: "跳过疑似密钥内容（API key、token、OTP）", en: "Skip secret-looking content (API keys, tokens, OTP)") }
    var skipSecretNote: String {
        language.pick(
            zh: "会识别形如 `api_key=...`、`Bearer ...`、GitHub token、AWS access key、JWT 和 6 位 OTP 的内容，并避免存储。",
            en: "Detects strings shaped like `api_key=...`, `Bearer ...`, GitHub tokens, AWS access keys, JWTs, and 6-digit OTP codes — they will not be stored."
        )
    }
    var encryption: String { language.pick(zh: "加密", en: "Encryption") }
    var encryptLocalStore: String { language.pick(zh: "加密本地数据库", en: "Encrypt local store") }
    var encryptionNote: String {
        language.pick(
            zh: "SQLCipher 集成会在 v1.0 加入。在此之前，数据库位于 `~/Library/Application Support/Magpie/clips.sqlite`，并使用 macOS 当前用户权限保护。",
            en: "SQLCipher integration coming in v1.0. Until then, the database lives in `~/Library/Application Support/Magpie/clips.sqlite` with macOS user-only file permissions."
        )
    }
    var analytics: String { language.pick(zh: "分析", en: "Analytics") }
    var sendAnalytics: String { language.pick(zh: "发送分析数据", en: "Send analytics") }
    var analyticsNote: String {
        language.pick(
            zh: "Magpie 按本地优先设计，不会联网上传数据。这个开关永远不会启用。",
            en: "Magpie is local-only by design. This will never be enabled."
        )
    }

    var scopeGlobal: String { language.pick(zh: "全局", en: "Global") }
    var scopePanel: String { language.pick(zh: "面板", en: "Panel") }
    var keyClick: String { language.pick(zh: "单击", en: "Click") }
    var keyDoubleClick: String { language.pick(zh: "双击", en: "Double-click") }
    var keySpace: String { language.pick(zh: "空格", en: "Space") }
    var shortcutShowHidePanel: String { language.pick(zh: "显示 / 隐藏面板", en: "Show / hide panel") }
    var shortcutOpenSettings: String { language.pick(zh: "打开设置", en: "Open Settings") }
    var shortcutPasteFocused: String { language.pick(zh: "粘贴当前选中记录", en: "Paste focused clip") }
    var shortcutQuickPaste: String { language.pick(zh: "快速粘贴第 1 条（也支持 ⌘2...⌘9）", en: "Quick paste clip 1 (also ⌘2...⌘9)") }
    var shortcutClickFocus: String { language.pick(zh: "聚焦并显示详情面板", en: "Focus + show Detail Pane") }
    var shortcutDoubleClickPaste: String { language.pick(zh: "聚焦并粘贴", en: "Focus + paste") }
    var shortcutMoveOlder: String { language.pick(zh: "移动到更旧的记录", en: "Move focus toward older clips") }
    var shortcutMoveNewer: String { language.pick(zh: "移动到更新的记录", en: "Move focus toward newer clips") }
    var shortcutPin: String { language.pick(zh: "固定 / 取消固定当前记录", en: "Pin / unpin focused clip") }
    var shortcutCycleLayout: String { language.pick(zh: "切换布局（Stripe -> Stack -> Grid）", en: "Cycle layout (Stripe -> Stack -> Grid)") }
    var shortcutToggleDetail: String {
        language.pick(
            zh: "切换详情面板（搜索框为空时）",
            en: "Toggle Detail Pane (when search field is empty)"
        )
    }
    var shortcutCancelCascade: String {
        language.pick(
            zh: "取消级联（清搜索 -> 清过滤 -> 关闭）",
            en: "Cancel cascade (clear search -> filter -> close)"
        )
    }
}
