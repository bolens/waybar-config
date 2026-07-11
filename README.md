# Waybar Configuration

A modern, highly modular, and performance-optimized Waybar configuration tailored for KDE Plasma 6 and Hyprland compositors under Wayland.

## Features

- **Independent Active Workspace Indicators per Monitor**: Tracks and maps virtual desktops per output using a custom KWin DBus listener script, solving the global workspace tracking limitation in KDE Plasma.
- **Unified Compositor Detection**: Automatically detects whether you are running KDE Plasma or Hyprland, loading the appropriate workspace and window watchers seamlessly.
- **Declarative Code Generation**: Generates Waybar layouts, modules, and theme tokens dynamically from a single central JSONC file (`data/waybar-settings.jsonc`).
- **Smart Caching & Background Refresh**: Employs a zero-lag background-refresh caching mechanism via `scripts/lib/waybar-cache-helpers.sh` (using `serve_cache_or_refresh`). Serves cached UI state instantly on poll, then asynchronously runs updates in the background, preventing CPU stampedes and sluggish updates.
- **Rich Cyberpunk Aesthetics**: High-refresh-rate-friendly pill containers, responsive icons, subtle hover micro-animations, and dynamic sliders.

## File Structure

* `config.jsonc`: Main bar entry point mapping includes and layouts.
* `data/`: Settings SoT (`waybar-settings.jsonc` → compiled `waybar-settings.json`), optional secrets (`waybar-secrets.jsonc`, gitignored), dock/network/workspace manifests.
* `layouts/`: Top and bottom bar layouts (hand-written shells + `.generated.jsonc`).
* `modules/`: Widget configs — almost all are `.generated.jsonc` from settings; do not edit those by hand.
* `includes/`: Include stack wiring modules into the bar.
* `scripts/`: Status/click handlers, listeners, generators, and CI — domain folders plus `lib/`, `generate/`, `ci/`, `infra/`. See [scripts/README.md](scripts/README.md).
* `theme/`: CSS tokens/modules plus Rofi themes under `theme/rofi/`.
* `style.css` / `user-style.css` / `theme.css`: Bar stylesheet entry points (`style.css` also imports hyprwhspr styles when installed).

## Getting Started

### Installation

1. Clone this repository directly to your Waybar home directory:
   ```bash
   git clone https://github.com/bolens/waybar-config.git ~/.config/waybar
   ```

2. Prefer the systemd user unit (recommended):
   ```bash
   systemctl --user daemon-reload
   systemctl --user enable --now waybar
   systemctl --user enable --now waybar-healthcheck.timer
   ```

   Or start via the launcher (which builds settings, configures session paths, and listens to session state):
   ```bash
   ~/.config/waybar/scripts/infra/waybar-launch.sh
   ```

### Ops notes (systemd)

| Unit | Role |
|------|------|
| `waybar.service` | Runs `scripts/infra/waybar-launch.sh`; `ExecStop`/`ExecStartPre` call `scripts/infra/listener-ctl.sh stop-all`; reload uses `kill -USR2 $MAINPID` |
| `waybar-healthcheck.timer` | Every ~10s: restart dead waybar, heal privacy / device-notifier / compositor listeners |

Do **not** start a second waybar alongside the user service (duplicates bars and listeners).

Point units at `scripts/infra/waybar-launch.sh`, `scripts/infra/listener-ctl.sh`, and `scripts/infra/waybar-healthcheck.sh`. Keep `WAYBAR_HOME` / `WAYBAR_SCRIPTS` set (scripts root is still `$WAYBAR_HOME/scripts`).

### Layer / tooltips (Plasma)

`bars.layer` is **`overlay`** so KWin renders tooltips. Using `"top"` can fix fullscreen overlap but breaks tooltips on Plasma Wayland. Keep `bars.tooltip: true`.

### Hyprland / hyprwhspr

On Hyprland, `custom/hyprwhspr` comes from generated `modules/hypr-tools.generated.jsonc` (via `scripts/services/hypr/hyprwhspr-status-wrapper.sh`). Clicks call the system hyprwhspr tray scripts under `/usr/lib/hyprwhspr/…`. `style.css` imports hyprwhspr’s CSS when the package is installed. No separate hand-written hyprwhspr module file is required.

## Development & Customization

