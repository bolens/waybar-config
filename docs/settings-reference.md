# Settings reference

> Doc map: [Documentation index](README.md) · [Architecture](architecture.md) · [Root README](../README.md)

Source of truth: [`data/waybar-settings.jsonc`](../data/waybar-settings.jsonc). After edits, run `make generate`. See [architecture](architecture.md) for the compile/generate pipeline.

Optional overlay: `data/waybar-secrets.jsonc` (gitignored). Never put credentials in the main settings file.

## Top-level keys

| Key | Purpose |
|-----|---------|
| `bars` | Layer, outputs, height, spacing, floating island geometry, glass opacity |
| `drawers` | Click-to-reveal, transition, drawer icons/tooltips |
| `module_intervals` | Poll TTL per module key (`once` or seconds). Single map — no separate `poll_intervals` |
| `signals` | Waybar RT signal numbers for push updates |
| `layouts` | `top` / `bottom` → `modules_left` / `modules_center` / `modules_right` |
| `groups` | Named strips/drawers and their module id lists |
| `dock` | Dock section ordering |
| `workspaces` | Slot count, scroll-per-output |
| `dock_windows` | Per-window dock slots (enable, slot_count, per_output, …) |
| `window_switcher` | Output filtering for the switcher |
| `cava` | Optional visualizer bars/framerate/placement |
| `pomodoro` | Work / break durations |
| `homelab` | HTTP health `targets[]` |
| `active_window` | Title truncation / display |
| `capture` | Screenshot & screenrecord dirs/tools |
| `disk` | Disk paths for the disk module |
| `liquidctl` | Device filters |
| `updates` | Package update checker options |
| `github` | `gh` notifications module |
| `services` | Non-secret service toggles / URLs |
| `network` | Interface / bandwidth options |
| `brightness` | Backend / device |
| `audio` | PipeWire / pulse options |
| `tray` | Tray spacing |
| `clocks` | Formats and calendar markup |
| `theme` | Mode, preset, wallpaper, fonts, colors — [theming](theming.md) |
| `visual` | Gauges, album art, stats carousel, animations, reduced motion |
| `hypr_tools` | Hyprland helper command paths |
| `weather` | Provider, unit, location |
| `bluetooth` / `keyboard` / `gamemode` / `kdeconnect` / … | Click/scroll overrides and small feature blocks |
| `thresholds` | Warning/critical cutoffs for metrics |
| `nightlight` | Temperature / toggle behavior |
| `rofi` | Menu theming / bindings |
| `apps` | Launch commands and URLs (machine-specific) |
| `streamdeck` | Stream Deck module options |

## `bars`

Common fields: `layer` (`overlay` recommended on Plasma for tooltips), `output`, `exclusive`, `height`, `spacing`, `tooltip`, `floating`, `margin_*`, `glass_opacity`, `chrome_radius`.

## `module_intervals` and `signals`

- Interval keys (e.g. `cpu`, `weather`) are read by status scripts via `waybar_module_interval <key> <fallback>`.
- Value `"once"` → long cache TTL for signal-driven modules.
- `signals.<key>` must match the Waybar module `signal` field generators emit.

## `layouts` and `groups`

- Layouts place **group ids** and **module ids** on the bar (e.g. `group/media`, `clock#bottom`).
- Groups define drawer direction and the ordered module list inside each strip.
- Special tokens like `@network.interfaces` expand at generate time.

Laptop / fork-friendly overrides: [`data/profiles/minimal-groups.jsonc`](../data/profiles/minimal-groups.jsonc) via `make profile-minimal`.

## `theme` and `visual`

See [theming](theming.md). Visual polish flags live under `visual.*` (gauges, album art, carousel, CSS animation toggles, `reduced_motion`).

## `homelab.targets`

```jsonc
"homelab": {
  "timeout_sec": 3,
  "targets": [
    { "name": "Caddy", "url": "https://example.com/health", "expect": "2xx" }
  ]
}
```

Empty targets hide the module. One target → left opens URL. Two or more → rofi picker.

## `apps` and personalization

Click targets, desktop IDs, and service URLs under `apps` / `services` are machine-specific. Forks should edit them locally rather than expecting upstream hosts.

## Manifests (outside the main JSONC)

| File | Role |
|------|------|
| `data/dock-apps.json` | Dock launcher entries |
| `data/network-interfaces.json` | Interface → module wiring |
| `data/workspace-bar.json`, `workspace-desktops.json`, `workspace-glyphs.json` | Workspace UI data |

## Editing via MCP

Agents can use the [MCP server](mcp.md) (`waybar_get_settings`, `waybar_patch_settings`, …). Programmatic writes rewrite pretty JSON and **drop JSONC comments**.

## Related docs

See the full map: [Documentation index](README.md).

| Doc | Topic |
|-----|--------|
| [Architecture](architecture.md) | Pipeline overview |
| [Adding a module](adding-a-module.md) | Wire new keys into generators |
| [Theming](theming.md) | `theme` / `visual` detail |
| [Troubleshooting](troubleshooting.md) | When edits do not apply |
| [MCP server](mcp.md) | Agent API over settings |
| [AGENTS.md](../AGENTS.md) | Agent briefing |
| [Contributing](../CONTRIBUTING.md) | Checks and PR norms |
