#!/usr/bin/env python3
import json
import os
import subprocess
import sys

def parse_devices(devs, parent_is_removable=False):
    targets = []
    for d in devs:
        name = d.get("name", "")
        dev_type = d.get("type", "")
        # Filter out loop, swap, zram
        if dev_type in ("loop", "zram", "swap") or "loop" in name or "zram" in name:
            continue
        
        is_rem = d.get("rm", False) or d.get("hotplug", False) or parent_is_removable
        
        children = d.get("children", [])
        if children:
            targets.extend(parse_devices(children, parent_is_removable=is_rem))
        else:
            if is_rem or dev_type == "rom":
                targets.append({
                    "name": name,
                    "type": dev_type,
                    "size": d.get("size", "Unknown"),
                    "vendor": d.get("vendor", "").strip() if d.get("vendor") else "",
                    "model": d.get("model", "").strip() if d.get("model") else "",
                    "fstype": d.get("fstype", ""),
                    "label": d.get("label", ""),
                    "mountpoint": d.get("mountpoint"),
                    "mountpoints": d.get("mountpoints", [])
                })
    return targets

def is_mounted(target):
    mp = target.get("mountpoint")
    if mp and mp.strip():
        return True
    mps = target.get("mountpoints")
    if mps and any(x.strip() for x in mps if x):
        return True
    return False

def get_mountpoints(target):
    mps = []
    mp = target.get("mountpoint")
    if mp and mp.strip():
        mps.append(mp.strip())
    for x in target.get("mountpoints", []):
        if x and x.strip() and x.strip() not in mps:
            mps.append(x.strip())
    return mps

def get_description(target):
    label = target.get("label") or ""
    model = target.get("model") or ""
    vendor = target.get("vendor") or ""
    name = target.get("name", "")
    size = target.get("size", "")
    
    desc_parts = []
    if vendor:
        desc_parts.append(vendor)
    if model:
        desc_parts.append(model)
    
    desc = " ".join(desc_parts).strip()
    if not desc:
        desc = label.strip()
    
    if not desc:
        desc = f"Drive /dev/{name}"
    else:
        if label.strip() and label.strip() != desc:
            desc = f"{desc} ({label.strip()})"
            
    return f"{desc} ({size})"

