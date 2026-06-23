# Premium Waybar Configuration

A premium, modern, and highly modular Waybar configuration designed for KDE Plasma 6 and Hyprland compositors under Wayland.

## Features

- **Independent Active Workspace Indicators per Monitor**: Solves the global workspace tracking limitation in KDE Plasma by mapping and tracking virtual desktops per output using a custom KWin DBus listener script, ensuring Waybar displays the correct active desktop for each monitor independently.
- **Unified Compositor Detection**: Automatically detects the current compositor environment (KDE Plasma or Hyprland) and loads matching workspace and active window watchers seamlessly.
- **Dynamic Module Configurations**: Custom modular scripts with auto-generation support for audio, network interfaces, Docker status, update reviews, night light control, power management, screen recording, and system hardware metrics.
- **Smart Caching**: Employs a zero-lag cache invalidation mechanism. When desktop workspace focus transitions or media outputs change, caches are invalidated immediately before triggering Waybar signals to avoid stale UI updates without causing CPU stampedes.
- **Rich Aesthetics**: Premium styling, custom icon grids, and responsive layouts tailored to high-refresh and multi-monitor setups.

## File Structure

- [`config.jsonc`](./config.jsonc): Main configuration file loading layouts and including modular defaults.
- [`style.css`](./style.css) & [`user-style.css`](./user-style.css): Main stylesheets defining tokens, animations, and premium visual layout styles.
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
