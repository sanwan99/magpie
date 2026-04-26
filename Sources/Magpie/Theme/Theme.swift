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

    /// Full token set for this flavor.
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
