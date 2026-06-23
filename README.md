# Waybar Configuration

A modern and highly modular Waybar configuration designed for KDE Plasma 6 and Hyprland compositors under Wayland.

## Features

- **Independent Active Workspace Indicators per Monitor**: Solves the global workspace tracking limitation in KDE Plasma by mapping and tracking virtual desktops per output using a custom KWin DBus listener script, ensuring Waybar displays the correct active desktop for each monitor independently.
- **Unified Compositor Detection**: Automatically detects the current compositor environment (KDE Plasma or Hyprland) and loads matching workspace and active window watchers seamlessly.
- **Dynamic Module Configurations**: Custom modular scripts with auto-generation support for audio, network interfaces, Docker status, update reviews, night light control, power management, screen recording, and system hardware metrics.
- **Smart Caching**: Employs a zero-lag cache invalidation mechanism. When desktop workspace focus transitions or media outputs change, caches are invalidated immediately before triggering Waybar signals to avoid stale UI updates without causing CPU stampedes.
- **Rich Aesthetics**: Custom icon grids and responsive layouts tailored to high-refresh and multi-monitor setups.

## Dependencies

The scripts and widgets included in this configuration depend on the following packages:

### Core Integration
- `qt6-tools` (provides `qdbus6`, required for KDE Plasma 6 integration)
- `hyprland` (provides `hyprctl`, required for Hyprland integration)
- `python-gobject` / `pygobject` (required by the Python listener script for GLib/Gio DBus interfaces)
- `socat` (required by the Hyprland event listener script)
- `jq` (required by almost all status scripts and configuration generators to parse JSON)
- `wireplumber` (provides `wpctl`, required for volume status and default audio sink controls)

### Menu & Interface Utilities
- `rofi` or `wofi` (required for calendar, bluetooth, clipboard, and window-switching menus)
- `cliphist` (required for clipboard history tracking)
- `wl-clipboard` (provides `wl-copy`/`wl-paste`, required for clipboard actions)
- `wtype` (required for background hotkey simulation, e.g. Discord controls)
- `zscroll` (required for scrolling text in status modules)
- `libnotify` (provides `notify-send`, required for system notifications)
- `pavucontrol` or `pwvucontrol` (optional GUI volume control mixer, opened on audio module click)

### Hardware & Network Status Controls
- `networkmanager` (provides `nmcli`, required for network and VPN status)
- `pipewire-pulse` / `pulseaudio` (provides `pactl`, required for audio/volume management)
- `wireless_tools` (provides `iwgetid`, optional, required for WiFi ESSID connection details)
- `brightnessctl` (optional, required for local laptop display backlight controls)
- `ddcutil` (optional, required for monitor brightness controls via DDC/CI)
- `docker` (optional, required for Docker container status tracking)
- `github-cli` (provides `gh`, optional, required for GitHub notification status)
- `upower` (optional, required for notebook battery and general power state tracking)
- `nut` (provides `upsc`, optional, required for local UPS battery status tracking)
- `ripgrep` (provides `rg`, required for fast text searching in various status scripts)

### Security, System Status & Updates
- `chkrootkit` (optional, required for security scan state alerts)
- `libredefender` (optional, required for local firewall/antivirus status checks)
- `pacman-contrib` (provides `checkupdates`, optional, required for Arch Linux system updates status)
- `flatpak` (optional, required for flatpak application updates tracking)
- `paru` or `yay` (optional AUR helper, required for AUR updates checking)

## File Structure

- [`config.jsonc`](./config.jsonc): Main configuration file loading layouts and including modular defaults.
- [`style.css`](./style.css) & [`user-style.css`](./user-style.css): Main stylesheets defining tokens, animations, and visual layout styles.
- [`modules/`](./modules/): Individual JSONC files for each widget (workspace slots, network, clock, tray, etc.).
- [`layouts/`](./layouts/): Core structural layout files (`top`, `bottom`, etc.).
- [`data/`](./data/): Contains user settings and dynamic workspace configurations.
- [`scripts/`](./scripts/): Helper scripts for state-tracking, listener utilities, volume controls, and compositor integrations.

## Installation & Usage

1. Clone this repository directly to your Waybar configuration home:
   ```bash
   git clone https://github.com/bolens/waybar-config.git ~/.config/waybar
   ```
2. Start Waybar using the launcher script (which auto-generates layout-specific files on boot and monitors compositor sessions):
   ```bash
   ~/.config/waybar/scripts/waybar-launch.sh
   ```

To run it continuously under systemd, reload and restart the user unit:
```bash
systemctl --user daemon-reload
systemctl --user restart waybar
```
