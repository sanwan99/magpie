import AppKit
import SwiftUI

// MARK: - Base theme (light / dark / follow system)

/// Base theme — picks the foundational background brightness.
/// Maps to NSWindow.appearance so SwiftUI's @Environment automatically follows.
enum AppTheme: String, Codable, Sendable, CaseIterable {
    case system
    case light
    case dark

    var displayName: String {
        displayName(language: .en)
    }

    func displayName(language: AppLanguage) -> String {
        switch self {
        case .system: return language.pick(zh: "跟随系统", en: "Follow System")
        case .light:  return language.pick(zh: "浅色", en: "Light")
        case .dark:   return language.pick(zh: "深色", en: "Dark")
        }
    }

    var appearance: NSAppearance? {
        switch self {
        case .system: return nil
        case .light:  return NSAppearance(named: .aqua)
        case .dark:   return NSAppearance(named: .darkAqua)
        }
    }
}

// MARK: - Flavor (overlay theme — accent palette + decorative tokens)

/// A flavor sits on top of the base theme. Mono/Graphite/Blue/Olive are
/// muted accents; Splat is a decorative theme (fluo yellow/purple, comic
/// outlines, big corner radii) demonstrating how flavors can override more
/// than color.
///
/// **Adding a new flavor** (per `Sources/Magpie/Theme/README.md`):
///   1. Add an enum case here.
///   2. Add an entry to `tokens` below.
///   3. Add a display name to `displayName`.
///   4. Done — `CaseIterable` picks it up everywhere (Settings list, etc.).
enum Flavor: String, Codable, Sendable, CaseIterable {
    case mono
    case graphite
    case blue
    case olive
    case splat
    case forest
    case husk
    case mist
    case club
    case unit
    case ink
    case gilt

    var displayName: String {
        displayName(language: .en)
    }

    func displayName(language: AppLanguage) -> String {
        switch self {
        case .mono:     return language.pick(zh: "单色", en: "Mono")
        case .graphite: return language.pick(zh: "石墨", en: "Graphite")
        case .blue:     return language.pick(zh: "蓝色", en: "Blue")
        case .olive:    return language.pick(zh: "橄榄", en: "Olive")
        case .splat:    return "Splat"
        case .forest:   return language.pick(zh: "林克 / 塞尔达", en: "Link / Zelda")
        case .husk:     return language.pick(zh: "小骑士 / 黄蜂女", en: "Knight / Hornet")
        case .mist:     return language.pick(zh: "芙莉莲 / 菲伦", en: "Frieren / Fern")
        case .club:     return language.pick(zh: "凉宫 / 长门", en: "Haruhi / Nagato")
        case .unit:     return language.pick(zh: "明日香 / 绫波", en: "Asuka / Rei")
        case .ink:      return language.pick(zh: "战场原 / 羽川", en: "Senjougahara / Hanekawa")
        case .gilt:     return language.pick(zh: "大忍 / 小忍", en: "Kiss-Shot / Shinobu")
        }
    }

    /// Decorative flavors render extra panel chrome in addition to tokens.
    var isDecorative: Bool {
        switch self {
        case .splat, .forest, .husk, .mist, .club, .unit, .ink, .gilt:
            return true
        case .mono, .graphite, .blue, .olive:
            return false
        }
    }

    /// ColorScheme-aware token resolution. Most flavors return the same
    /// token set regardless of base theme; Splat returns a different palette
    /// for dark mode (deep purple ink) vs light mode (paper-white).
    func tokens(for scheme: ColorScheme) -> FlavorTokens {
        if self == .splat {
            return scheme == .dark ? Flavor.splatDarkTokens : tokens
        }
        if let decorative = decorativeTokens(for: scheme) {
            return decorative
        }
        return regularTokens(for: scheme)
    }

