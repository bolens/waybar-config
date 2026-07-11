#!/usr/bin/env python3
"""
ethernet-popup.py
=================

Waybar GTK popup for per-interface Ethernet/bond/Wi-Fi status.

Features:
    - Shows all interfaces, bonds, slaves, public IP, VPN, and more.
    - Sensitive info (all IPs, MACs, etc.) can be masked/unmasked with [S].
    - Details can be toggled with [M].
    - Debug output available when WAYBAR_DEBUG=1.
    - Robust error handling for missing tools.

Usage:
    $ python3 ethernet-popup.py <interface>
    (Typically launched by Waybar custom module button)

Key Bindings:
    [Esc] or [q]   - Close popup
    [M]            - Toggle more details
    [S]            - Show/hide sensitive info

Arguments:
    <interface>    - Network interface name (e.g., eth0, bond0)

Outputs:
    GTK popup window with per-interface and bond status.
    Prints debug output to stderr if DEBUG is enabled.

Example:
    See Waybar config for custom/ethernet button integration.
"""

import gi
import os
import re
import subprocess
import sys
import time

DEBUG = os.environ.get("WAYBAR_DEBUG", "").strip().lower() in ("1", "true", "yes")

gi.require_version("Gtk", "3.0")
try:
    gi.require_version("GtkLayerShell", "0.1")
    from gi.repository import GtkLayerShell  # noqa: E402

    LAYER_SHELL_AVAILABLE = True
except (ValueError, ImportError):
    LAYER_SHELL_AVAILABLE = False

from gi.repository import Gdk, GLib, Gtk  # noqa: E402

# Cache public IP for the session
_PUBLIC_IP = None

# Cache both real and VPN public IPs
_REAL_PUBLIC_IP = None
_VPN_PUBLIC_IP = None
def get_public_ips():
    global _REAL_PUBLIC_IP, _VPN_PUBLIC_IP
    # If already fetched, return cached
    if _REAL_PUBLIC_IP is not None and _VPN_PUBLIC_IP is not None:
        return _REAL_PUBLIC_IP, _VPN_PUBLIC_IP
    # Try to get real public IP by temporarily disabling VPN if possible
    # For now, just fetch current (VPN) IP, and try to fetch real IP by using the physical interface if possible
    try:
        _VPN_PUBLIC_IP = subprocess.check_output("curl -s --max-time 1 https://checkip.amazonaws.com", shell=True, text=True, timeout=1).strip()
        if not re.match(r"^\d+\.\d+\.\d+\.\d+$", _VPN_PUBLIC_IP):
            _VPN_PUBLIC_IP = 'n/a'
    except Exception:
        _VPN_PUBLIC_IP = 'n/a'
    # Try to get real public IP by using --interface if possible (Linux only)
    try:
        # Try to use the default physical interface for outgoing traffic
        default_iface = subprocess.check_output("ip route get 1 | awk '{print $5; exit}'", shell=True, text=True, timeout=2).strip()
        _REAL_PUBLIC_IP = subprocess.check_output(f"curl --interface {default_iface} -s --max-time 1 https://checkip.amazonaws.com", shell=True, text=True, timeout=1).strip()
        if not re.match(r"^\d+\.\d+\.\d+\.\d+$", _REAL_PUBLIC_IP):
            _REAL_PUBLIC_IP = 'n/a'
    except Exception:
        _REAL_PUBLIC_IP = _VPN_PUBLIC_IP
    return _REAL_PUBLIC_IP, _VPN_PUBLIC_IP

def nmcli_device_connection(iface):
    try:
        out = subprocess.check_output(
            ['nmcli', '-t', '-f', 'GENERAL.CONNECTION', 'device', 'show', iface],
            text=True,
            stderr=subprocess.DEVNULL if not DEBUG else None,
            timeout=2,
        ).strip()
        if not out:
            return ''
        line = out.splitlines()[0]
        return line.split(':', 1)[1] if ':' in line else line
    except Exception as e:
        if DEBUG:
            print(f"[DEBUG] nmcli device connection for {iface} => Exception: {e}", file=sys.stderr)
        return ''


