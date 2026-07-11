# Waybar Configuration

A modern, highly modular, and performance-optimized Waybar configuration tailored for KDE Plasma 6 and Hyprland compositors under Wayland.

## Features

- **Independent Active Workspace Indicators per Monitor**: Tracks and maps virtual desktops per output using a custom KWin DBus listener script, solving the global workspace tracking limitation in KDE Plasma.
- **Unified Compositor Detection**: Automatically detects whether you are running KDE Plasma or Hyprland, loading the appropriate workspace and window watchers seamlessly.
- **Declarative Code Generation**: Generates Waybar layouts, modules, and theme tokens dynamically from a single central JSONC file (`data/waybar-settings.jsonc`).
- **Smart Caching & Background Refresh**: Employs a zero-lag background-refresh caching mechanism via `waybar-cache-helpers.sh` (using `serve_cache_or_refresh`). Serves cached UI state instantly on poll, then asynchronously runs updates in the background, preventing CPU stampedes and sluggish updates.
- **Rich Cyberpunk Aesthetics**: High-refresh-rate-friendly pill containers, responsive icons, subtle hover micro-animations, and dynamic sliders.

## File Structure

* `config.jsonc`: Main bar entry point mapping includes and layouts.
* `data/`: Contains settings (`waybar-settings.jsonc` source of truth; `waybar-settings.json` is compiled), optional local secrets (`waybar-secrets.jsonc`, gitignored), and network interface specifications.
* `layouts/`: Core top and bottom structural layouts.
* `modules/`: Configuration blocks for specific widgets (clock, workspaces, tray, etc.).
* `includes/`: Common defaults and unified configuration entry points.
* `scripts/`: Telemetry, status checks, click handlers, and backend watchers.
* `theme/`: Styling sheets, colors, and layout tokens.

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
   ~/.config/waybar/scripts/waybar-launch.sh
   ```

### Ops notes (systemd)

| Unit | Role |
|------|------|
| `waybar.service` | Runs `waybar-launch.sh`; `ExecStop`/`ExecStartPre` call `listener-ctl.sh stop-all`; reload uses `kill -USR2 $MAINPID` |
| `waybar-healthcheck.timer` | Every ~10s: restart dead waybar, heal privacy / device-notifier / compositor listeners |

Do **not** start a second waybar alongside the user service (duplicates bars and listeners).

### Layer / tooltips (Plasma)

`bars.layer` is **`overlay`** so KWin renders tooltips. Using `"top"` can fix fullscreen overlap but breaks tooltips on Plasma Wayland. Keep `bars.tooltip: true`.

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
| `scripts/i2pd-set-console-pass.sh` | Sync helper (run with `sudo`) |

**`scripts/i2pd-set-console-pass.sh`** (idempotent):

1. If secrets already have `services.i2pd.console_pass` → push it into `/etc/i2pd/i2pd.conf` `[http]` (and ensure `/var/lib/i2pd/i2pd.conf` is the tmpfiles symlink to `/etc`).
2. If secrets are missing/`CHANGE_ME` but i2pd.conf already has `[http] pass` → **import** that pass into `waybar-secrets.jsonc` (create/update, `chown` to the sudo caller), then continue.
3. Re-run with matching state → no config rewrite, no service restart; auth check only.
4. Password never appears on process argv or in script output.

```bash
sudo ~/.config/waybar/scripts/i2pd-set-console-pass.sh
```

Install the repo pre-commit hook (blocks committing secrets / `console_pass` in settings):

```bash
ln -sfn ../../scripts/pre-commit-check-secrets.sh ~/.config/waybar/.git/hooks/pre-commit
```

To regenerate configurations after modifying settings:
```bash
~/.config/waybar/scripts/generate-settings.sh
~/.config/waybar/scripts/generate-compositor-modules.sh
```

Launch skips regeneration when inputs are unchanged (stamp: `~/.cache/waybar/generated.stamp`).

### Adding new status modules
If you are developing a new status script (e.g. `scripts/my-status.sh`):
1. Import the cache helpers at the top of your script:
   ```bash
   . "${WAYBAR_HOME:-$HOME/.config/waybar}/scripts/waybar-cache-helpers.sh"
   ```
2. Leverage the unified caching function to eliminate boilerplate:
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

### Testing & Validation
Verify that changes are syntactically valid and perform as expected before committing:
* **Validate JSONC outputs**:
  ```bash
  ~/.config/waybar/scripts/validate-generated-config.sh
  ```
* **Run Unit/Behavioral Tests**:
  ```bash
  ~/.config/waybar/scripts/run-generator-tests.sh
  # includes secrets overlay + i2pd sync helper tests
  ~/.config/waybar/scripts/run-secrets-and-settings-tests.sh
  ```

## Dependencies
A list of optional integration packages:
* **Core**: `qt6-tools` (KDE DBus), `socat` (Hyprland events), `jq` (JSON parsing), `wireplumber` (audio).
* **Menus**: `rofi` or `wofi` (interactive menus), `cliphist` (clipboard history).
* **Telemetry**: `networkmanager`, `brightnessctl`, `ddcutil`, `docker`, `upower`, `nut` (UPS status).