    /// Backwards-compatible default-light tokens. Used by previews and as the
    /// fallback when no ColorScheme is available.
    var tokens: FlavorTokens {
        switch self {
        case .mono:
            return FlavorTokens(
                accent:           Color(white: 0.55),
                focusBgColor:     Color(white: 0.55),
                focusBgIntensity: 0.18,
                cardBgIdleColor:  nil,
                cardBgIdleOpacity: 0,
                panelBgOverlay:   nil,
                focusGlowColor:   nil,
                strokeColor:      .primary,
                focusStrokeColor: nil,
                strokeOpacity:    0.06,
                strokeWidth:      0.5,
                focusStrokeOpacity: 0.55,
                focusStrokeWidth: 1.0,
                cardCornerRadius: 12,
                tileCornerRadius: 10
            )
        case .graphite:
            return FlavorTokens(
                accent:           Color(red: 0.42, green: 0.42, blue: 0.46),
                focusBgColor:     Color(red: 0.42, green: 0.42, blue: 0.46),
                focusBgIntensity: 0.20,
                cardBgIdleColor:  nil,
                cardBgIdleOpacity: 0,
                panelBgOverlay:   nil,
                focusGlowColor:   nil,
                strokeColor:      .primary,
                focusStrokeColor: nil,
                strokeOpacity:    0.06,
                strokeWidth:      0.5,
                focusStrokeOpacity: 0.55,
                focusStrokeWidth: 1.0,
                cardCornerRadius: 12,
                tileCornerRadius: 10
            )
        case .blue:
            return FlavorTokens(
                accent:           Color(red: 0.32, green: 0.50, blue: 0.78),
                focusBgColor:     Color(red: 0.32, green: 0.50, blue: 0.78),
                focusBgIntensity: 0.22,
                cardBgIdleColor:  nil,
                cardBgIdleOpacity: 0,
                panelBgOverlay:   nil,
                focusGlowColor:   nil,
                strokeColor:      .primary,
                focusStrokeColor: nil,
                strokeOpacity:    0.06,
                strokeWidth:      0.5,
                focusStrokeOpacity: 0.65,
                focusStrokeWidth: 1.0,
                cardCornerRadius: 12,
                tileCornerRadius: 10
            )
        case .olive:
            return FlavorTokens(
                accent:           Color(red: 0.48, green: 0.55, blue: 0.34),
                focusBgColor:     Color(red: 0.48, green: 0.55, blue: 0.34),
                focusBgIntensity: 0.22,
                cardBgIdleColor:  nil,
                cardBgIdleOpacity: 0,
                panelBgOverlay:   nil,
                focusGlowColor:   nil,
                strokeColor:      .primary,
                focusStrokeColor: nil,
                strokeOpacity:    0.06,
                strokeWidth:      0.5,
                focusStrokeOpacity: 0.55,
                focusStrokeWidth: 1.0,
                cardCornerRadius: 12,
                tileCornerRadius: 10
            )
        case .splat:
            // Splatoon-inspired demo flavor — light-mode visuals.
            //   accent (purple) is preserved for swatches / future splatter
            //   decorations; the *panel* itself stays paper-light per spec
            //   `[data-accent="splat"][data-theme="light"]` (panel-bg #ffffff).
            //   Strong visual takes:
            //     - cream cards (#fffce6) on the default vibrancy
            //     - fluo-yellow focus (#ffe900)
            //     - thick black comic outlines (1.5 / 2.5)
            //     - bigger corner radii (16 / 14) for the playful shape
            //   Note: dark-mode splat (deep-purple ink) needs ColorScheme-aware
            //   tokens — left for v0.3 along with squid mascot decorations.
            return FlavorTokens(
                accent:           Color(red: 0.48, green: 0.17, blue: 1.00),  // #7a2bff — for swatch / future decor
                focusBgColor:     Color(red: 1.00, green: 0.91, blue: 0.00),  // #ffe900 fluo yellow
                focusBgIntensity: 0.92,
                cardBgIdleColor:  Color(red: 1.00, green: 0.99, blue: 0.90),  // #fffce6 cream
                cardBgIdleOpacity: 0.85,
                panelBgOverlay:   nil,                                         // paper-light panel
                focusGlowColor:   nil,
                strokeColor:      .black,
                focusStrokeColor: nil,
                strokeOpacity:    0.95,
                strokeWidth:      1.5,
                focusStrokeOpacity: 1.00,
                focusStrokeWidth: 2.5,
                cardCornerRadius: 16,
                tileCornerRadius: 14
            )
        case .forest, .husk, .mist, .club, .unit, .ink, .gilt:
            return decorativeTokens(for: .light) ?? Flavor.mono.tokens
        }
    }
}

