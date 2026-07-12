#!/usr/bin/env python3
"""Query virtual desktops for KDE and Hyprland with resolved names and glyphs."""

from __future__ import annotations

import json
import os
import re
import subprocess
import sys
from pathlib import Path

WAYBAR_HOME = Path(__file__).resolve().parents[2]
GLYPH_FILE = WAYBAR_HOME / "data/workspace-glyphs.json"
NAMES_FILE = WAYBAR_HOME / "data/workspace-desktops.json"
KWINRC = Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config")) / "kwinrc"
# qdbus6 --literal shape: (uss) <0-based pos>, "<uuid>", "<name>"
DESKTOP_RE = re.compile(r'\(uss\) (\d+), "([^"]+)", "([^"]+)"')
DEFAULT_DESKTOP_RE = re.compile(r"^desktop\s+\d+$", re.IGNORECASE)


def load_glyphs() -> dict[str, str]:
    if GLYPH_FILE.is_file():
        return json.loads(GLYPH_FILE.read_text(encoding="utf-8"))
    return {"default": "󰝥"}


def slugify(name: str) -> str:
    slug = re.sub(r"[^a-z0-9]+", "-", name.lower()).strip("-")
    return slug or "desktop"


def configured_names() -> dict[int, str]:
    names: dict[int, str] = {}
    if not NAMES_FILE.is_file():
        return names
    try:
        entries = json.loads(NAMES_FILE.read_text(encoding="utf-8"))
    except json.JSONDecodeError:
        return names
    if isinstance(entries, list):
        for index, value in enumerate(entries):
            if isinstance(value, str) and value.strip():
                names[index] = value.strip()
    return names


def kwinrc_names() -> dict[int, str]:
    """Map desktop index → name from ~/.config/kwinrc [Desktops] Name_N=.

    kwinrc uses 1-based Name_1, Name_2, …; we store 0-based indices to match
    VirtualDesktopManager.desktops positions and configured_names().
    """
    names: dict[int, str] = {}
    if not KWINRC.is_file():
        return names

    in_desktops = False
    for raw_line in KWINRC.read_text(encoding="utf-8", errors="replace").splitlines():
        line = raw_line.strip()
        if line == "[Desktops]":
            in_desktops = True
            continue
        if line.startswith("[") and in_desktops:
            break
        if not in_desktops:
            continue
        match = re.match(r"Name_(\d+)=(.*)$", line)
        if match:
            names[int(match.group(1)) - 1] = match.group(2)
    return names


def lookup_glyph(name: str, glyphs: dict[str, str]) -> str:
    slug = slugify(name)
    for key in (slug, name.lower(), name):
        value = glyphs.get(key)
        if value:
            return value
    return glyphs.get("default", "󰝥")


def resolve_name(position: int, dbus_name: str, kwin_names: dict[int, str], configured: dict[int, str]) -> str:
    # Priority: custom D-Bus name → kwinrc → data/workspace-desktops.json → raw.
    # Generic "Desktop N" names are treated as placeholders and get remapped.
    if not DEFAULT_DESKTOP_RE.match(dbus_name.strip()):
        return dbus_name
    if position in kwin_names:
        return kwin_names[position]
    if position in configured:
        return configured[position]
    return dbus_name


def fetch_kde_desktops() -> list[tuple[int, str, str]]:
    try:
        literal = subprocess.check_output(
            [
                "qdbus6",
                "--literal",
                "org.kde.KWin",
                "/VirtualDesktopManager",
                "org.kde.KWin.VirtualDesktopManager.desktops",
            ],
            text=True,
            stderr=subprocess.DEVNULL,
        )
    except (subprocess.CalledProcessError, FileNotFoundError):
        return []

    desktops = [(int(pos), desktop_id, name) for pos, desktop_id, name in DESKTOP_RE.findall(literal)]
    desktops.sort(key=lambda item: item[0])
    return desktops


def kde_current_desktop_id(output: str | None = None) -> str:
    if output:
        try:
            cache_file = Path(os.environ.get("XDG_CACHE_HOME", Path.home() / ".cache")) / "waybar/kde-active-desktops.json"
            if cache_file.is_file():
                mapping = json.loads(cache_file.read_text(encoding="utf-8"))
                if output in mapping:
                    return str(mapping[output])
        except Exception:
            pass

    try:
        return subprocess.check_output(
            [
                "qdbus6",
                "org.kde.KWin",
                "/VirtualDesktopManager",
                "org.kde.KWin.VirtualDesktopManager.current",
            ],
            text=True,
            stderr=subprocess.DEVNULL,
        ).strip()
    except (subprocess.CalledProcessError, FileNotFoundError):
        return ""