def main():
    try:
        res = subprocess.run(
            ["lsblk", "-J", "-o", "NAME,RM,TYPE,MOUNTPOINT,MOUNTPOINTS,SIZE,VENDOR,MODEL,FSTYPE,LABEL,HOTPLUG"],
            capture_output=True, text=True, check=True
        )
        data = json.loads(res.stdout)
        devices = data.get("blockdevices", [])
    except Exception as e:
        devices = []

    targets = parse_devices(devices)
    
    # Filter targets to only include those with non-zero size/valid media
    valid_targets = []
    for t in targets:
        # Ignore empty optical drives/card readers
        if t.get("size") == "0B" and not t.get("fstype"):
            continue
        valid_targets.append(t)

    # Actions: status or menu
    mode = "--status"
    if len(sys.argv) > 1:
        mode = sys.argv[1]

    if mode == "--menu":
        menu_items = []
        for t in valid_targets:
            desc = get_description(t)
            name = t["name"]
            mounted = is_mounted(t)
            
            if mounted:
                mps = get_mountpoints(t)
                menu_items.append({
                    "text": f"󱊟 Unmount/Eject {desc} [/dev/{name}]",
                    "action": "unmount",
                    "device": name,
                    "desc": desc
                })
                menu_items.append({
                    "text": f"󰉋 Open {desc} in File Manager",
                    "action": "open",
                    "device": name,
                    "mountpoints": mps
                })
            else:
                menu_items.append({
                    "text": f"󱊞 Mount {desc} [/dev/{name}]",
                    "action": "mount",
                    "device": name,
                    "desc": desc
                })
        
        menu_items.append({
            "text": "󰑐 Rescan Devices",
            "action": "rescan",
            "device": None
        })

        if not valid_targets:
            options_str = "No removable devices connected\n󰑐 Rescan Devices"
        else:
            options_str = "\n".join(item["text"] for item in menu_items)

        # Run rofi
        try:
            rofi_res = subprocess.run(
                ["rofi", "-dmenu", "-p", "Device Notifier", "-theme-str", "window {width: 500px;}"],
                input=options_str, capture_output=True, text=True
            )
            selected = rofi_res.stdout.strip()
        except Exception:
            selected = ""

        if not selected:
            sys.exit(0)

        # Process action
        selected_item = None
        for item in menu_items:
            if item["text"] == selected:
                selected_item = item
                break

        if selected == "󰑐 Rescan Devices":
            selected_item = {"action": "rescan"}

        if not selected_item:
            sys.exit(0)

        action = selected_item["action"]
        
        # Helper path for waybar-signal
        script_dir = os.path.dirname(os.path.realpath(__file__))
        signal_script = os.path.join(script_dir, "waybar-signal.sh")
        cache_file = os.path.expanduser("~/.cache/waybar/device-notifier-status.json")

        if action == "mount":
            dev = selected_item["device"]
            desc = selected_item["desc"]
            mount_res = subprocess.run(["udisksctl", "mount", "-b", f"/dev/{dev}"], capture_output=True, text=True)
            if mount_res.returncode == 0:
                subprocess.run(["notify-send", "Device Notifier", f"Mounted {desc} successfully."])
            else:
                err_msg = mount_res.stderr.strip() or "Unknown error"
                subprocess.run(["notify-send", "Device Notifier", f"Failed to mount {desc}: {err_msg}"])
            # Refresh waybar
            subprocess.run([signal_script, "19", cache_file])

        elif action == "unmount":
            dev = selected_item["device"]
            desc = selected_item["desc"]
            unmount_res = subprocess.run(["udisksctl", "unmount", "-b", f"/dev/{dev}"], capture_output=True, text=True)
            if unmount_res.returncode == 0:
                subprocess.run(["udisksctl", "power-off", "-b", f"/dev/{dev}"], capture_output=True)
                subprocess.run(["notify-send", "Device Notifier", f"Safely removed {desc}."])
            else:
                err_msg = unmount_res.stderr.strip() or "Unknown error"
                subprocess.run(["notify-send", "Device Notifier", f"Failed to unmount {desc}: {err_msg}"])
            # Refresh waybar
            subprocess.run([signal_script, "19", cache_file])

        elif action == "open":
            mps = selected_item["mountpoints"]
            if mps:
                subprocess.run(["xdg-open", mps[0]])

        elif action == "rescan":
            subprocess.run([signal_script, "19", cache_file])

    else:
        # Status mode (Waybar output)
        total_targets = len(valid_targets)
        mounted_targets = sum(1 for t in valid_targets if is_mounted(t))
        unmounted_targets = total_targets - mounted_targets
        
        if total_targets == 0:
            out = {
                "text": "",
                "tooltip": "Device Notifier\nNo removable devices connected",
                "class": "empty"
            }
        else:
            tooltip_lines = ["Removable Devices:"]
            for t in valid_targets:
                desc = get_description(t)
                name = t["name"]
                mounted = is_mounted(t)
                
                if mounted:
                    mps = get_mountpoints(t)
                    mps_str = ", ".join(mps)
                    tooltip_lines.append(f"● {desc} (/dev/{name})\n  Mounted at: {mps_str}")
                else:
                    tooltip_lines.append(f"○ {desc} (/dev/{name})\n  Unmounted")

            tooltip_lines.append("\nLeft: Open Devices Menu")
            tooltip = "\n".join(tooltip_lines)
            
            if unmounted_targets > 0:
                text = f"󰗏 {unmounted_targets}"
                cls = "unmounted"
            else:
                text = f"󱊟 {total_targets}"
                cls = "mounted"
                
            out = {
                "text": text,
                "tooltip": tooltip,
                "class": cls
            }
            
        print(json.dumps(out))

if __name__ == "__main__":
    main()