# Helper to get ethernet info (mimics your shell logic)
def get_eth_info(iface):
    def run(cmd):
        try:
            result = subprocess.check_output(
                cmd,
                shell=True,
                text=True,
                stderr=subprocess.DEVNULL if not DEBUG else None,
            ).strip()
            if DEBUG:
                print(f"[DEBUG] {cmd} => {result}", file=sys.stderr)
            return result
        except Exception as e:
            if DEBUG:
                print(f"[DEBUG] {cmd} => Exception: {e}", file=sys.stderr)
            return ''

    # Always get permanent MAC and speed from the real interface (never from bond)
    mac = get_permanent_mac(iface) or run(f"cat /sys/class/net/{iface}/address")
    speed = run(f"cat /sys/class/net/{iface}/speed")
    if speed.isdigit():
        speed = f"{int(speed)//1000} Gbps" if int(speed) >= 1000 else f"{speed} Mbps"
    else:
        speed = 'n/a'

    status = get_interface_status(iface)
    bond_master = get_bond_master(iface)
    use_bond = bond_master and is_bond_up(bond_master) and status == "connected"
    info_iface = bond_master if use_bond else iface
    if DEBUG:
        print(f"[DEBUG] info_iface for {iface}: {info_iface} (use_bond={use_bond})", file=sys.stderr)

    ip4 = netmask = gateway = dns = 'n/a'
    if status == "connected":
        info_profile = nmcli_device_connection(info_iface)
        ip4_cidr = run(f"nmcli -g IP4.ADDRESS device show {info_iface} | awk 'NR==1 {{print; exit}}'")
        if ip4_cidr:
            ip4_split = ip4_cidr.split('/')
            ip4 = ip4_split[0]
            if len(ip4_split) > 1:
                try:
                    prefix = int(ip4_split[1])
                    # Convert CIDR prefix to netmask
                    mask = (0xffffffff >> (32 - prefix)) << (32 - prefix)
                    netmask = f"{(mask >> 24) & 0xff}.{(mask >> 16) & 0xff}.{(mask >> 8) & 0xff}.{mask & 0xff}"
                except Exception:
                    netmask = 'n/a'
        if (not ip4) and info_profile and info_profile != '--':
            ip4_cidr = run(f"nmcli -g ip4.address connection show '{info_profile}' | awk 'NR==1 {{print; exit}}'")
            if ip4_cidr:
                ip4_split = ip4_cidr.split('/')
                ip4 = ip4_split[0]
                if len(ip4_split) > 1:
                    try:
                        prefix = int(ip4_split[1])
                        mask = (0xffffffff >> (32 - prefix)) << (32 - prefix)
                        netmask = f"{(mask >> 24) & 0xff}.{(mask >> 16) & 0xff}.{(mask >> 8) & 0xff}.{mask & 0xff}"
                    except Exception:
                        netmask = 'n/a'
        gateway = run(f"nmcli -g IP4.GATEWAY device show {info_iface}")
        if (not gateway) and info_profile and info_profile != '--':
            gateway = run(f"nmcli -g ipv4.gateway connection show '{info_profile}'")
        dns = run(f"nmcli -g IP4.DNS device show {info_iface} | paste -sd ', ' -")
        if (not dns) and info_profile and info_profile != '--':
            dns = run(f"nmcli -g ipv4.dns connection show '{info_profile}' | paste -sd ', ' -")

    profile = nmcli_device_connection(iface)
    real_ip, vpn_ip = get_public_ips()
    # Always show the MAC of the physical interface, not the bond, even if info_iface is the bond
    return {
        'Interface': iface,
        'Connection': profile,
        'Status': status,
        'IP': ip4 or 'n/a',
        'Netmask': netmask or 'n/a',
        'MAC': mac or 'n/a',
        'Gateway': gateway or 'n/a',
        'DNS': dns or 'n/a',
        'Speed': speed or 'n/a',
        'RealPublicIP': real_ip,
    }

def get_default_iface():
    # Try to find the first up ethernet interface
    try:
        out = subprocess.check_output(
            "ip -o link show | awk '{sub(/:/,\"\",$2)} $2 ~ /^(eno|enp|ens|eth)/ && /state UP/ {print $2; exit}'",
            shell=True, text=True).strip()
        if out:
            return out
    except Exception:
        pass
    # Fallback: any ethernet
    try:
        out = subprocess.check_output(
            "ip -o link show | awk '{sub(/:/,\"\",$2)} $2 ~ /^(eno|enp|ens|eth)/ {print $2; exit}'",
            shell=True, text=True).strip()
        if out:
            return out
    except Exception:
        pass
    return 'eno1'

