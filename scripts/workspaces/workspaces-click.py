#!/usr/bin/env python3
"""Activate a workspace by slot index, or scroll desktops (optionally per-output)."""

from __future__ import annotations

import json
import os
import subprocess
import sys
import tempfile
from pathlib import Path

WAYBAR_HOME = Path(__file__).resolve().parents[2]
QUERY = WAYBAR_HOME / "scripts/workspaces/workspaces-query.py"


def query_state() -> dict:
    raw = subprocess.check_output([sys.executable, str(QUERY)], text=True)
    return json.loads(raw)


def _run_kwin_script(script_content: str, script_name: str = "temp_switch_desktop") -> bool:
    """Load, run, and unload a temporary KWin script. Returns True on best-effort success."""
    script_path = None
    try:
        with tempfile.NamedTemporaryFile(mode="w", suffix=".js", delete=False) as f:
            f.write(script_content)
            script_path = f.name

        subprocess.run(
            [
                "qdbus6",
                "org.kde.KWin",
                "/Scripting",
                "org.kde.kwin.Scripting.unloadScript",
                script_name,
            ],
            capture_output=True,
            check=False,
        )

        res = subprocess.run(
            [
                "qdbus6",
                "org.kde.KWin",
                "/Scripting",
                "org.kde.kwin.Scripting.loadScript",
                script_path,
                script_name,
            ],
            capture_output=True,
            text=True,
            check=False,
        )
        script_id = (res.stdout or "").strip()

        if script_id.isdigit():
            subprocess.run(
                [
                    "qdbus6",
                    "org.kde.KWin",
                    f"/Scripting/Script{script_id}",
                    "org.kde.kwin.Script.run",
                ],
                capture_output=True,
                check=False,
            )
            subprocess.run(
                [
                    "qdbus6",
                    "org.kde.KWin",
                    "/Scripting",
                    "org.kde.kwin.Scripting.unloadScript",
                    script_name,
                ],
                capture_output=True,
                check=False,
            )
            return True
    except Exception:
        return False
    finally:
        if script_path:
            try:
                os.remove(script_path)
            except OSError:
                pass
    return False


def activate_kde(desktop_id: str, position: int, output: str = "") -> None:
    if output:
        # Escape for embedding in a JS string literal.
        safe_output = output.replace("\\", "\\\\").replace('"', '\\"')
        safe_desktop = desktop_id.replace("\\", "\\\\").replace('"', '\\"')
        script_content = f"""
        (function() {{
            var outputName = "{safe_output}";
            var desktopId = "{safe_desktop}";
            var screens = workspace.screens || workspace.outputs || [];
            var targetOutput = null;
            for (var i = 0; i < screens.length; i++) {{
                if (screens[i].name === outputName) {{
                    targetOutput = screens[i];
                    break;
                }}
            }}
            var desktops = workspace.desktops || [];
            var targetDesktop = null;
            for (var j = 0; j < desktops.length; j++) {{
                if (desktops[j].id === desktopId) {{
                    targetDesktop = desktops[j];
                    break;
                }}
            }}
            if (targetDesktop && targetOutput) {{
                if (typeof workspace.setCurrentDesktopForScreen === "function") {{
                    workspace.setCurrentDesktopForScreen(targetDesktop, targetOutput);
                }} else {{
                    workspace.currentDesktop = targetDesktop;
                }}
            }}
        }})();
        """
        if _run_kwin_script(script_content, "temp_switch_desktop"):
            return

    try:
        subprocess.run(
            [
                "qdbus6",
                "org.kde.KWin",
                "/VirtualDesktopManager",
                "org.kde.KWin.VirtualDesktopManager.current",
                desktop_id,
            ],
            check=False,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
    except FileNotFoundError:
        return

    subprocess.run(
        [
            "qdbus6",
            "org.kde.KWin",
            "/KWin",
            "org.kde.KWin.setCurrentDesktop",
            str(position + 1),
        ],
        check=False,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )


def scroll_kde(direction: int, output: str = "") -> bool:
    """Scroll virtual desktops. direction: -1 (up/prev) or +1 (down/next)."""
    if output:
        safe_output = output.replace("\\", "\\\\").replace('"', '\\"')
        dir_js = -1 if direction < 0 else 1
        script_content = f"""
        (function() {{
            var outputName = "{safe_output}";
            var direction = {dir_js};
            var screens = workspace.screens || workspace.outputs || [];
            var targetOutput = null;
            for (var i = 0; i < screens.length; i++) {{
                if (screens[i].name === outputName) {{
                    targetOutput = screens[i];
                    break;
                }}
            }}
            if (!targetOutput) {{
                return;
            }}
            var desktops = workspace.desktops || [];
            if (!desktops.length) {{
                return;
            }}
            var current = null;
            if (typeof workspace.currentDesktopForScreen === "function") {{
                current = workspace.currentDesktopForScreen(targetOutput);
            }} else {{
                current = workspace.currentDesktop;
            }}
            var idx = 0;
            for (var j = 0; j < desktops.length; j++) {{
                if (current && desktops[j].id === current.id) {{
                    idx = j;
                    break;
                }}
            }}
            var nextIdx = (idx + direction + desktops.length) % desktops.length;
            var nextDesktop = desktops[nextIdx];
            if (typeof workspace.setCurrentDesktopForScreen === "function") {{
                workspace.setCurrentDesktopForScreen(nextDesktop, targetOutput);
            }} else {{
                workspace.currentDesktop = nextDesktop;
            }}
        }})();
        """
        return _run_kwin_script(script_content, "temp_scroll_desktop")

    method = "previousDesktop" if direction < 0 else "nextDesktop"
    try:
        subprocess.run(
            ["qdbus6", "org.kde.KWin", "/KWin", f"org.kde.KWin.{method}"],
            check=False,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            timeout=2,
        )
        return True
    except (FileNotFoundError, subprocess.TimeoutExpired):
        return False


def activate_hyprland(desktop_id: str) -> None:
    subprocess.run(
        ["hyprctl", "dispatch", "workspace", desktop_id],
        check=False,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )


def activate_slot(slot: int, output: str = "") -> bool:
    state = query_state()
    compositor = state.get("compositor", "unknown")
    desktops = state.get("desktops", [])
    if slot < 0 or slot >= len(desktops):
        return False

    desktop = desktops[slot]
    if compositor == "kde":
        activate_kde(str(desktop["id"]), int(desktop["position"]), output)
    elif compositor == "hyprland":
        activate_hyprland(str(desktop["id"]))
    else:
        return False
    return True


def main() -> int:
    if len(sys.argv) < 2:
        return 1

    action = sys.argv[1]
    output = sys.argv[2] if len(sys.argv) > 2 else ""

    if action in ("scroll-up", "scroll-down"):
        direction = -1 if action == "scroll-up" else 1
        return 0 if scroll_kde(direction, output) else 1

    if not action.isdigit():
        return 1
    slot = int(action)
    ok = activate_slot(slot, output)
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
