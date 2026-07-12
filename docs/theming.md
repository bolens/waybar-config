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
| `stats_carousel` | Opt-in rotating metrics |
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