def build_kde_state(output: str | None = None) -> dict:
    glyphs = load_glyphs()
    kwin_names = kwinrc_names()
    configured = configured_names()
    current = kde_current_desktop_id(output)
    desktops = []

    for position, desktop_id, dbus_name in fetch_kde_desktops():
        name = resolve_name(position, dbus_name, kwin_names, configured)
        desktops.append(
            {
                "position": position,
                "id": desktop_id,
                "name": name,
                "glyph": lookup_glyph(name, glyphs),
                "active": desktop_id == current,
            }
        )

    return {"compositor": "kde", "current": current, "desktops": desktops}


def resolve_hypr_name(position: int, raw_name: str, configured: dict[int, str]) -> str:
    # Hyprland often names workspaces "1","2",… — remap via configured index
    # (1-based name → 0-based key) before falling back to enumerate position.
    name = raw_name.strip()
    if name.isdigit():
        index = int(name) - 1
        if index in configured:
            return configured[index]
    if position in configured:
        return configured[position]
    return name


def build_hyprland_state(output: str | None = None) -> dict:
    glyphs = load_glyphs()
    configured = configured_names()

    try:
        workspaces = json.loads(
            subprocess.check_output(["hyprctl", "workspaces", "-j"], text=True, stderr=subprocess.DEVNULL)
        )
    except (subprocess.CalledProcessError, FileNotFoundError, json.JSONDecodeError):
        return {"compositor": "hyprland", "current": "", "desktops": []}

    active_workspace_id = None
    if output:
        try:
            monitors = json.loads(
                subprocess.check_output(["hyprctl", "monitors", "-j"], text=True, stderr=subprocess.DEVNULL)
            )
            for monitor in monitors:
                if monitor.get("name") == output:
                    active_workspace_id = str(monitor.get("activeWorkspace", {}).get("id", ""))
                    break
        except Exception:
            pass

    sorted_ws = sorted(workspaces, key=lambda item: item.get("id", 0))
    desktops = []
    current = ""

    for position, workspace in enumerate(sorted_ws):
        workspace_id = str(workspace.get("id", position + 1))
        name = resolve_hypr_name(position, str(workspace.get("name", workspace_id)), configured)
        
        if active_workspace_id is not None:
            active = (workspace_id == active_workspace_id)
        else:
            active = bool(workspace.get("focused", False))
            
        if active:
            current = workspace_id
        desktops.append(
            {
                "position": position,
                "id": workspace_id,
                "name": name,
                "glyph": lookup_glyph(name, glyphs),
                "active": active,
            }
        )

    return {"compositor": "hyprland", "current": current, "desktops": desktops}


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

    for proc in ("kwin_wayland", "kwin_x11"):
        try:
            subprocess.run(
                ["pgrep", "-x", proc],
                check=True,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )
            return "kde"
        except (subprocess.CalledProcessError, FileNotFoundError):
            pass

    for proc in ("Hyprland", "hyprland"):
        try:
            subprocess.run(
                ["pgrep", "-x", proc],
                check=True,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )
            return "hyprland"
        except (subprocess.CalledProcessError, FileNotFoundError):
            pass

    return "unknown"


def build_state(output: str | None = None) -> dict:
    compositor = detect_compositor()
    if compositor == "hyprland":
        return build_hyprland_state(output)
    if compositor == "kde":
        return build_kde_state(output)
    return {"compositor": compositor, "current": "", "desktops": []}


def main() -> int:
    position = int(sys.argv[1]) if len(sys.argv) > 1 else -1
    output = os.environ.get("WAYBAR_OUTPUT_NAME") or os.environ.get("WAYBAR_OUTPUT")

    import time
    cache_dir = Path(os.environ.get("XDG_CACHE_HOME", Path.home() / ".cache")) / "waybar"
    cache_file = cache_dir / f"workspaces-{output or 'default'}.json"

    # Short TTL so N workspace slot scripts in one Waybar tick share one
    # Hyprland/KWin query instead of each spawning qdbus/hyprctl.
    state = None
    if cache_file.is_file():
        try:
            mtime = cache_file.stat().st_mtime
            if (time.time() - mtime) < 0.2:
                state = json.loads(cache_file.read_text(encoding="utf-8"))
        except Exception:
            pass

    if state is None:
        state = build_state(output)
        try:
            cache_dir.mkdir(parents=True, exist_ok=True)
            tmp_file = cache_dir / f"{cache_file.name}.tmp.{os.getpid()}"
            tmp_file.write_text(json.dumps(state), encoding="utf-8")
            os.replace(tmp_file, cache_file)
        except Exception:
            pass

    if position >= 0:
        for desktop in state["desktops"]:
            if desktop["position"] == position:
                formatted = {
                    "text": desktop["glyph"],
                    "tooltip": desktop["name"],
                    "class": ["ws-hit", "ws-active" if desktop["active"] else "ws-inactive"]
                }
                print(json.dumps(formatted))
                return 0
        print(json.dumps({"text": "", "tooltip": "", "class": ["hidden"]}))
        return 0

    print(json.dumps(state))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