### Central Configuration
Avoid editing `.generated.jsonc` or `.generated.css` files directly. Customize thresholds, poll intervals, application bindings, signals, and colors in:
👉 **[data/waybar-settings.jsonc](file:///home/panda/.config/waybar/data/waybar-settings.jsonc)**

`data/waybar-settings.json` is a compiled artifact and will be overwritten.

Interval / cache TTLs live in a single map: `module_intervals` (there is no separate `poll_intervals`). Status scripts read TTLs via `waybar_module_interval`.

### Secrets (i2pd console)

Credentials that must not be committed live in **`data/waybar-secrets.jsonc`** (gitignored). It is merged over `waybar-settings.jsonc` at read time by `waybar_settings_get`.

| File | Role |
|------|------|
| `data/waybar-secrets.jsonc` | Local secrets (mode `0600`, never commit) |
| `data/waybar-secrets.example.jsonc` | Safe template to copy |
| `scripts/services/i2pd/i2pd-set-console-pass.sh` | Sync helper (run with `sudo`) |

**`scripts/services/i2pd/i2pd-set-console-pass.sh`** (idempotent):

1. If secrets already have `services.i2pd.console_pass` → push it into `/etc/i2pd/i2pd.conf` `[http]` (and ensure `/var/lib/i2pd/i2pd.conf` is the tmpfiles symlink to `/etc`).
2. If secrets are missing/`CHANGE_ME` but i2pd.conf already has `[http] pass` → **import** that pass into `waybar-secrets.jsonc` (create/update, `chown` to the sudo caller), then continue.
3. Re-run with matching state → no config rewrite, no service restart; auth check only.
4. Password never appears on process argv or in script output.

```bash
sudo ~/.config/waybar/scripts/services/i2pd/i2pd-set-console-pass.sh
```

Install the repo pre-commit hook (blocks committing secrets / `console_pass` in settings):

```bash
ln -sfn ../../scripts/ci/pre-commit-check-secrets.sh ~/.config/waybar/.git/hooks/pre-commit
```

To regenerate configurations after modifying settings:
```bash
make generate
# or:
~/.config/waybar/scripts/generate/generate-settings.sh
~/.config/waybar/scripts/generate/generate-compositor-modules.sh
```

Launch skips regeneration when inputs are unchanged (stamp: `~/.cache/waybar/generated.stamp`).

### Adding new status modules
If you are developing a new status script (e.g. `scripts/system/my-status.sh`):
1. Place it in the matching domain folder (see [scripts/README.md](scripts/README.md)).
2. Import the cache helpers at the top of your script:
   ```bash
   : "${WAYBAR_HOME:=${XDG_CONFIG_HOME:-$HOME/.config}/waybar}"
   : "${WAYBAR_SCRIPTS:=$WAYBAR_HOME/scripts}"
   . "$WAYBAR_SCRIPTS/lib/waybar-cache-helpers.sh"
   ```
3. Leverage the unified caching function to eliminate boilerplate:
   ```bash
   ttl="$(waybar_module_interval my_module 60)"
   if [ "${1:-}" != "--refresh" ]; then
     if serve_cache_or_refresh "$cache_file" "$ttl" "$lock_dir" "$stale_lock_ttl"; then
       exit 0
     fi
     emit_waybar_json "󰄜 --" "Initializing..." "normal"
     exit 0
   fi
   # ... implement your --refresh data fetching logic here ...
   ```
4. Point the generator (or module config) at `$WAYBAR_HOME/scripts/<domain>/my-status.sh`.

### Testing & Validation

```bash
make check          # contracts + generator + secrets + validate
make check-syntax   # bash -n over all scripts
```

Or individually:
```bash
~/.config/waybar/scripts/ci/validate-generated-config.sh
~/.config/waybar/scripts/ci/run-generator-tests.sh
~/.config/waybar/scripts/ci/run-secrets-and-settings-tests.sh
```

## Dependencies
A list of optional integration packages:
* **Core**: `qt6-tools` (KDE DBus), `socat` (Hyprland events), `jq` (JSON parsing), `wireplumber` (audio).
* **Menus**: `rofi` or `wofi` (interactive menus), `cliphist` (clipboard history).
* **Telemetry**: `networkmanager`, `brightnessctl`, `ddcutil`, `docker`, `upower`, `nut` (UPS status).
* **Hyprland extras** (optional): `hyprwhspr` (voice/dictation module + CSS import in `style.css`).
