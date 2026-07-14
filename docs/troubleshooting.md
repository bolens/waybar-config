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

## Crash toasts show `&lt;html&gt;&lt;tt&gt;…` (DrKonqi + mako)

DrKonqi / KNotifications send Plasma Qt HTML (`<html><tt>/usr/bin/zsh</tt>…`). **mako** advertises `body-markup` but only parses Pango, so invalid tags make it escape the whole body and you see literal entities.

This config starts `notify-sanitize-listener.py` whenever `makoctl` is on `PATH` (see `waybar-launch.sh` / healthcheck). It replaces the toast in place with plain text. Covered by the `notify-sanitize` CI suite.

If toasts still look escaped: `systemctl --user restart waybar` (or start the listener via `listener-ctl.sh start …/notify-sanitize-listener.py notify-sanitize`) and confirm `makoctl` owns `org.freedesktop.Notifications`.

## Tooltips show literal `&gt;` / `<b>` instead of styled text

Waybar's `"escape": true` runs `Glib::Markup::escape_text` on JSON `text`/`tooltip`. If the status script **already** escapes (`emit_waybar_json`, `html.escape`, `escape_markup`), entities are escaped twice and the tooltip shows markup like `-&gt;` instead of `->`.

Contract used here:

| Module pattern | `escape` flag | Who escapes |
|----------------|---------------|-------------|
| `emit_waybar_json` / script `escape_markup` | **omit** (false) | script |
| Intentional Pango (`<b>…</b>`) | **omit** (false) | escape user text only |
| Raw untrusted text, no script escape | `escape: true` | Waybar |

Covered by the `tooltip-pango-escape` CI suite (and `lib-utils` for `emit_waybar_json` single-escape).

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
5. Overlay net modules: **Yggdrasil** needs your user in the `yggdrasil` group for the admin socket; **IPFS** needs Kubo reachable at `services.ipfs.api_url` (default `http://127.0.0.1:5001`).

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

## Logs and stale modules

Useful logs:

```bash
journalctl --user -u waybar -n 100 --no-pager
# Filtered stderr copy (Drop patterns in scripts/infra/waybar-journal-drop.rg):
less "${XDG_CACHE_HOME:-$HOME/.cache}/waybar/waybar.log"
scripts/infra/waybar-healthcheck.sh   # if present / via timer unit
bash scripts/ci/validate-generated-config.sh
```

Stale custom modules after a click usually mean a **missed signal**:

1. Confirm the module has a `signal` field and a matching `signals.<key>` (`jq '.signals' data/waybar-settings.json`).
2. Prefer `"$WAYBAR_SCRIPTS/lib/waybar-signal.sh" <key>` (not a bare `RTMIN+N`).
3. Unknown keys print `waybar-signal: unknown key …` on stderr — that line appears in the journal / `waybar.log` when a click/listener typo drifts from settings.
4. After changing `signals.*`, regenerate and restart so generators and listeners pick up the new map.
5. Listener crash loops (`album-art listener dead; restarting` every ~30s) usually mean a FIFO reader saw EOF — listeners must open the trigger FIFO with `exec 3<>"$fifo"` (RDWR) and define `waybar_listener_cleanup` instead of replacing the lock EXIT trap. See `scripts/listeners/album-art-listener.sh`.

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