private extension Flavor {
    func regularTokens(for scheme: ColorScheme) -> FlavorTokens {
        let palette = regularPalette
        switch scheme {
        case .dark:
            return FlavorTokens(
                accent:           palette.accent,
                focusBgColor:     palette.darkFocus,
                focusBgIntensity: palette.darkFocusIntensity,
                cardBgIdleColor:  .white,
                cardBgIdleOpacity: 0.04,
                panelBgOverlay:   Color(red: 0.086, green: 0.086, blue: 0.094).opacity(0.58),
                focusGlowColor:   nil,
                strokeColor:      .white,
                focusStrokeColor: palette.darkFocusBorder,
                strokeOpacity:    0.07,
                strokeWidth:      0.5,
                focusStrokeOpacity: 0.60,
                focusStrokeWidth: 0.5,
                cardCornerRadius: 12,
                tileCornerRadius: 10
            )
        case .light:
            return FlavorTokens(
                accent:           palette.accent,
                focusBgColor:     palette.lightFocus,
                focusBgIntensity: palette.lightFocusIntensity,
                cardBgIdleColor:  .white,
                cardBgIdleOpacity: 0.60,
                panelBgOverlay:   Color(red: 0.988, green: 0.980, blue: 0.969).opacity(0.62),
                focusGlowColor:   nil,
                strokeColor:      .black,
                focusStrokeColor: palette.lightFocusBorder,
                strokeOpacity:    0.06,
                strokeWidth:      0.5,
                focusStrokeOpacity: 0.50,
                focusStrokeWidth: 0.5,
                cardCornerRadius: 12,
                tileCornerRadius: 10
            )
        @unknown default:
            return tokens
        }
    }

    var regularPalette: RegularThemePalette {
        switch self {
        case .mono:
            return RegularThemePalette(
                accent: Color(white: 0.55),
                darkFocus: Color(red: 0.31, green: 0.25, blue: 0.28),
                darkFocusIntensity: 0.70,
                darkFocusBorder: Color(red: 0.72, green: 0.64, blue: 0.68),
                lightFocus: Color(red: 0.93, green: 0.90, blue: 0.91),
                lightFocusIntensity: 1.00,
                lightFocusBorder: Color(red: 0.50, green: 0.44, blue: 0.47)
            )
        case .graphite:
            return RegularThemePalette(
                accent: Color(red: 0.42, green: 0.42, blue: 0.46),
                darkFocus: Color(red: 0.22, green: 0.27, blue: 0.35),
                darkFocusIntensity: 0.72,
                darkFocusBorder: Color(red: 0.49, green: 0.57, blue: 0.70),
                lightFocus: Color(red: 0.88, green: 0.90, blue: 0.94),
                lightFocusIntensity: 1.00,
                lightFocusBorder: Color(red: 0.42, green: 0.48, blue: 0.58)
            )
        case .blue:
            return RegularThemePalette(
                accent: Color(red: 0.32, green: 0.50, blue: 0.78),
                darkFocus: Color(red: 0.05, green: 0.17, blue: 0.42),
                darkFocusIntensity: 0.72,
                darkFocusBorder: Color(red: 0.36, green: 0.59, blue: 1.00),
                lightFocus: Color(red: 0.85, green: 0.90, blue: 1.00),
                lightFocusIntensity: 1.00,
                lightFocusBorder: Color(red: 0.25, green: 0.44, blue: 0.78)
            )
        case .olive:
            return RegularThemePalette(
                accent: Color(red: 0.48, green: 0.55, blue: 0.34),
                darkFocus: Color(red: 0.20, green: 0.28, blue: 0.08),
                darkFocusIntensity: 0.72,
                darkFocusBorder: Color(red: 0.56, green: 0.73, blue: 0.34),
                lightFocus: Color(red: 0.89, green: 0.94, blue: 0.78),
                lightFocusIntensity: 1.00,
                lightFocusBorder: Color(red: 0.42, green: 0.51, blue: 0.24)
            )
        case .splat:
            return RegularThemePalette(
                accent: Color(red: 0.48, green: 0.17, blue: 1.00),
                darkFocus: Color(red: 0.48, green: 0.17, blue: 1.00),
                darkFocusIntensity: 0.30,
                darkFocusBorder: Color(red: 0.48, green: 0.17, blue: 1.00),
                lightFocus: Color(red: 1.00, green: 0.91, blue: 0.00),
                lightFocusIntensity: 0.92,
                lightFocusBorder: Color(red: 0.48, green: 0.17, blue: 1.00)
            )
        case .forest, .husk, .mist, .club, .unit, .ink, .gilt:
            return RegularThemePalette(
                accent: decorativeTokens(for: .light)?.accent ?? Color(white: 0.55),
                darkFocus: decorativeTokens(for: .dark)?.focusBgColor ?? Color(white: 0.30),
                darkFocusIntensity: decorativeTokens(for: .dark)?.focusBgIntensity ?? 0.30,
                darkFocusBorder: decorativeTokens(for: .dark)?.focusStrokeColor ?? Color(white: 0.65),
                lightFocus: decorativeTokens(for: .light)?.focusBgColor ?? Color(white: 0.90),
                lightFocusIntensity: decorativeTokens(for: .light)?.focusBgIntensity ?? 1.00,
                lightFocusBorder: decorativeTokens(for: .light)?.focusStrokeColor ?? Color(white: 0.45)
            )
        }
    }
}

