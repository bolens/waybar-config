# Waybar Configuration

A modern, highly modular, and performance-optimized Waybar configuration tailored for KDE Plasma 6 and Hyprland compositors under Wayland.

## Features

- **Independent Active Workspace Indicators per Monitor**: Tracks and maps virtual desktops per output using a custom KWin DBus listener script, solving the global workspace tracking limitation in KDE Plasma.
- **Unified Compositor Detection**: Automatically detects whether you are running KDE Plasma or Hyprland, loading the appropriate workspace and window watchers seamlessly.
- **Declarative Code Generation**: Generates Waybar layouts, modules, and theme tokens dynamically from a single central JSON file (`data/waybar-settings.json`).
- **Smart Caching & Background Refresh**: Employs a zero-lag background-refresh caching mechanism via `waybar-cache-helpers.sh` (using `serve_cache_or_refresh`). Serves cached UI state instantly on poll, then asynchronously runs updates in the background, preventing CPU stampedes and sluggish updates.
- **Rich Cyberpunk Aesthetics**: High-refresh-rate-friendly pill containers, responsive icons, subtle hover micro-animations, and dynamic sliders.

## File Structure

* `config.jsonc`: Main bar entry point mapping includes and layouts.
* `data/`: Contains settings (`waybar-settings.json`) and network interface specifications.
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

2. Start Waybar using the launcher script (which builds settings, configures session paths, and listens to session state):
   ```bash
   ~/.config/waybar/scripts/waybar-launch.sh
   ```

### Running under systemd

To run Waybar as a user unit:
```bash
systemctl --user daemon-reload
systemctl --user enable --now waybar
```

## Development & Customization

### Central Configuration
Avoid editing `.generated.jsonc` or `.generated.css` files directly. Customize all thresholds, poll intervals, application bindings, signals, and colors in:
👉 **[data/waybar-settings.json](file:///home/panda/.config/waybar/data/waybar-settings.json)**

To regenerate configurations after modifying settings:
```bash
~/.config/waybar/scripts/generate-settings.sh
```

### Adding new status modules
If you are developing a new status script (e.g. `scripts/my-status.sh`):
1. Import the cache helpers at the top of your script:
   ```bash
   . "${WAYBAR_HOME:-$HOME/.config/waybar}/scripts/waybar-cache-helpers.sh"
   ```
2. Leverage the unified caching function to eliminate boilerplate:
   ```bash
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
  ```

## Dependencies
A list of optional integration packages:
* **Core**: `qt6-tools` (KDE DBus), `socat` (Hyprland events), `jq` (JSON parsing), `wireplumber` (audio).
* **Menus**: `rofi` or `wofi` (interactive menus), `cliphist` (clipboard history).
* **Telemetry**: `networkmanager`, `brightnessctl`, `ddcutil`, `docker`, `upower`, `nut` (UPS status).
