#!/usr/bin/env python3
"""Activate a workspace by slot index."""

from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path

WAYBAR_HOME = Path(__file__).resolve().parents[2]
QUERY = WAYBAR_HOME / "scripts/workspaces/workspaces-query.py"


def query_state() -> dict:
    raw = subprocess.check_output([sys.executable, str(QUERY)], text=True)
    return json.loads(raw)


def activate_kde(desktop_id: str, position: int, output: str = "") -> None:
    if output:
        # Switch the desktop specifically on the given output/monitor using a temporary KWin script
        script_content = f"""
        (function() {{
            var outputName = "{output}";
            var desktopId = "{desktop_id}";
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
        import tempfile
        import os
        try:
            with tempfile.NamedTemporaryFile(mode="w", suffix=".js", delete=False) as f:
                f.write(script_content)
                script_path = f.name
            
            # Unload any existing temp script
            subprocess.run([
                "qdbus6", "org.kde.KWin", "/Scripting",
                "org.kde.kwin.Scripting.unloadScript", "temp_switch_desktop"
            ], capture_output=True)
            
            # Load and run the script
            res = subprocess.run([
                "qdbus6", "org.kde.KWin", "/Scripting",
                "org.kde.kwin.Scripting.loadScript", script_path, "temp_switch_desktop"
            ], capture_output=True, text=True)
            script_id = res.stdout.strip()
            
            if script_id.isdigit():
                subprocess.run([
                    "qdbus6", "org.kde.KWin", f"/Scripting/Script{script_id}",
                    "org.kde.kwin.Script.run"
                ], capture_output=True)
                # Unload it right after execution
                subprocess.run([
                    "qdbus6", "org.kde.KWin", "/Scripting",
                    "org.kde.kwin.Scripting.unloadScript", "temp_switch_desktop"
                ], capture_output=True)
            try:
                os.remove(script_path)
            except Exception:
                pass
            return
        except Exception:
            pass

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
    if len(sys.argv) < 2 or not sys.argv[1].isdigit():
        return 1
    slot = int(sys.argv[1])
    output = sys.argv[2] if len(sys.argv) > 2 else ""
    ok = activate_slot(slot, output)
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
