"""Path helpers for the KDE listener (scripts/ root resolution)."""
import os


def waybar_scripts_dir():
    """Return scripts/ root (parent of lib/)."""
    env = os.environ.get("WAYBAR_SCRIPTS")
    if env:
        return env
    # paths.py lives at scripts/lib/kde_listener/paths.py
    return os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
