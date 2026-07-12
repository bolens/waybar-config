"""Compositor detection for the KDE session listener (hyprland / kde / unknown)."""
import os
import subprocess


def detect_compositor() -> str:
    env = os.environ.get("WAYBAR_COMPOSITOR", "").strip()
    if env in ("hyprland", "kde", "unknown"):
        return env
    if os.environ.get("HYPRLAND_INSTANCE_SIGNATURE"):
        return "hyprland"
    desktop = "".join(
        os.environ.get(key, "")
        for key in ("XDG_CURRENT_DESKTOP", "XDG_SESSION_DESKTOP", "DESKTOP_SESSION")
    )
    if any(token in desktop for token in ("Hyprland", "hyprland")):
        return "hyprland"
    if any(token in desktop for token in ("KDE", "Plasma", "plasma")):
        return "kde"
    if os.environ.get("KDE_SESSION_VERSION"):
        return "kde"
    try:
        subprocess.run(
            ["pgrep", "-x", "kwin_wayland"],
            check=True,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        return "kde"
    except (subprocess.CalledProcessError, FileNotFoundError):
        pass
    try:
        subprocess.run(
            ["pgrep", "-x", "kwin_x11"],
            check=True,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        return "kde"
    except (subprocess.CalledProcessError, FileNotFoundError):
        pass
    return "unknown"
