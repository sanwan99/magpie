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
        switch self {
        case .system: return "Follow System"
        case .light:  return "Light"
        case .dark:   return "Dark"
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

    var displayName: String {
        switch self {
        case .mono:     return "Mono"
        case .graphite: return "Graphite"
        case .blue:     return "Blue"
        case .olive:    return "Olive"
        case .splat:    return "Splat"
        }
    }

    /// ColorScheme-aware token resolution. Most flavors return the same
    /// token set regardless of base theme; Splat returns a different palette
    /// for dark mode (deep purple ink) vs light mode (paper-white).
    func tokens(for scheme: ColorScheme) -> FlavorTokens {
        if self == .splat && scheme == .dark {
            return Flavor.splatDarkTokens
        }
        return tokens
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
                strokeOpacity:    0.95,
                strokeWidth:      1.5,
                focusStrokeOpacity: 1.00,
                focusStrokeWidth: 2.5,
                cardCornerRadius: 16,
                tileCornerRadius: 14
            )
        }
    }
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
    /// Splat dark — panel is BLACK (not purple), purple is decoration only.
    /// Lime-yellow (#c9ff00, leaning toward green per prototype squid color)
    /// is the focus highlight + accent. Decorative splatter / squid mascot
    /// elements layer on top via SplatDecorations.
    ///
    /// Focus styling matches the prototype's "neon highlight" — the focused
    /// card stays mostly black, gets a thick lime border, and a lime drop-glow
    /// outside the stroke. NOT a solid lime fill (which would obscure content).
    static let splatDarkTokens = FlavorTokens(
        // Purple lives in decorations (splatter shapes), not in card chrome.
        accent:           Color(red: 0.48, green: 0.17, blue: 1.00),  // #7a2bff for swatch
        // #c9ff00 — lime yellow, matches squid mascot color
        focusBgColor:     Color(red: 0.79, green: 1.00, blue: 0.00),
        // 0 = no fill on focus — keep card body black, let stroke + glow do
        // the work. Prototype focused card is BLACK with lime border, not
        // yellow with black text.
        focusBgIntensity: 0.0,
        // No idle card tint — let the black panel show through naturally.
        cardBgIdleColor:  nil,
        cardBgIdleOpacity: 0,
        // Near-black panel with a hint of warmth. 94% opacity keeps a tiny
        // hint of vibrancy.
        panelBgOverlay:   Color(red: 0.04, green: 0.04, blue: 0.05).opacity(0.94),
        // Lime drop-glow outside the focused stroke — gives the prototype's
        // "highlighted card pops out of the page" neon look.
        focusGlowColor:   Color(red: 0.79, green: 1.00, blue: 0.00),
        // Lime yellow outlines pop against black; thin idle / 4px focused
        // gives the comic outline feel.
        strokeColor:      Color(red: 0.79, green: 1.00, blue: 0.00),
        strokeOpacity:    0.30,
        strokeWidth:      1.0,
        focusStrokeOpacity: 1.0,
        focusStrokeWidth: 4.0,
        cardCornerRadius: 18,
        tileCornerRadius: 16
    )
}
