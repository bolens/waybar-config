# Theming

> Doc map: [Documentation index](README.md) · [Settings reference](settings-reference.md) · [Architecture](architecture.md)

Colors and chrome come from `theme` in [`data/waybar-settings.jsonc`](../data/waybar-settings.jsonc). After changes: `make generate` (writes `theme/tokens.generated.css` and `theme/semantic-colors.generated.css`).

GTK3/Waybar has **no CSS `var()`** — generators bake concrete color values into semantic CSS.

## Modes

| `theme.mode` | Behavior |
|--------------|----------|
| `static` | Use `theme.colors.*` (and fonts / radius on the theme object) |
| `preset` | Load [`data/themes/<theme.preset>.jsonc`](../data/themes/), then optional `theme.colors` overrides |
| `wallpaper` | Auto matugen → wallust → pywal. Default `theme.wallpaper.scope: per_output` styles each monitor |

GTK3 has no CSS variables. Generators bake colors into:

| File | Owns |
|------|------|
| `theme/tokens.generated.css` | Font, bar chrome, tooltips |
| `theme/module-pills.generated.css` | Shared pill layout from `scripts/lib/css-selectors-lib.sh` |
| `theme/semantic-colors.generated.css` | Theme-aware pill/drawer/slot colors (`slot_count`-aware) |
| `theme/drawers.generated.css` / `theme/groups.generated.css` | Drawer shells + `#center`/`#status` cluster layout from the same lib SoT |
| `theme/modules.css` / `theme/groups.css` | Hand layout overrides (privacy chips, `#workspaces`/`#submap`, …) |
| `theme/workspaces.css` / `theme/dock-windows.css` | Strip chrome only |
| `theme/workspaces.generated.css` / `theme/dock-windows.generated.css` | Slot layout from `slot_count` |
| `theme/accents/*.css` | Shared cyberpunk **brand** state accents (not theme-tinted) |
| `user-style/*.css` | Personal taste overrides — **must load last** via `style.css` |

### Where does new CSS go?

| Change | Put it here |
|--------|-------------|
| New module that should share pill chrome | Add ID to `waybar_css_pill_ids` in `scripts/lib/css-selectors-lib.sh`, then `make generate` |
| Theme-aware color (follows `theme.mode` / presets) | Generator → `semantic-colors.generated.css` (do not hand-edit) |
| Shared state color that stays cyberpunk on every preset | `theme/accents/<domain>.css` |
| Personal one-off taste | `user-style/<domain>.css` |
| Layout-only quirk (padding, hidden, letter-spacing) | `theme/modules.css` (or drawers/groups generators if it is an ID list) |
| New drawer side | `drawers.icons` + `groups.*` in settings **and** `waybar_css_drawer_sides` / group map in the lib |

### Accents vs `theme.mode`

`theme/accents/*.css` is **intentional brand chrome**: VPN greens, clock yellow, privacy in-use colors, dock app hovers, etc. stay cyberpunk even when `theme.mode` is `preset`/`nord`/wallpaper. Semantic pill backgrounds and `.warning`/`.critical` **do** follow the active theme. Do not move brand accents into the theme generator unless you are deliberately making them theme-aware.

`style.css` is import glue (no thin accent/user hubs):

```css
@import "…/hyprwhspr-style.css";
@import "theme.css";
@import "theme/accents/….css";   /* domain accents */
@import "user-style/….css";      /* personal — last */
```

`@import` paths resolve relative to the **file that contains them**. From `style.css` (config root) use `theme/accents/…` and `user-style/…`. Avoid `/*` / `*.css` globs inside CSS comments — GTK treats that as a nested comment and rejects the stylesheet.

Do not re-set `.warning`/`.critical` colors in accents or user-style modules.

```jsonc
"theme": {
  "mode": "preset",
  "preset": "nord"
}
```

Bundled presets: `cyberpunk`, `glass-cyber`, `minimal`, `nord`, `dracula`, `catppuccin-mocha`, `catppuccin-macchiato`, `gruvbox`, `tokyo-night`, `rose-pine`, `everforest`, `solarized-dark`, `one-dark`.

### Wallpaper mode

```jsonc
"theme": {
  "mode": "wallpaper",
  "wallpaper": {
    "backend": "auto",       // auto | matugen | wallust | pywal
    "scope": "per_output",   // per_output | global
    "image": null,           // global fallback path
    "outputs": {},           // optional { "DP-1": "/path/wall.jpg" }
    "reload_style": true
  }
}
```

After wallpaper changes, run `scripts/tools/theme-apply-wallpaper.sh`. Optional packages: see README → Dependencies → wallpaper theming.

## Fonts and chrome

On the `theme` object: `font_family`, `font_size`, `tooltip_font_size`, `border_radius`, `tooltip_padding`, plus `colors.*` (`foreground`, `background`, `accent`, `warning`, `critical`, workspace colors, tooltip chrome, …).

Clock calendar spans and Rofi menus consume the same color set.

After editing theme colors or CSS layout/accent modules, run `make generate` (or at least `bash scripts/generate/generate-theme-tokens.sh`) so `semantic-colors.generated.css` picks up accent-tinted module pills and drawer handles.

## Floating / glass bars

```jsonc
"bars": {
  "floating": true,
  "margin_top": 8,
  "margin_right": 12,
  "margin_left": 12,
  "glass_opacity": null,   // null = keep theme background alpha
  "chrome_radius": null    // null = theme.border_radius
}
```

On Hyprland, optional blur: `scripts/tools/print-hypr-waybar-blur.sh` (print snippet; not auto-applied).

## Visual polish

Under `visual` in settings:

| Key | Role |
|-----|------|
| `gauges` | Unicode metric gauges |
| `album_art` | MPRIS art chip (on by default) |
| `stats_carousel` | Rotating cpu/mem/disk/gpu chip (on by default; scroll to cycle; `module_intervals.stats_carousel`, default 8) |
| `animations` | `workspace_pulse`, `critical_breathe`, `idle_glow`, `reduced_motion` |

### Reduced motion

`visual.animations.reduced_motion`: `auto` | `force` | `off`.

In `auto`, launch probes GNOME reduced-motion / animations, Plasma `AnimationDurationFactor=0`, and Hyprland `animations:enabled`. When active, `theme/reduced-motion.generated.css` disables CSS motion and unicode spinners skip.

Override: `WAYBAR_REDUCED_MOTION=1|0`.

## Cava placement

`cava.placement`: `drawer` (default) or `inline` in the open media strip. Requires the `cava` package; module hides when missing/silent.

## MCP helpers

`waybar_list_themes`, `waybar_set_theme`, `waybar_apply_preset`, `waybar_write_theme` — see [mcp.md](mcp.md).

## Related docs

See the full map: [Documentation index](README.md).

| Doc | Topic |
|-----|--------|
| [Settings reference](settings-reference.md) | `theme` / `visual` / `bars` keys |
| [Architecture](architecture.md) | How tokens are generated |
| [Troubleshooting](troubleshooting.md) | Theme / wallpaper not updating |
| [MCP server](mcp.md) | Agent theme tools |
| [Root README](../README.md#theming) | User-facing theming summary |
| [Contributing](../CONTRIBUTING.md) | Dev loop |
| [AGENTS.md](../AGENTS.md) | Agent briefing |
