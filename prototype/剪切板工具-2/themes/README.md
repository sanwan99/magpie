# Magpie themes

Each theme is a self-contained file. Adding/removing one is a single-file change.

```
themes/
  base.css           ← layout + components + animations (theme-agnostic)
  theme-light.css    ← light surfaces, macOS vibrancy
  theme-dark.css     ← dark surfaces, macOS vibrancy
  theme-splat.css    ← Splatoon (fluo paint, ink splats, comic outlines)
  splat.jsx          ← splat-only React components (mascot, background)
```

## How it works

`base.css` defines structure but never picks colors directly — it only reads
CSS custom properties (`--ink`, `--panel-bg`, `--accent-h`, …).

Each theme file defines those variables under a selector:

```css
:root[data-theme="light"]  { --ink: #1c1c1e; --panel-bg: rgba(252,250,247,.62); … }
:root[data-theme="dark"]   { --ink: #f2f2f5; --panel-bg: rgba(22,22,24,.58);    … }
:root[data-accent="splat"] { --splat-y: #ffd200; --splat-p: #7a2bff;            … }
```

Switching themes is just toggling the attribute on `<html>`:

```js
document.documentElement.dataset.theme = 'dark';
document.documentElement.dataset.accent = 'splat';   // splat is layered on top
```

## Adding a new theme

1. Copy `theme-light.css` → `theme-myname.css`.
2. Edit the variables for your palette.
3. (Optional) Add bespoke decorative selectors at the bottom — keep them all
   namespaced under `[data-theme="myname"]` so they only fire for your theme.
4. Link it in `Deck Clipboard.html` next to the others.
5. (Optional) If the theme needs custom React components (like splat's squid
   mascot), add them as `themes/myname.jsx` and conditionally render in app.jsx.

## Why split this way

- **Light/Dark** are *base* themes — they redefine the foundational color
  variables. You pick one at a time via `data-theme`.
- **Splat** is an *accent layer* — it overlays its own variables and adds
  decorative chrome on top of light or dark. Hence `data-accent="splat"`,
  not `data-theme="splat"`.

If you want a future theme to fully replace the look (not layer on), use
`data-theme`. If it's a flavor that swaps a few accents, use `data-accent`.
