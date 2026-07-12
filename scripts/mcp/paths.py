"""Resolve WAYBAR_HOME and safe path helpers."""

from __future__ import annotations

import os
import re
from pathlib import Path

SAFE_NAME_RE = re.compile(r"^[a-z0-9][a-z0-9_-]*$", re.IGNORECASE)

THEME_MODES = frozenset({"static", "preset", "wallpaper"})
LAYOUT_BARS = frozenset({"top", "bottom"})
LAYOUT_SIDES = frozenset({"modules_left", "modules_center", "modules_right"})
CHECK_SUBSETS = frozenset({"syntax", "python", "validate", "fast", "contracts", "ruff"})

MANIFEST_FILES: dict[str, str] = {
    "dock-apps": "data/dock-apps.json",
    "network-interfaces": "data/network-interfaces.json",
    "workspace-bar": "data/workspace-bar.json",
    "workspace-desktops": "data/workspace-desktops.json",
    "workspace-glyphs": "data/workspace-glyphs.json",
    "secrets-example": "data/waybar-secrets.example.jsonc",
}

GENERATED_DIR_NAMES = frozenset(
    {"modules", "layouts", "includes", "theme"}
)

SETTINGS_SCHEMA: dict[str, str] = {
    "bars": "Bar chrome: layer, output, height, floating geometry, margins",
    "drawers": "Drawer click-to-reveal, transition, icons",
    "module_intervals": "Poll intervals (seconds or once) per module key",
    "signals": "Waybar RT signals for push updates",
    "layouts": "Top/bottom module placement lists",
    "groups": "Named module groups (drawers and strips)",
    "dock": "Dock section ordering",
    "workspaces": "Workspace slot count / scroll behavior",
    "dock_windows": "Per-window dock slots",
    "window_switcher": "Window switcher output filtering",
    "cava": "Optional cava visualizer settings",
    "pomodoro": "Pomodoro timer durations",
    "homelab": "HTTP health probe targets",
    "active_window": "Active window title truncation",
    "capture": "Screenshot / screenrecord paths and tools",
    "disk": "Disk module paths",
    "liquidctl": "liquidctl device filters",
    "updates": "Package update checker settings",
    "github": "GitHub notifications module",
    "services": "Service-specific toggles (non-secret)",
    "network": "Network interface / bandwidth options",
    "brightness": "Brightness backend / device",
    "audio": "Pulseaudio / pipewire options",
    "tray": "System tray spacing",
    "clocks": "Clock formats and calendars",
    "theme": "Colors, preset/wallpaper mode, fonts",
    "visual": "Gauges, album art, stats carousel, animations",
    "hypr_tools": "Hyprland helper command bindings",
    "weather": "Weather provider / location / unit",
    "bluetooth": "Bluetooth click overrides",
    "keyboard": "Keyboard layout click/scroll overrides",
    "gamemode": "Gamemode indicator",
    "kdeconnect": "KDE Connect module",
    "device_notifier": "Device notifier",
    "colorpicker": "Color picker command",
    "vaults": "Vaults module",
    "touchpad": "Touchpad toggle",
    "thresholds": "Warning/critical thresholds for metrics",
    "nightlight": "Night light temperature",
    "rofi": "Rofi theme / menu bindings",
    "apps": "Application launch commands",
    "streamdeck": "Stream Deck module",
}


def resolve_waybar_home(explicit: str | None = None) -> Path:
    if explicit:
        return Path(explicit).expanduser().resolve()
    env = os.environ.get("WAYBAR_HOME")
    if env:
        return Path(env).expanduser().resolve()
    # scripts/mcp/paths.py -> parents: mcp, scripts, repo root
    here = Path(__file__).resolve()
    repo_root = here.parents[2]
    if (repo_root / "data" / "waybar-settings.jsonc").is_file():
        return repo_root
    xdg = os.environ.get("XDG_CONFIG_HOME", str(Path.home() / ".config"))
    return Path(xdg).expanduser().resolve() / "waybar"


class WaybarPaths:
    def __init__(self, home: Path | None = None) -> None:
        self.home = home or resolve_waybar_home()

    @property
    def settings_jsonc(self) -> Path:
        return self.home / "data" / "waybar-settings.jsonc"

    @property
    def settings_json(self) -> Path:
        return self.home / "data" / "waybar-settings.json"

    @property
    def secrets_jsonc(self) -> Path:
        return self.home / "data" / "waybar-secrets.jsonc"

    @property
    def secrets_example(self) -> Path:
        return self.home / "data" / "waybar-secrets.example.jsonc"

    @property
    def themes_dir(self) -> Path:
        return self.home / "data" / "themes"

    @property
    def profiles_dir(self) -> Path:
        return self.home / "data" / "profiles"

    @property
    def data_dir(self) -> Path:
        return self.home / "data"

    @property
    def scripts_dir(self) -> Path:
        return self.home / "scripts"

    @property
    def modules_dir(self) -> Path:
        return self.home / "modules"

    @property
    def includes_dir(self) -> Path:
        return self.home / "includes"

    @property
    def layouts_dir(self) -> Path:
        return self.home / "layouts"

    @property
    def theme_dir(self) -> Path:
        return self.home / "theme"

    @property
    def backup_dir(self) -> Path:
        cache = Path(
            os.environ.get("XDG_CACHE_HOME", str(Path.home() / ".cache"))
        )
        return cache / "waybar" / "mcp-backups"

    def theme_file(self, name: str) -> Path:
        ensure_safe_name(name, "theme")
        return self.themes_dir / f"{name}.jsonc"

    def profile_file(self, name: str) -> Path:
        ensure_safe_name(name, "profile")
        return self.profiles_dir / f"{name}.jsonc"

    def manifest_file(self, manifest_id: str) -> Path:
        if manifest_id not in MANIFEST_FILES:
            raise ValueError(
                f"unknown manifest '{manifest_id}'. "
                f"Allowed: {', '.join(sorted(MANIFEST_FILES))}"
            )
        return self.home / MANIFEST_FILES[manifest_id]

    def safe_under(self, path: Path, *allowed_roots: Path) -> Path:
        resolved = path.resolve()
        for root in allowed_roots:
            try:
                resolved.relative_to(root.resolve())
                return resolved
            except ValueError:
                continue
        raise ValueError(f"path escapes allowlisted directories: {path}")


def ensure_safe_name(name: str, kind: str = "name") -> str:
    if ".." in name or "/" in name or "\\" in name:
        raise ValueError(f"invalid {kind}: path traversal rejected")
    if not SAFE_NAME_RE.match(name):
        raise ValueError(
            f"invalid {kind} '{name}': must match {SAFE_NAME_RE.pattern}"
        )
    return name
