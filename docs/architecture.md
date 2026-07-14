# Architecture

> Doc map: [Documentation index](README.md) · [Root README](../README.md) · [Contributing](../CONTRIBUTING.md) · [AGENTS](../AGENTS.md)

How this Waybar config turns declarative settings into a running bar.

```text
data/waybar-settings.jsonc     (source of truth — edit this)
        │
        ▼  compile (strip JSONC comments)
data/waybar-settings.json      (artifact — overwritten)
        │
        ├─ optional deep-merge ◀── data/waybar-secrets.jsonc (gitignored)
        │
        ▼  make generate
scripts/generate/*.sh
        │
        ▼
modules/*.generated.jsonc
layouts/*.generated.jsonc
includes/bar-defaults.generated.jsonc
theme/*.generated.css
        │
        ▼
config.jsonc → includes/stack.jsonc → Waybar
        │
        ▼
scripts/infra/waybar-launch.sh  (+ systemd user units, listeners)
```

## Source of truth vs artifacts

| Path | Role |
|------|------|
| [`data/waybar-settings.jsonc`](../data/waybar-settings.jsonc) | **Edit this.** Intervals, groups, layouts, theme, apps, feature flags |
| `data/waybar-settings.json` | Compiled from JSONC; do not hand-edit |
| `data/waybar-secrets.jsonc` | Local credentials overlay (mode `0600`, never commit) |
| `data/themes/*.jsonc` | Color presets for `theme.mode=preset` |
| `data/profiles/*.jsonc` | Optional overlays (e.g. minimal laptop groups) |
| `data/dock-apps.json`, `network-interfaces.json`, `workspace-*.json` | Manifests consumed by generators |
| `modules/*.generated.jsonc`, `layouts/*.generated.jsonc`, `theme/*.generated.css` | **Generated** — regenerate after settings changes |
| Hand-written shells under `layouts/`, `config.jsonc`, `style.css` | Entry points / chrome that include generated pieces |

## Runtime path

1. **systemd** `waybar.service` runs [`scripts/infra/waybar-launch.sh`](../scripts/infra/waybar-launch.sh).
2. Launch compiles settings if needed, skips `make generate` when the stamp (`~/.cache/waybar/generated.stamp`) matches inputs, starts listeners via `listener-ctl.sh`, then execs Waybar.
3. Status modules under `scripts/<domain>/` poll or listen; most use [`scripts/lib/waybar-cache-helpers.sh`](../scripts/lib/waybar-cache-helpers.sh) (`serve_cache_or_refresh`) and intervals from `module_intervals` via `waybar_module_interval`.
4. Settings reads go through [`scripts/lib/waybar-settings.sh`](../scripts/lib/waybar-settings.sh) (`waybar_settings_get`, secrets merge).
5. Long-running listeners (`privacy`, `vpn-tailscale`, `album-art`, compositor watchers, …) push updates with [`scripts/lib/waybar-signal.sh`](../scripts/lib/waybar-signal.sh) keyed by `signals.*` — see [`scripts/README.md`](../scripts/README.md#listeners-daemons). Unknown keys log to stderr (journal / `~/.cache/waybar/waybar.log`); CI covers the map in the `module-signals` suite.

## Generators

`make generate` runs (see Makefile):

- `scripts/generate/generate-settings.sh` — bar defaults, layouts, groups, system modules, then domain emitters (utilities, audio, clock, drawers, network-custom, privacy, active-window, dock-windows, tray, hypr-tools, theme tokens, animations, …)
- `scripts/generate/generate-compositor-modules.sh`
- `scripts/generate/generate-workspaces-css.sh`
- `scripts/generate/generate-dock-windows-css.sh`
- `scripts/generate/generate-drawers-css.sh`
- `scripts/generate/generate-groups-css.sh`

Sibling scripts also emit network/dock modules when invoked from `generate-settings.sh`.

## Compositors

Detection picks Plasma vs Hyprland for workspaces, active window, dock-windows, and related listeners. Shared settings stay compositor-agnostic; compositor-specific bits live under `scripts/listeners/`, `scripts/workspaces/`, and `hypr_tools` in settings.

## Related docs

See the full map: [Documentation index](README.md).

| Doc | Topic |
|-----|--------|
| [Settings reference](settings-reference.md) | Top-level settings keys |
| [Adding a module](adding-a-module.md) | New module checklist |
| [Theming](theming.md) | Colors / presets / wallpaper |
| [Troubleshooting](troubleshooting.md) | Common failures |
| [MCP server](mcp.md) | Optional AI agent API |
| [Scripts layout](../scripts/README.md) | Domain folders + CI harness |
| [Contributing](../CONTRIBUTING.md) | Dev loop and checks |
| [AGENTS.md](../AGENTS.md) | Agent briefing |