private extension Flavor {
    func decorativeTokens(for scheme: ColorScheme) -> FlavorTokens? {
        let dark = scheme == .dark
        switch self {
        case .forest:
            return dark
                ? Self.decorative(
                    accent: Self.rgb(212, 175, 90),
                    focus: (Self.rgb(70, 100, 68), 0.55),
                    card: (Self.rgb(40, 60, 46), 0.45),
                    panel: Self.rgb(20, 32, 24).opacity(0.78),
                    stroke: (Self.rgb(212, 175, 90), 0.14),
                    focusStroke: (Self.rgb(212, 175, 90), 0.55),
                    glow: Self.rgb(212, 175, 90)
                )
                : Self.decorative(
                    accent: Self.rgb(110, 82, 15),
                    focus: (Self.rgb(220, 205, 150), 0.60),
                    card: (Self.rgb(255, 250, 235), 0.60),
                    panel: Self.rgb(252, 247, 232).opacity(0.86),
                    stroke: (Self.rgb(80, 60, 28), 0.14),
                    focusStroke: (Self.rgb(160, 110, 30), 0.55),
                    glow: Self.rgb(160, 110, 30)
                )
        case .husk:
            return dark
                ? Self.decorative(
                    accent: Self.rgb(236, 229, 216),
                    focus: (Self.rgb(36, 44, 60), 0.85),
                    card: (Self.rgb(22, 28, 40), 0.60),
                    panel: Self.rgb(14, 18, 26).opacity(0.82),
                    stroke: (Self.rgb(236, 229, 216), 0.10),
                    focusStroke: (Self.rgb(196, 40, 40), 0.70),
                    glow: Self.rgb(196, 40, 40)
                )
                : Self.decorative(
                    accent: Self.rgb(24, 24, 27),
                    focus: (Self.rgb(24, 24, 27), 0.12),
                    card: (Self.rgb(255, 250, 240), 0.70),
                    panel: Self.rgb(248, 243, 232).opacity(0.88),
                    stroke: (Self.rgb(24, 24, 27), 0.10),
                    focusStroke: (Self.rgb(196, 40, 40), 0.70),
                    glow: Self.rgb(196, 40, 40)
                )
        case .mist:
            return dark
                ? Self.decorative(
                    accent: Self.rgb(192, 178, 228),
                    focus: (Self.rgb(80, 76, 118), 0.55),
                    card: (Self.rgb(48, 56, 72), 0.45),
                    panel: Self.rgb(28, 32, 38).opacity(0.82),
                    stroke: (Self.rgb(208, 200, 232), 0.10),
                    focusStroke: (Self.rgb(192, 178, 228), 0.60),
                    glow: Self.rgb(192, 178, 228)
                )
                : Self.decorative(
                    accent: Self.rgb(93, 72, 148),
                    focus: (Self.rgb(220, 210, 242), 0.85),
                    card: (Self.rgb(248, 246, 255), 0.70),
                    panel: Self.rgb(252, 250, 255).opacity(0.88),
                    stroke: (Self.rgb(96, 82, 128), 0.12),
                    focusStroke: (Self.rgb(120, 96, 176), 0.55),
                    glow: Self.rgb(140, 116, 196)
                )
        case .club:
            return dark
                ? Self.decorative(
                    accent: Self.rgb(255, 210, 75),
                    focus: (Self.rgb(216, 164, 40), 0.85),
                    card: (Self.rgb(38, 52, 84), 0.55),
                    panel: Self.rgb(20, 28, 46).opacity(0.82),
                    stroke: (Self.rgb(255, 210, 75), 0.14),
                    focusStroke: (Self.rgb(255, 210, 75), 1.00),
                    glow: Self.rgb(255, 210, 75)
                )
                : Self.decorative(
                    accent: Self.rgb(28, 78, 168),
                    focus: (Self.rgb(255, 210, 75), 0.86),
                    card: (Self.rgb(255, 255, 255), 0.70),
                    panel: Self.rgb(252, 250, 242).opacity(0.90),
                    stroke: (Self.rgb(0, 40, 90), 0.12),
                    focusStroke: (Self.rgb(28, 34, 56), 0.70),
                    glow: Self.rgb(28, 78, 168)
                )
        case .unit:
            return dark
                ? Self.decorative(
                    accent: Self.rgb(214, 46, 54),
                    focus: (Self.rgb(214, 46, 54), 0.18),
                    card: (Self.rgb(36, 38, 46), 0.65),
                    panel: Self.rgb(20, 21, 25).opacity(0.88),
                    stroke: (Self.rgb(214, 46, 54), 0.14),
                    focusStroke: (Self.rgb(214, 46, 54), 1.00),
                    glow: Self.rgb(214, 46, 54)
                )
                : Self.decorative(
                    accent: Self.rgb(180, 35, 43),
                    focus: (Self.rgb(214, 46, 54), 0.10),
                    card: (Self.rgb(255, 255, 255), 0.70),
                    panel: Self.rgb(248, 246, 242).opacity(0.92),
                    stroke: (Self.rgb(140, 18, 24), 0.10),
                    focusStroke: (Self.rgb(180, 35, 43), 0.85),
                    glow: Self.rgb(180, 35, 43)
                )
        case .ink:
            return dark
                ? Self.decorative(
                    accent: Self.rgb(181, 166, 217),
                    focus: (Self.rgb(118, 108, 160), 0.40),
                    card: (Self.rgb(40, 38, 48), 0.55),
                    panel: Self.rgb(22, 22, 28).opacity(0.85),
                    stroke: (Self.rgb(220, 215, 232), 0.10),
                    focusStroke: (Self.rgb(181, 166, 217), 1.00),
                    glow: Self.rgb(181, 166, 217)
                )
                : Self.decorative(
                    accent: Self.rgb(76, 63, 118),
                    focus: (Self.rgb(24, 22, 30), 0.10),
                    card: (Self.rgb(255, 255, 255), 0.65),
                    panel: Self.rgb(252, 251, 252).opacity(0.92),
                    stroke: (Self.rgb(45, 40, 68), 0.12),
                    focusStroke: (Self.rgb(76, 63, 118), 0.85),
                    glow: Self.rgb(76, 63, 118)
                )
        case .gilt:
            return dark
                ? Self.decorative(
                    accent: Self.rgb(232, 198, 107),
                    focus: (Self.rgb(214, 175, 72), 0.16),
                    card: (Self.rgb(38, 30, 16), 0.65),
                    panel: Self.rgb(20, 17, 10).opacity(0.86),
                    stroke: (Self.rgb(214, 175, 72), 0.18),
                    focusStroke: (Self.rgb(232, 198, 107), 1.00),
                    glow: Self.rgb(232, 198, 107)
                )
                : Self.decorative(
                    accent: Self.rgb(110, 82, 16),
                    focus: (Self.rgb(232, 198, 107), 0.40),
                    card: (Self.rgb(255, 250, 232), 0.70),
                    panel: Self.rgb(252, 247, 232).opacity(0.92),
                    stroke: (Self.rgb(120, 90, 18), 0.16),
                    focusStroke: (Self.rgb(164, 127, 28), 0.85),
                    glow: Self.rgb(164, 127, 28)
                )
        case .mono, .graphite, .blue, .olive, .splat:
            return nil
        }
    }