def get_mouse_position():
    import os
    # Prefer shared launch export, then Hyprland signature.
    comp = (os.environ.get("WAYBAR_COMPOSITOR") or "").strip().lower()
    if comp == "hyprland" or os.environ.get("HYPRLAND_INSTANCE_SIGNATURE"):
        try:
            out = subprocess.check_output(["hyprctl", "cursorpos"], text=True).strip()
            x, y = map(int, out.split(","))
            return x, y
        except Exception:
            pass
    # Try X11
    try:
        import Xlib.display
        display = Xlib.display.Display()
        root = display.screen().root
        pointer = root.query_pointer()
        return pointer.root_x, pointer.root_y
    except Exception:
        pass
    # Try xdotool (X11)
    try:
        out = subprocess.check_output(["xdotool", "getmouselocation", "--shell"], text=True)
        vals = dict(line.split("=") for line in out.strip().splitlines() if "=" in line)
        return int(vals["X"]), int(vals["Y"])
    except Exception:
        pass
    # Try swaymsg (Wayland, sway)
    try:
        out = subprocess.check_output(["swaymsg", "-t", "get_seats"], text=True)
        import json
        seats = json.loads(out)
        for seat in seats:
            if "devices" in seat:
                for dev in seat["devices"]:
                    if dev.get("type") == "pointer" and "xy" in dev:
                        return dev["xy"]
    except Exception:
        pass
    # GTK seat pointer (works on Plasma Wayland once display is up)
    try:
        display = Gdk.Display.get_default()
        if display is not None:
            seat = display.get_default_seat()
            if seat is not None:
                pointer = seat.get_pointer()
                if pointer is not None:
                    # Gdk 3: get_position; Gdk 4 differs — try both.
                    if hasattr(pointer, "get_position"):
                        _screen, x, y = pointer.get_position()
                        return int(x), int(y)
            monitor = display.get_primary_monitor() if hasattr(display, "get_primary_monitor") else None
            if monitor is None and hasattr(display, "get_monitor"):
                monitor = display.get_monitor(0)
            if monitor is not None:
                geo = monitor.get_geometry()
                return geo.x + geo.width // 2, geo.y + geo.height // 2
    except Exception:
        pass
    return 960, 540  # Fallback to 1080p center

def get_bond_master(iface):
    import os
    try:
        master_path = f"/sys/class/net/{iface}/master"
        if os.path.islink(master_path):
            master = os.path.basename(os.readlink(master_path))
            if DEBUG:
                print(f"[DEBUG] {iface} bond master: {master}", file=sys.stderr)
            return master
        else:
            if DEBUG:
                print(f"[DEBUG] {iface} has no bond master (not a symlink)", file=sys.stderr)
            return None
    except Exception as e:
        if DEBUG:
            print(f"[DEBUG] {iface} has no bond master: {e}", file=sys.stderr)
        return None

def get_permanent_mac(iface):
    try:
        out = subprocess.check_output(f"ethtool -P {iface}", shell=True, text=True)
        m = re.search(r"Permanent address: ([0-9a-f:]{17})", out)
        if m:
            if DEBUG:
                print(f"[DEBUG] ethtool -P {iface} => {m.group(1)}", file=sys.stderr)
            return m.group(1)
    except Exception as e:
        if DEBUG:
            print(f"[DEBUG] ethtool -P {iface} => Exception: {e}", file=sys.stderr)
        return ''

def is_bond_up(bond_iface):
    try:
        state = open(f"/sys/class/net/{bond_iface}/operstate").read().strip()
        if DEBUG:
            print(f"[DEBUG] {bond_iface} operstate: {state}", file=sys.stderr)
        return state == "up"
    except Exception as e:
        if DEBUG:
            print(f"[DEBUG] {bond_iface} operstate => Exception: {e}", file=sys.stderr)
        return False

def get_interface_status(iface):
    try:
        state = open(f"/sys/class/net/{iface}/operstate").read().strip()
        if DEBUG:
            print(f"[DEBUG] {iface} operstate: {state}", file=sys.stderr)
        return "connected" if state == "up" else "disconnected"
    except Exception as e:
        if DEBUG:
            print(f"[DEBUG] {iface} operstate => Exception: {e}", file=sys.stderr)
        return "unknown"

