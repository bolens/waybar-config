# Troubleshooting

> Doc map: [Documentation index](README.md) · [Architecture](architecture.md) · [Root README](../README.md)

## Bar did not pick up my settings

1. Confirm you edited **`data/waybar-settings.jsonc`**, not `waybar-settings.json` or a `*.generated.*` file.
2. Run `make generate`.
3. Restart: `systemctl --user restart waybar` (or launch script).
4. If launch skipped generate, check `~/.cache/waybar/generated.stamp` — delete it and restart to force regen.

## Duplicate bars or listeners

Do **not** start Waybar both via the user service and a second manual process. Prefer:

```bash
systemctl --user status waybar
systemctl --user restart waybar
```

`ExecStop` / `ExecStartPre` call `listener-ctl.sh stop-all` to avoid orphan watchers.

## Tooltips missing on Plasma

Keep `bars.tooltip: true`. This config uses `bars.layer: "top"` so fullscreen apps cover the bar. Layer `"overlay"` is better for KWin tooltips on Plasma Wayland but keeps the bar above fullscreen.

**Bottom bar only (top still works):** Common Waybar/gtk-layer-shell issue ([#3356](https://github.com/Alexays/Waybar/issues/3356)) — tooltips render *below* the bar (off-screen). Mitigations in this config:
- bottom-bar drawer tips are compact (title + “Click to toggle”, no tall Contains: lists)
- no vertical module margins (they worsen off-screen placement)
- `bars.height` ≥ module min-height (~60)
- do **not** float the bottom bar with side margins — that leaves visible gaps at the screen edges

**Dock appicons:** Waybar attaches tooltips to the inner `GtkLabel`, not the padded module box. Generated CSS includes `.appicon label { padding; min-width; min-height }`. Dock launchers use `"format": "{text}"`.

**Bar-wide tooltips dead (top and bottom):** Streaming modules starve the GTK loop — almost always `custom/cava` and/or `custom/mpris` zscroll while music plays (dual outputs double the load). Pause playback to confirm; tooltips should return. This config caps cava emits (~1.25/s, engine ≤12 fps) and mpris scroll (≥0.8s + 500ms throttle).

## “No such file” / wrong paths after move

Units use `%h/.config/waybar`. Remove drop-ins that hard-code old `/home/…` `ExecStart=` paths. See `systemd/waybar.service.d/README.conf.example`.

Ensure scripts see:

```bash
export WAYBAR_HOME="${XDG_CONFIG_HOME:-$HOME/.config}/waybar"
export WAYBAR_SCRIPTS="$WAYBAR_HOME/scripts"
```

## Module missing / always empty

1. Optional binary absent → many modules **hide** (by design). Check README Dependencies.
2. Group list omitted the module id — check `groups.*` in settings.
3. Generator not emitting it — `make generate` and inspect `modules/*.generated.jsonc`.
4. For secrets-backed modules (i2pd, CoolerControl), verify `data/waybar-secrets.jsonc` mode `0600` and auth helpers.

## CoolerControl / i2pd auth

```bash
sudo scripts/services/coolercontrol/coolercontrol-set-ui-pass.sh
sudo scripts/services/i2pd/i2pd-set-console-pass.sh
scripts/services/coolercontrol/coolercontrol-check-auth.sh
```

Prefer a read-only CoolerControl access token for day-to-day monitoring.

## Dock windows wrong on Plasma

Per-output filtering prefers WindowsRunner screen props when present; otherwise Waybar enriches via KWin `getWindowInfo` geometry + `kscreen-doctor` output rects. If those probes fail, both bars may still show the full list. Hyprland is usually correct when `hyprctl` clients include monitors. Needs `qt6-tools` (`qdbus6`) and `kscreen-doctor`. Disable with `dock_windows.enabled: false`.

## Theme / wallpaper not updating

- `theme.mode=preset` → valid `theme.preset` under `data/themes/`, then `make generate`.
- `theme.mode=wallpaper` → run `scripts/tools/theme-apply-wallpaper.sh` after wallpaper changes; confirm matugen/wallust/pywal are installed for your backend.

## CI / generate drift

```bash
make generate
make check-drift
git status   # commit intended .generated.* changes
```

Suite matrix out of sync: `make check-suite-inventory`.

## Healthcheck thrashing

`waybar-healthcheck.timer` restarts a dead bar and heals listeners about every 10s. If it loops, check `journalctl --user -u waybar -u waybar-healthcheck` for crash reasons (bad CSS, missing binary in `ExecStart`, compositor session gone).

## MCP / agent edits

- Programmatic settings writes **drop JSONC comments**.
- MCP never writes live secrets; use example + helpers.
- After agent patches: generate → validate → restart (`confirm=true`). See [mcp.md](mcp.md).

## Getting more signal

```bash
journalctl --user -u waybar -n 100 --no-pager
scripts/infra/waybar-healthcheck.sh   # if present / via timer unit
bash scripts/ci/validate-generated-config.sh
```

## Related docs

See the full map: [Documentation index](README.md).

| Doc | Topic |
|-----|--------|
| [Architecture](architecture.md) | Launch / generate / stamp |
| [Settings reference](settings-reference.md) | What to edit |
| [Theming](theming.md) | Preset / wallpaper issues |
| [Adding a module](adding-a-module.md) | Module wiring checklist |
| [MCP server](mcp.md) | Agent edit side effects |
| [Contributing](../CONTRIBUTING.md) | Local checks |
| [AGENTS.md](../AGENTS.md) | Agent briefing |
| [Scripts layout](../scripts/README.md) | Where helpers live |