    static func decorative(
        accent: Color,
        focus: (Color, Double),
        card: (Color, Double),
        panel: Color,
        stroke: (Color, Double),
        focusStroke: (Color, Double),
        glow: Color
    ) -> FlavorTokens {
        FlavorTokens(
            accent: accent,
            focusBgColor: focus.0,
            focusBgIntensity: focus.1,
            cardBgIdleColor: card.0,
            cardBgIdleOpacity: card.1,
            panelBgOverlay: panel,
            focusGlowColor: glow,
            strokeColor: stroke.0,
            focusStrokeColor: focusStroke.0,
            strokeOpacity: stroke.1,
            strokeWidth: 0.5,
            focusStrokeOpacity: focusStroke.1,
            focusStrokeWidth: 1.5,
            cardCornerRadius: 8,
            tileCornerRadius: 8
        )
    }

    static func rgb(_ r: Double, _ g: Double, _ b: Double) -> Color {
        Color(red: r / 255.0, green: g / 255.0, blue: b / 255.0)
    }
}

private struct RegularThemePalette {
    let accent: Color
    let darkFocus: Color
    let darkFocusIntensity: Double
    let darkFocusBorder: Color
    let lightFocus: Color
    let lightFocusIntensity: Double
    let lightFocusBorder: Color
}

