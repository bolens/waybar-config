import json
import os
import subprocess


def load_waybar_signals():
    """Load RTMIN offsets from waybar-settings.json (signals.*)."""
    defaults = {
        "workspaces": 16,
        "clipboard": 9,
        "notifications": 10,
        "keyboard_layout": 2,
        "nightlight": 14,
        "brightness": 8,
        "vpn": 5,
        "tailscale": 12,
        "kdeconnect": 18,
        "device_battery": 4,
        "powerprofiles": 3,
        "dock_windows": 11,
    }
    home = os.environ.get("WAYBAR_HOME") or os.path.join(
        os.environ.get("XDG_CONFIG_HOME", os.path.expanduser("~/.config")), "waybar"
    )
    path = os.path.join(home, "data", "waybar-settings.json")
    try:
        with open(path, "r", encoding="utf-8") as f:
            data = json.load(f)
        signals = data.get("signals") or {}
        out = dict(defaults)
        for key, val in signals.items():
            if isinstance(val, int):
                out[key] = val
        return out
    except Exception:
        return defaults


SIGNALS = load_waybar_signals()


def waybar_rtmin(key):
    offset = SIGNALS.get(key)
    if offset is None:
        return
    subprocess.run(
        ["pkill", "-x", f"-RTMIN+{offset}", "waybar"],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
