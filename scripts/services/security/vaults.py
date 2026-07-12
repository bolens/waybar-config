#!/usr/bin/env python3
"""gocryptfs vault discovery and Waybar status/click helpers.

Scans a vaults base directory for mount dirs paired with cipher dirs named
`.<Name>`, `.<Name>.cipher`, or `<Name>_cipher` (must contain gocryptfs.conf).
"""
import json
import os
import subprocess
import sys

def get_vaults(base_dir):
    if not os.path.isdir(base_dir):
        return []
    
    vaults = []
    # Scan base_dir for directories
    for item in os.listdir(base_dir):
        if item.startswith("."):
            continue
        mount_path = os.path.join(base_dir, item)
        if not os.path.isdir(mount_path):
            continue
        
        # Look for corresponding cipher directory
        # Standard: .<Name> or .<Name>.cipher
        cipher_paths = [
            os.path.join(base_dir, f".{item}"),
            os.path.join(base_dir, f".{item}.cipher"),
            os.path.join(base_dir, f"{item}_cipher")
        ]
        
        cipher_dir = None
        for cp in cipher_paths:
            if os.path.isdir(cp) and os.path.isfile(os.path.join(cp, "gocryptfs.conf")):
                cipher_dir = cp
                break
                
        if cipher_dir:
            vaults.append({
                "name": item,
                "mount": mount_path,
                "cipher": cipher_dir
            })
            
    return vaults

def is_mounted(mount_path):
    res = subprocess.run(["findmnt", "-n", "-M", mount_path], capture_output=True)
    return res.returncode == 0

def main():
    home = os.path.expanduser("~")
    base_dir = os.path.join(home, "Vaults")
    rofi_width = 400

    # Read overrides from waybar-settings if possible
    settings_file = os.path.join(home, ".config/waybar/data/waybar-settings.json")
    # Match shell: WAYBAR_HOME → $XDG_CONFIG_HOME/waybar → ~/.config/waybar
    waybar_home = os.environ.get("WAYBAR_HOME") or os.path.join(
        os.environ.get("XDG_CONFIG_HOME", os.path.join(home, ".config")), "waybar"
    )
    for candidate in (
        os.path.join(waybar_home, "data", "waybar-settings.json"),
        settings_file,
    ):
        if os.path.isfile(candidate):
            try:
                with open(candidate, "r", encoding="utf-8") as f:
                    settings = json.load(f)
                bd = settings.get("vaults", {}).get("base_dir")
                if bd:
                    base_dir = bd
                rofi_width = int(
                    settings.get("rofi", {}).get("vaults", {}).get("width", rofi_width)
                )
            except Exception:
                pass
            break

    vaults = get_vaults(base_dir)

    mode = "--status"
    if len(sys.argv) > 1:
        mode = sys.argv[1]

    # Match shell: WAYBAR_HOME → $XDG_CONFIG_HOME/waybar → ~/.config/waybar
    waybar_home = os.environ.get("WAYBAR_HOME") or os.path.join(
        os.environ.get("XDG_CONFIG_HOME", os.path.expanduser("~/.config")), "waybar"
    )
    waybar_scripts = os.environ.get("WAYBAR_SCRIPTS", os.path.join(waybar_home, "scripts"))
    signal_script = os.path.join(waybar_scripts, "lib", "waybar-signal.sh")
    cache_file = os.path.expanduser("~/.cache/waybar/vaults-status.json")

    if mode == "--menu":
        if not vaults:
            subprocess.run(["notify-send", "KDE Vaults", f"No vaults found in {base_dir}."])
            sys.exit(0)

        menu_lines = []
        for v in vaults:
            mounted = is_mounted(v["mount"])
            if mounted:
                menu_lines.append(f"󰌿 Lock {v['name']}")
            else:
                menu_lines.append(f"󰌾 Unlock {v['name']}")

        options_str = "\n".join(menu_lines)
        theme_str = f"window {{width: {rofi_width}px;}}"

        try:
            rofi_res = subprocess.run(
                ["rofi", "-dmenu", "-p", "KDE Vaults", "-theme-str", theme_str],
                input=options_str, capture_output=True, text=True
            )
            selected = rofi_res.stdout.strip()
        except Exception:
            selected = ""

        if not selected:
            sys.exit(0)

        selected_vault_name = selected.split(" ", 2)[-1]
        selected_vault = next((v for v in vaults if v["name"] == selected_vault_name), None)

        if not selected_vault:
            sys.exit(0)

        action = "lock" if "Lock" in selected else "unlock"

        if action == "unlock":
            # Prompt password via rofi
            try:
                pass_res = subprocess.run(
                    ["rofi", "-dmenu", "-password", "-p", f"Password for {selected_vault_name}", "-theme-str", theme_str],
                    capture_output=True, text=True
                )
                password = pass_res.stdout.strip()
            except Exception:
                password = ""

            if not password:
                sys.exit(0)

            # Unlock using gocryptfs
            mount_proc = subprocess.Popen(
                ["gocryptfs", selected_vault["cipher"], selected_vault["mount"]],
                stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True
            )
            stdout, stderr = mount_proc.communicate(input=password + "\n")
            
            if mount_proc.returncode == 0:
                subprocess.run(["notify-send", "KDE Vaults", f"Vault '{selected_vault_name}' unlocked."])
            else:
                err_msg = stderr.strip() or "Incorrect password or mount failed."
                subprocess.run(["notify-send", "KDE Vaults", f"Failed to unlock '{selected_vault_name}': {err_msg}"])

            subprocess.run([signal_script, "21", cache_file])

        elif action == "lock":
            # Lock vault by unmounting
            lock_res = subprocess.run(["fusermount", "-u", selected_vault["mount"]], capture_output=True, text=True)
            if lock_res.returncode == 0:
                subprocess.run(["notify-send", "KDE Vaults", f"Vault '{selected_vault_name}' locked."])
            else:
                err_msg = lock_res.stderr.strip() or "Mount is busy."
                subprocess.run(["notify-send", "KDE Vaults", f"Failed to lock '{selected_vault_name}': {err_msg}"])

            subprocess.run([signal_script, "21", cache_file])

    else:
        # Status mode
        if not vaults:
            out = {
                "text": "",
                "tooltip": f"KDE Vaults\nNo vaults found in {base_dir}",
                "class": "empty"
            }
        else:
            unlocked_count = 0
            tooltip_lines = ["KDE Vaults:"]
            for v in vaults:
                mounted = is_mounted(v["mount"])
                if mounted:
                    unlocked_count += 1
                    tooltip_lines.append(f"● {v['name']}: Unlocked")
                else:
                    tooltip_lines.append(f"○ {v['name']}: Locked")

            tooltip_lines.append("\nLeft: Open Vaults Menu")
            tooltip = "\n".join(tooltip_lines)

            if unlocked_count > 0:
                text = "󰌿"
                cls = "unlocked"
            else:
                text = "󰌾"
                cls = "locked"

            out = {
                "text": text,
                "tooltip": tooltip,
                "class": cls
            }

        # Escape special XML/HTML characters to prevent Pango markup crashes in Waybar tooltips
        import html
        if "text" in out:
            out["text"] = html.escape(out["text"])
        if "tooltip" in out:
            out["tooltip"] = html.escape(out["tooltip"])
        print(json.dumps(out))

if __name__ == "__main__":
    main()