/// All visual variables a flavor can override.
/// Default-arg-free — every flavor must specify all tokens, so adding a
/// new field forces you to think about what it should be everywhere.
struct FlavorTokens: Sendable {
    /// Solid accent color (used for swatches, buttons, hover hints).
    let accent: Color
    /// Tint applied behind focused items.
    let focusBgColor: Color
    /// Multiplier on focusBgColor (0…1) — how strongly to tint.
    let focusBgIntensity: Double
    /// Background tint on idle (non-focused) cards. nil = no override (use the
    /// default `.background.opacity(...)` look).
    let cardBgIdleColor: Color?
    /// Multiplier on cardBgIdleColor.
    let cardBgIdleOpacity: Double
    /// Optional color overlay painted behind the panel content (under top bar
    /// and layout body). nil = transparent. Used by decorative flavors like
    /// Splat to swap the whole-panel mood.
    let panelBgOverlay: Color?
    /// Optional neon-glow color for focused cards (drawn as a colored shadow
    /// outside the stroke). nil = use the default black drop-shadow.
    /// Splat dark uses lime to get the prototype's "highlight pop" effect.
    let focusGlowColor: Color?
    /// Default card / tile border color.
    let strokeColor: Color
    /// Optional focused border color. nil = reuse strokeColor.
    let focusStrokeColor: Color?
    /// Default border alpha when not focused.
    let strokeOpacity: Double
    /// Default border width when not focused.
    let strokeWidth: CGFloat
    /// Border alpha when item is focused.
    let focusStrokeOpacity: Double
    /// Border width when item is focused.
    let focusStrokeWidth: CGFloat
    /// Corner radius for ClipPreview cards (Stripe).
    let cardCornerRadius: CGFloat
    /// Corner radius for grid tiles.
    let tileCornerRadius: CGFloat

    /// Convenience: ready-to-use focused background color (color × intensity).
    var focusBg: Color {
        focusBgColor.opacity(focusBgIntensity)
    }

    /// Convenience: ready-to-use idle card background, or transparent if not set.
    var cardBgIdle: Color {
        guard let color = cardBgIdleColor else { return .clear }
        return color.opacity(cardBgIdleOpacity)
    }
}

// MARK: - Splat dark variant

extension Flavor {
    /// Splat dark — matches `prototype/剪切板工具-2/themes/theme-splat.css`:
    /// deep purple panel, purple idle cards, bright yellow focused cards,
    /// yellow panel/card outlines, and purple offset shadow on focus.
    static let splatDarkTokens = FlavorTokens(
        accent:           Color(red: 1.00, green: 0.91, blue: 0.00),  // #ffe900
        focusBgColor:     Color(red: 1.00, green: 0.91, blue: 0.00),
        focusBgIntensity: 0.98,
        cardBgIdleColor:  Color(red: 0.13, green: 0.04, blue: 0.23),  // #220a3a
        cardBgIdleOpacity: 0.94,
        panelBgOverlay:   Color(red: 0.08, green: 0.02, blue: 0.12).opacity(0.98), // #14041f
        focusGlowColor:   Color(red: 0.48, green: 0.17, blue: 1.00),  // #7a2bff
        strokeColor:      Color(red: 1.00, green: 0.91, blue: 0.00),
        focusStrokeColor: Color(red: 0.05, green: 0.05, blue: 0.06),
        strokeOpacity:    0.95,
        strokeWidth:      2.0,
        focusStrokeOpacity: 1.0,
        focusStrokeWidth: 2.8,
        cardCornerRadius: 18,
        tileCornerRadius: 16
    )
}
