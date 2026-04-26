# Magpie themes

Magpie has two layers, mirroring the prototype's `data-theme` / `data-accent`
split:

| Layer | Type | Mutually exclusive? | Affects |
|---|---|---|---|
| **Base theme** | `AppTheme` (`light` / `dark` / `system`) | yes — pick one | NSWindow appearance, system vibrancy |
| **Flavor** | `Flavor` (`mono` / `graphite` / `blue` / `olive` / `splat`) | yes — pick one | Accent color, focus chrome, stroke, corner radius |

A flavor sits **on top** of the base theme — it overrides accent + decorative
chrome but leaves the base brightness alone. So `Splat + Light` and
`Splat + Dark` both work.

---

## Adding a new flavor

Three small edits, no other code changes needed.

### 1. Add an enum case

In `Theme.swift`:

```swift
enum Flavor: String, Codable, Sendable, CaseIterable {
    case mono
    case graphite
    case blue
    case olive
    case splat
    case yourflavor   // ← add here
}
```

### 2. Add a display name

```swift
var displayName: String {
    switch self {
    // …existing cases…
    case .yourflavor: return "Your Flavor"
    }
}
```

### 3. Add tokens

```swift
var tokens: FlavorTokens {
    switch self {
    // …existing cases…
    case .yourflavor:
        return FlavorTokens(
            accent:           Color.purple,
            focusBgColor:     Color.pink,
            focusBgIntensity: 0.30,
            strokeColor:      .primary,
            strokeOpacity:    0.06,
            strokeWidth:      0.5,
            focusStrokeOpacity: 0.55,
            focusStrokeWidth: 1.0,
            cardCornerRadius: 12,
            tileCornerRadius: 10
        )
    }
}
```

That's it. `Flavor.allCases` (from `CaseIterable`) automatically picks up the
new case — Settings → General → Flavor will show a swatch for it, and
ClipPreview / StackRow / GridTile will read its tokens.

---

## What lives in `FlavorTokens`

Every flavor must specify all of these (no defaults — adding a new field
forces every flavor to re-decide):

| Token | Used by |
|---|---|
| `accent` | Solid accent color — Settings swatch, future button highlights |
| `focusBgColor` × `focusBgIntensity` | Background tint behind the focused card |
| `strokeColor` × `strokeOpacity` × `strokeWidth` | Card / tile border (default state) |
| `focusStrokeOpacity` × `focusStrokeWidth` | Card / tile border (focused state) |
| `cardCornerRadius` | ClipPreview corner radius (Stripe) |
| `tileCornerRadius` | GridTile corner radius |

---

## Why this split (vs. one big "theme" enum)

- The base theme is **structural** — Light vs. Dark changes vibrancy material,
  text legibility, glass strength. Macros like `NSAppearance` already do this
  job; we just route to them.
- A flavor is **decorative** — accent palette, focus chrome, corner shape.
  It never has to fight with the base theme's decisions about brightness;
  it only contributes color + a few millimeters of curvature.

If a future "theme" needs to fully replace structure (different layout,
different fonts, different animations), make it a new `AppTheme` case
rather than a flavor.

---

## What's not in v0.2-c (yet)

- **Custom typefaces** (Splat would want `Tilt Warp` or similar). Tokens
  could grow a `fontFamily: String?` field and views could conditionally
  apply it — left for v0.3.
- **Decorative components** (squid mascots, ink splat backgrounds). Per-flavor
  decorative SwiftUI views can be conditionally rendered in `PanelContentView`
  switching on `settings.flavor` — also v0.3 if Splat needs them.
- **OKLCH-based focus color computation**. The prototype uses CSS
  `color-mix(in oklch, …)`. SwiftUI's `Color` API doesn't expose OKLCH
  directly; for now each flavor specifies focus colors directly.
