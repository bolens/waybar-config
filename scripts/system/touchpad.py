#!/usr/bin/env python3
import json
import os
import subprocess
import sys

def get_touchpad_device():
    try:
        res = subprocess.run(["hyprctl", "devices", "-j"], capture_output=True, text=True, check=True)
        devices = json.loads(res.stdout)
        mice = devices.get("mice", [])
        
        # Scan mice for device containing touchpad keywords case-insensitively
        for m in mice:
            name = m.get("name", "")
            name_lower = name.lower()
            if "touchpad" in name_lower or "glidepoint" in name_lower or name_lower.startswith("elan") or name_lower.startswith("syna"):
                return name
    except Exception:
        pass
    return None

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
    return "unknown"

def main():
    home = os.path.expanduser("~")
    cache_dir = os.environ.get("XDG_CACHE_HOME", os.path.join(home, ".cache"))
    state_file = os.path.join(cache_dir, "waybar/touchpad-disabled")
    
    # Ensure cache directory exists
    os.makedirs(os.path.dirname(state_file), exist_ok=True)

    mode = "--status"
    if len(sys.argv) > 1:
        mode = sys.argv[1]

    # Match shell: WAYBAR_HOME → $XDG_CONFIG_HOME/waybar → ~/.config/waybar
    waybar_home = os.environ.get("WAYBAR_HOME") or os.path.join(
        os.environ.get("XDG_CONFIG_HOME", os.path.expanduser("~/.config")), "waybar"
    )
    waybar_scripts = os.environ.get("WAYBAR_SCRIPTS", os.path.join(waybar_home, "scripts"))
    signal_script = os.path.join(waybar_scripts, "lib", "waybar-signal.sh")
    cache_file = os.path.join(cache_dir, "waybar/touchpad-status.json")

    if mode == "--toggle":
        if detect_compositor() != "hyprland":
            subprocess.run(["notify-send", "Touchpad Status", "Touchpad toggle is only available on Hyprland."])
            sys.exit(0)
        device_name = get_touchpad_device()
        if not device_name:
            subprocess.run(["notify-send", "Touchpad Status", "No touchpad device found."])
            sys.exit(0)

        disabled = os.path.isfile(state_file)

        if disabled:
            # Enable touchpad
            try:
                os.remove(state_file)
            except Exception:
                pass
            subprocess.run(["hyprctl", "keyword", f"device:{device_name}:enabled", "true"], capture_output=True)
            subprocess.run(["notify-send", "Touchpad Status", "Touchpad enabled."])
        else:
            # Disable touchpad
            try:
                with open(state_file, "w") as f:
                    f.write("disabled")
            except Exception:
                pass
            subprocess.run(["hyprctl", "keyword", f"device:{device_name}:enabled", "false"], capture_output=True)
            subprocess.run(["notify-send", "Touchpad Status", "Touchpad disabled."])

        # Refresh waybar status (signal 20)
        subprocess.run([signal_script, "20", cache_file])

    else:
        # Status mode
        disabled = os.path.isfile(state_file)
        
        if disabled:
            out = {
                "text": "󰟴",
                "tooltip": "Touchpad: Disabled\nLeft: click to enable",
                "class": "disabled"
            }
        else:
            out = {
                "text": "󰟳",
                "tooltip": "Touchpad: Enabled\nLeft: click to disable",
                "class": "enabled"
            }
            
        print(json.dumps(out))

if __name__ == "__main__":
    main()