def get_bond_slaves(bond_iface):
    import glob
    slaves = []
    try:
        # Find all lower_* symlinks (ethernet and wifi)
        slave_paths = glob.glob(f"/sys/class/net/{bond_iface}/lower_*")
        for path in slave_paths:
            slave = os.path.basename(path).replace("lower_", "")
            slaves.append(slave)
        # Also add any wlan* interfaces that are part of the bond (Wi-Fi slaves)
        wifi_candidates = glob.glob("/sys/class/net/*")
        for wifi_path in wifi_candidates:
            wifi_iface = os.path.basename(wifi_path)
            if wifi_iface.startswith("wlan") or wifi_iface.startswith("wlp"):
                master_path = f"/sys/class/net/{wifi_iface}/master"
                if os.path.islink(master_path):
                    master = os.path.basename(os.readlink(master_path))
                    if master == bond_iface and wifi_iface not in slaves:
                        slaves.append(wifi_iface)
        if DEBUG:
            print(f"[DEBUG] {bond_iface} slaves (with wifi): {slaves}", file=sys.stderr)
    except Exception as e:
        if DEBUG:
            print(f"[DEBUG] get_bond_slaves({bond_iface}) => Exception: {e}", file=sys.stderr)
    return slaves

class EthPopup(Gtk.Window):
    def __init__(self, infos, title=None):
        Gtk.Window.__init__(self, title=title or "Ethernet Info")
        self._layer_shell_anchor_set = False
        if LAYER_SHELL_AVAILABLE:
            GtkLayerShell.init_for_window(self)
        self.set_border_width(16)
        self.set_resizable(False)
        self.set_type_hint(Gdk.WindowTypeHint.DIALOG)
        self.set_keep_above(True)
        self.set_decorated(False)
        self.connect("key-press-event", self.on_key)
        self.connect("delete-event", lambda *a: Gtk.main_quit())
        self.expanded = False
        self.sensitive = False
        self.infos = infos  # list of (label, info_dict)
        self.is_bond = len(infos) > 1
        self.build_ui()
        self.connect("map-event", self.on_position_event)
        self.connect("size-allocate", self.on_position_event)

    def set_layer_shell_anchor(self):
        if getattr(self, '_layer_shell_anchor_set', False):
            return
        # Force top-right anchor (pointer geometry unused for layer-shell layout)
        for edge in [GtkLayerShell.Edge.TOP, GtkLayerShell.Edge.BOTTOM, GtkLayerShell.Edge.LEFT, GtkLayerShell.Edge.RIGHT]:
            GtkLayerShell.set_anchor(self, edge, False)
        GtkLayerShell.set_anchor(self, GtkLayerShell.Edge.TOP, True)
        GtkLayerShell.set_anchor(self, GtkLayerShell.Edge.RIGHT, True)
        # Fixed margins for top-right corner
        margin_top = 20
        margin_right = 20
        GtkLayerShell.set_margin(self, GtkLayerShell.Edge.TOP, margin_top)
        GtkLayerShell.set_margin(self, GtkLayerShell.Edge.RIGHT, margin_right)
        GtkLayerShell.set_keyboard_mode(self, GtkLayerShell.KeyboardMode.ON_DEMAND)
        self._layer_shell_anchor_set = True

    def on_position_event(self, *args):
        if LAYER_SHELL_AVAILABLE:
            self.set_layer_shell_anchor()
        else:
            self.reposition()

    def reposition(self):
        display = Gdk.Display.get_default()
        seat = display.get_default_seat()
        pointer = seat.get_pointer()
        _, x, y = pointer.get_position()
        self._last_pointer = (x, y)
        monitor = display.get_monitor_at_point(x, y)
        geo = monitor.get_geometry()
        alloc = self.get_allocation()
        win_width = alloc.width or 400
        win_height = alloc.height or 200
        px = min(max(geo.x, x - win_width // 2), geo.x + geo.width - win_width)
        py = min(max(geo.y, y + 10), geo.y + geo.height - win_height)
        self.move(px, py)

    def build_ui(self):
        vbox = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10)
        self.add(vbox)
        # Header
        if len(self.infos) == 1:
            iface = self.infos[0][0]
            icon = "󰈀" if not iface.lower().startswith("wlan") else "󰤨"
            self.header_label = Gtk.Label()
            self.header_label.set_markup(f"<span size='x-large'><b>{icon}  Ethernet: <span foreground='#00e5ff'>{iface}</span></b></span>")
            self.header_label.set_xalign(0)
            vbox.pack_start(self.header_label, False, False, 0)
        else:
            self.header_label = Gtk.Label()
            self.header_label.set_markup(f"<span size='x-large'><b>󰌾  Bond: <span foreground='#00e5ff'>{self.infos[0][0]}</span></b></span>")
            self.header_label.set_xalign(0)
            vbox.pack_start(self.header_label, False, False, 0)
        use_scroll = False
        if len(self.infos) > 4:
            use_scroll = True
        elif self.expanded:
            # Estimate if expanded content will be tall; if so, use scroll
            num_fields = 4 + (6 if self.expanded else 0)
            num_sections = len(self.infos)
            est_height = (num_fields * num_sections * 38) + 60
            if est_height > 600:
                use_scroll = True
        if use_scroll:
            scroll = Gtk.ScrolledWindow()
            scroll.set_policy(Gtk.PolicyType.AUTOMATIC, Gtk.PolicyType.AUTOMATIC)
            scroll.set_min_content_width(480)
            if self.expanded:
                scroll.set_min_content_height(1000)
            vbox.pack_start(scroll, True, True, 0)
            inner_vbox = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12)
            scroll.add(inner_vbox)
            frame_pack_args = (False, False, 0)
        else:
            inner_vbox = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12)
            vbox.pack_start(inner_vbox, False, False, 0)
            frame_pack_args = (False, False, 0)
        for label, info in self.infos:
            # Choose icon and color for each interface type
            if label.startswith("Master"):
                icon = "󰡠"
                color = "#ffd700"
            elif label.startswith("Bond"):
                icon = "󰌾"
                color = "#00bfff"
            elif label.lower().startswith("slave") and info.get('Interface', '').lower().startswith("wlan"):
                icon = "󰤨"
                color = "#00bfff"
            else:
                icon = "󰈀"
                color = "#00bfff"
            # Status indicator
            status = info.get('Status', '').lower()
            if status == 'connected':
                status_icon = "<span foreground='#44ff44'>●</span>"
            elif status == 'disconnected':
                status_icon = "<span foreground='#ff2a7f'>●</span>"
            else:
                status_icon = "<span foreground='#ffd700'>●</span>"
            # Frame with subtle background
            frame = Gtk.Frame()
            frame.set_shadow_type(Gtk.ShadowType.ETCHED_IN)
            frame.set_label_widget(Gtk.Label(label=f"{icon} <b><span foreground='{color}'>{label}</span></b> {status_icon}", use_markup=True))
            grid = Gtk.Grid(column_spacing=16, row_spacing=6)
            row = 0
            fields = [
                ("<span foreground='#b0b8c1'><b>Connection</b></span>", f"<span foreground='#00bfff'>{info['Connection']}</span>"),
                ("<span foreground='#b0b8c1'><b>Status</b></span>", f"<span foreground='#00bfff'>{info['Status']}</span>"),
                ("<span foreground='#b0b8c1'><b>IP</b></span>", f"<span foreground='#00bfff'>{info['IP'] if self.sensitive else '••••••••'}</span>"),
                ("<span foreground='#b0b8c1'><b>Netmask</b></span>", f"<span foreground='#00bfff'>{info['Netmask'] if self.sensitive else '••••••••'}</span>"),
            ]
            if self.expanded:
                fields += [
                    ("<span foreground='#b0b8c1'><b>MAC</b></span>", f"<span foreground='#00bfff'>{info['MAC'] if self.sensitive else '••••••••'}</span>"),
                    ("<span foreground='#b0b8c1'><b>Gateway</b></span>", f"<span foreground='#00bfff'>{info['Gateway'] if self.sensitive else '••••••••'}</span>"),
                    ("<span foreground='#b0b8c1'><b>DNS</b></span>", f"<span foreground='#00bfff'>{info['DNS']}</span>"),
                    ("<span foreground='#b0b8c1'><b>Speed</b></span>", f"<span foreground='#00bfff'>{info['Speed']}</span>"),
                    ("<span foreground='#b0b8c1'><b>Real Public IP</b></span>", f"<span foreground='#00bfff'>{info['RealPublicIP'] if self.sensitive else '••••••••'}</span>"),
                ]
            for k, v in fields:
                key_lbl = Gtk.Label()
                key_lbl.set_markup(k)
                key_lbl.set_xalign(0)
                val_lbl = Gtk.Label()
                val_lbl.set_markup(v)
                val_lbl.set_xalign(0)
                grid.attach(key_lbl, 0, row, 1, 1)
                grid.attach(val_lbl, 1, row, 1, 1)
                row += 1
            frame.add(grid)
            inner_vbox.pack_start(frame, *frame_pack_args)
        # Keybind hints
        self.hints = Gtk.Label()
        self.hints.set_markup("<span foreground='#8aa2c5'>[M] Details  [S] Sensitive  [Esc] Close</span>")
        self.hints.set_xalign(0)
        vbox.pack_start(self.hints, False, False, 0)
        self.show_all()
        # Ensure popup grabs keyboard focus for keybinds
        self.present()
        self.grab_focus()

    def on_key(self, widget, event):
        key = Gdk.keyval_name(event.keyval)
        if key in ('Escape', 'q'):
            Gtk.main_quit()
        elif key in ('m', 'M'):
            self.expanded = not self.expanded
            self.rebuild()
        elif key in ('s', 'S'):
            self.sensitive = not self.sensitive
            self.rebuild()

    def rebuild(self):
        # Remove all children and rebuild UI
        for child in self.get_children():
            self.remove(child)
        self.build_ui()
        self.reposition()

    def position_below_mouse(self):
        # Wait for window to be realized
        while not self.get_realized():
            while Gtk.events_pending():
                Gtk.main_iteration_do(False)
            time.sleep(0.01)
        x, y = get_mouse_position()
        alloc = self.get_allocation()
        win_width = alloc.width or 400
        win_height = alloc.height or 200
        display = Gdk.Display.get_default()
        monitor = display.get_primary_monitor() if display else None
        if monitor:
            geo = monitor.get_geometry()
            px = min(max(geo.x, x - win_width // 2), geo.x + geo.width - win_width)
            py = min(max(geo.y, y + 10), geo.y + geo.height - win_height)
            self.move(px, py)
        else:
            self.move(x, y)

    def position_below_mouse_robust(self):
        # Use Gdk.Display and Gdk.Monitor for modern geometry
        def do_position():
            if not self.get_realized() or not self.get_window():
                return True  # Try again later
            display = Gdk.Display.get_default()
            seat = display.get_default_seat()
            pointer = seat.get_pointer()
            _, x, y = pointer.get_position()
            monitor = display.get_monitor_at_point(x, y)
            geo = monitor.get_geometry()
            alloc = self.get_allocation()
            win_width = alloc.width or 400
            win_height = alloc.height or 200
            px = min(max(geo.x, x - win_width // 2), geo.x + geo.width - win_width)
            py = min(max(geo.y, y + 10), geo.y + geo.height - win_height)
            self.move(px, py)
            return False
        GLib.idle_add(do_position)


def main():
    import sys
    if len(sys.argv) < 2:
        print("Usage: ethernet-popup.py <interface>")
        sys.exit(1)
    iface = sys.argv[1]
    if iface.startswith("bond"):  # If bond0, show master and all slaves
        bond_info = get_eth_info(iface)
        slaves = get_bond_slaves(iface)
        slave_infos = [(s, get_eth_info(s)) for s in slaves]
        # Find the currently active slave (master) from /proc/net/bonding/<bond>
        active_slave = None
        try:
            with open(f"/proc/net/bonding/{iface}") as f:
                for line in f:
                    if line.startswith("Currently Active Slave:"):
                        active_slave = line.split(":", 1)[1].strip()
                        break
        except Exception as e:
            if DEBUG:
                print(f"[DEBUG] Could not read active slave: {e}", file=sys.stderr)
        # Separate out the active slave
        master_info = None
        other_infos = []
        for s, info in slave_infos:
            if s == active_slave:
                master_info = (f"Master: {s}", info)
            else:
                other_infos.append((s, info))
        # Sort others: connected first, then disconnected, then unknown
        def status_key(item):
            status = item[1].get('Status', '').lower()
            if status == 'connected':
                return 0
            elif status == 'disconnected':
                return 1
            else:
                return 2
        other_infos_sorted = sorted(other_infos, key=status_key)
        all_infos = [("Bond", bond_info)]
        if master_info:
            all_infos.append(master_info)
        all_infos += [(f"Slave: {s}", info) for s, info in other_infos_sorted]
        win = EthPopup(all_infos, title=f"Bond: {iface}")
        win.show_all()
        win.position_below_mouse_robust()
        Gtk.main()
        sys.exit(0)
    # Single interface
    info = get_eth_info(iface)
    win = EthPopup([(iface, info)], title=f"Ethernet: {iface}")
    win.show_all()
    win.position_below_mouse_robust()
    Gtk.main()

if __name__ == "__main__":
    main()

