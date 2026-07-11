#!/usr/bin/env python3
"""
vpn-status-popup.py
===================

Waybar GTK popup for system-wide VPN/Privacy status.

Features:
    - Shows Tailscale, Netbird, VPN (NetworkManager), and public IP info.
    - Sensitive info (all IPs, user IDs, login/display names) can be masked/unmasked with [S].
    - Details can be toggled with [M].
    - Debug output available when WAYBAR_DEBUG=1.
    - Robust error handling for missing tools.

Usage:
    $ python3 vpn-status-popup.py
    (Typically launched by Waybar custom module button)

Key Bindings:
    [Esc] or [q]   - Close popup
    [M]            - Toggle more details
    [S]            - Show/hide sensitive info

Arguments:
    None

Outputs:
    GTK popup window with system-wide VPN/privacy status.
    Prints debug output to stderr if DEBUG is enabled.

Example:
    See Waybar config for custom/vpnstatus button integration.
"""

import concurrent.futures
import gi
import json
import os
import re
import subprocess
import sys
from pathlib import Path

DEBUG = os.environ.get("WAYBAR_DEBUG", "").strip().lower() in ("1", "true", "yes")

# Robustly suppress all non-debug output (including C-level and subprocess output)
if not DEBUG:
    devnull = os.open(os.devnull, os.O_WRONLY)
    os.dup2(devnull, 1)  # stdout
    os.dup2(devnull, 2)  # stderr
    sys.stdout = open(os.devnull, "w")
    sys.stderr = open(os.devnull, "w")


def debug(msg):
    if DEBUG:
        print(f"[DEBUG] {msg}", file=sys.stderr)


gi.require_version("Gtk", "3.0")
try:
    gi.require_version("GtkLayerShell", "0.1")
    from gi.repository import GtkLayerShell  # noqa: E402

    LAYER_SHELL_AVAILABLE = True
except (ValueError, ImportError):
    LAYER_SHELL_AVAILABLE = False

from gi.repository import Gdk, GLib, Gtk  # noqa: E402

_scripts = os.environ.get("WAYBAR_SCRIPTS") or str(Path(__file__).resolve().parents[1])
_lib = str(Path(_scripts) / "lib")
if _lib not in sys.path:
    sys.path.insert(0, _lib)
from gtk_popup_helpers import (  # noqa: E402
    get_real_and_vpn_ip as _shared_get_real_and_vpn_ip,
    have_cmd as _shared_have_cmd,
)


def have_cmd(cmd):
    result = _shared_have_cmd(cmd)
    debug(f"Checking for command '{cmd}': {result}")
    return result


def get_real_and_vpn_ip():
    return _shared_get_real_and_vpn_ip(debug=debug)


def get_tailscale_status():
    if not have_cmd('tailscale'):
        debug('tailscale not installed')
        return {'active': False, 'ip': 'tailscale not installed', 'user': 'n/a', 'hostname': 'n/a'}
    try:
        out = subprocess.check_output("tailscale status --json", shell=True, text=True, timeout=2)
        debug(f"Tailscale status: {out}")
        js = json.loads(out)
        self = js.get('Self', {})
        ts_ips = self.get('TailscaleIPs', [])
        ipv4 = next((ip for ip in ts_ips if re.match(r"^\d+\.\d+\.\d+\.\d+$", ip)), 'n/a')
        ipv6 = next((ip for ip in ts_ips if ':' in ip), 'n/a')
        user_id = self.get('UserID', 'n/a')
        debug(f"Tailscale user_id: {user_id}")
        login_name = display_name = None
        user_dict = js.get('User', {})
        if user_id != 'n/a' and isinstance(user_dict, dict):
            profile = user_dict.get(str(user_id), {})
            login_name = profile.get('LoginName')
            display_name = profile.get('DisplayName')
            debug(f"Tailscale login_name: {login_name}, display_name: {display_name}")
        # Additional fields
        return {
            'active': self.get('Online', False),
            'ipv4': ipv4,
            'ipv6': ipv6,
            'user': str(user_id),
            'login_name': login_name or 'n/a',
            'display_name': display_name or 'n/a',
            'hostname': self.get('HostName', 'n/a'),
            'public_key': self.get('PublicKey', 'n/a'),
            'dns_name': self.get('DNSName', 'n/a'),
            'os': self.get('OS', 'n/a'),
            'allowed_ips': ', '.join(self.get('AllowedIPs', [])) or 'n/a',
            'addrs': ', '.join(self.get('Addrs', [])) if self.get('Addrs') else 'n/a',
            'relay': self.get('Relay', 'n/a'),
            'rx_bytes': self.get('RxBytes', 'n/a'),
            'tx_bytes': self.get('TxBytes', 'n/a'),
            'created': self.get('Created', 'n/a'),
            'key_expiry': self.get('KeyExpiry', 'n/a'),
            'exit_node': self.get('ExitNode', False),
            'exit_node_option': self.get('ExitNodeOption', False),
            'peer_api_url': ', '.join(self.get('PeerAPIURL', [])) if self.get('PeerAPIURL') else 'n/a',
            'health': '; '.join(js.get('Health', [])) or 'n/a',
            'magic_dns_suffix': js.get('MagicDNSSuffix', 'n/a'),
            'tailnet_name': js.get('CurrentTailnet', {}).get('Name', 'n/a'),
        }
    except Exception as e:
        debug(f"Error fetching Tailscale status: {e}")
        return {'active': False, 'ip': 'n/a', 'user': 'n/a', 'hostname': 'n/a'}

def get_netbird_status():
    if not have_cmd('netbird'):
        debug('netbird not installed')
        return {'active': False, 'peer_id': 'netbird not installed', 'hostname': 'n/a', 'ip': 'n/a', 'type': 'n/a'}
    try:
        # Try JSON output for richer info
        out = subprocess.check_output("netbird status --json", shell=True, text=True, timeout=2)
        debug(f"Netbird status JSON: {out}")
        import json as _json
        js = _json.loads(out)
        # Fallbacks for missing fields
        connected = js.get('Connected', False)
        peer_id = js.get('PeerID', 'n/a')
        hostname = js.get('HostName', 'n/a')
        ip = js.get('IP', 'n/a')
        conn_type = js.get('ConnectionType', 'n/a')
        return {'active': connected, 'peer_id': peer_id, 'hostname': hostname, 'ip': ip, 'type': conn_type}
    except Exception as e:
        debug(f"Error fetching Netbird status: {e}")
        return {'active': False, 'peer_id': 'n/a', 'hostname': 'n/a', 'ip': 'n/a', 'type': 'n/a'}

def get_nm_vpn_status():
    if not have_cmd('nmcli'):
        debug('nmcli not installed')
        return {'active': False, 'name': 'nmcli not installed'}
    try:
        out = subprocess.check_output("nmcli -t -f NAME,TYPE,DEVICE,STATE connection show --active", shell=True, text=True, timeout=2)
        debug(f"nmcli output: {out}")
        lines = out.strip().split('\n')
        for line in lines:
            parts = line.split(':')
            if len(parts) >= 4 and parts[1] == 'vpn' and parts[3] == 'activated':
                name = parts[0]
                device = parts[2]
                # Now get more details for this VPN connection
                details = {'active': True, 'name': name, 'device': device}
                try:
                    detail_out = subprocess.check_output(f"nmcli -s -g connection.type,vpn-type,vpn.data,vpn.user-name,ipv4.dns,ipv4.gateway,ipv4.addresses connection show '{name}'", shell=True, text=True, timeout=2)
                    detail_lines = detail_out.strip().split('\n')
                    # connection.type, vpn-type, vpn.data, vpn.user-name, ipv4.dns, ipv4.gateway, ipv4.addresses
                    if len(detail_lines) > 0:
                        details['type'] = detail_lines[0]
                    if len(detail_lines) > 1:
                        details['vpn_type'] = detail_lines[1]
                    if len(detail_lines) > 2:
                        # Try to extract gateway from vpn.data if not present
                        data = detail_lines[2]
                        m = re.search(r'gateway=([^;]+)', data)
                        if m:
                            details['gateway'] = m.group(1)
                    if len(detail_lines) > 3:
                        details['username'] = detail_lines[3]
                    if len(detail_lines) > 4:
                        details['dns'] = detail_lines[4]
                    if len(detail_lines) > 5:
                        details['ipv4_gateway'] = detail_lines[5]
                    if len(detail_lines) > 6:
                        details['ipv4_address'] = detail_lines[6]
                except Exception as e:
                    debug(f"Error fetching VPN connection details: {e}")
                return details
    except Exception as e:
        debug(f"Error fetching nmcli VPN status: {e}")
    return {'active': False, 'name': 'n/a'}

def get_zerotier_status():
    if not have_cmd('zerotier-cli'):
        debug('zerotier-cli not installed')
        return {
            'active': False,
            'status': 'zerotier-cli not installed',
            'net_id': 'n/a',
            'name': 'n/a',
            'assigned_ips': 'n/a',
            'net_status': 'n/a',
        }
    try:
        # Get basic info
        out = subprocess.check_output("zerotier-cli info", shell=True, text=True, timeout=2)
        debug(f"Zerotier info: {out}")
        parts = out.strip().split()
        # Example: 200 info <id> <public id> <online|offline> <port> <version>
        if len(parts) >= 5:
            status = parts[3]
            active = status == 'ONLINE' or status == 'online'
        else:
            status = 'n/a'
            active = False
        # Get network info (may be empty if not joined)
        try:
            net_out = subprocess.check_output("zerotier-cli -j listnetworks", shell=True, text=True, timeout=2)
            import json as _json
            nets = _json.loads(net_out)
            if nets and isinstance(nets, list) and len(nets) > 0:
                net = nets[0]
                net_id = net.get('id', 'n/a')
                name = net.get('name', 'n/a')
                assigned_ips = ', '.join(net.get('assignedAddresses', [])) or 'n/a'
                status_str = net.get('status', 'n/a')
            else:
                net_id = name = assigned_ips = status_str = 'n/a'
        except Exception as e:
            debug(f"Zerotier network error: {e}")
            net_id = name = assigned_ips = status_str = 'n/a'
        return {
            'active': active,
            'status': status,
            'net_id': net_id,
            'name': name,
            'assigned_ips': assigned_ips,
            'net_status': status_str,
        }
    except Exception as e:
        debug(f"Error fetching Zerotier status: {e}")
        return {
            'active': False,
            'status': 'n/a',
            'net_id': 'n/a',
            'name': 'n/a',
            'assigned_ips': 'n/a',
            'net_status': 'n/a',
        }
def set_layer_shell_anchor(win):
    if not LAYER_SHELL_AVAILABLE:
        return
    if getattr(win, '_layer_shell_anchor_set', False):
        return
    GtkLayerShell.init_for_window(win)
    # Always anchor top-right with fixed margin
    for edge in [GtkLayerShell.Edge.TOP, GtkLayerShell.Edge.BOTTOM, GtkLayerShell.Edge.LEFT, GtkLayerShell.Edge.RIGHT]:
        GtkLayerShell.set_anchor(win, edge, False)
    GtkLayerShell.set_anchor(win, GtkLayerShell.Edge.TOP, True)
    GtkLayerShell.set_anchor(win, GtkLayerShell.Edge.RIGHT, True)
    margin_top = 20
    margin_right = 20
    GtkLayerShell.set_margin(win, GtkLayerShell.Edge.TOP, margin_top)
    GtkLayerShell.set_margin(win, GtkLayerShell.Edge.RIGHT, margin_right)
    GtkLayerShell.set_keyboard_mode(win, GtkLayerShell.KeyboardMode.ON_DEMAND)
    win._layer_shell_anchor_set = True

def build_status_ui():
    win = Gtk.Window(title="Network Privacy Status")
    win.set_border_width(18)
    win.set_resizable(False)
    win.set_type_hint(Gdk.WindowTypeHint.DIALOG)
    win.set_keep_above(True)
    win.set_decorated(False)
    if LAYER_SHELL_AVAILABLE:
        set_layer_shell_anchor(win)
    vbox = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=14)
    win.add(vbox)
    # Header
    header = Gtk.Label()
    header.set_markup("<span size='x-large'><b>🔒 Network Privacy Status</b></span>")
    header.set_xalign(0)
    vbox.pack_start(header, False, False, 0)

    # Gather all status info in parallel for speed
    with concurrent.futures.ThreadPoolExecutor() as executor:
        f_ts = executor.submit(get_tailscale_status)
        f_nb = executor.submit(get_netbird_status)
        f_vpn = executor.submit(get_nm_vpn_status)
        f_realvpn = executor.submit(get_real_and_vpn_ip)
        f_zt = executor.submit(get_zerotier_status)
        ts = f_ts.result()
        nb = f_nb.result()
        vpn = f_vpn.result()
        real_ip, vpn_ip = f_realvpn.result()
        zt = f_zt.result()


    # Sensitive info toggle and label registry (must be defined before any use)
    sensitive_labels = []
    sensitive_shown = {'value': False}
    def mask(val):
        if val == 'n/a':
            return 'n/a'
        return val if sensitive_shown['value'] else '••••••••'

    # Tailscale section
    ts_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2)
    ts_lbl = Gtk.Label()
    ts_icon = "󰖟" if ts['active'] else "󰖝"
    ts_status = "<span foreground='#44ff44'>Active</span>" if ts['active'] else "<span foreground='#ff2a7f'>Inactive</span>"
    ts_lbl.set_markup(f"{ts_icon} <b><span foreground='#00bfff'>Tailscale:</span></b> {ts_status}")
    ts_lbl.set_xalign(0)
    ts_box.pack_start(ts_lbl, False, False, 0)
    ts_detail_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=0)
    # IPv4/IPv6
    ts_detail_ipv4 = Gtk.Label()
    ts_detail_ipv4._raw = ts['ipv4']
    ts_detail_ipv4.set_markup(f"<span foreground='#b0b8c1'><b>IPv4:</b></span> <span foreground='#00bfff'>{mask(ts['ipv4'])}</span>")
    ts_detail_ipv4.set_xalign(0)
    sensitive_labels.append((ts_detail_ipv4, '<b>IPv4:</b> <span foreground="#00e5ff">{}</span>'))
    ts_detail_ipv6 = Gtk.Label()
    ts_detail_ipv6._raw = ts['ipv6']
    ts_detail_ipv6.set_markup(f"<span foreground='#b0b8c1'><b>IPv6:</b></span> <span foreground='#00bfff'>{mask(ts['ipv6'])}</span>")
    ts_detail_ipv6.set_xalign(0)
    sensitive_labels.append((ts_detail_ipv6, '<b>IPv6:</b> <span foreground="#00e5ff">{}</span>'))
    # User ID
    ts_detail_userid = Gtk.Label()
    ts_detail_userid.set_markup(f"<span foreground='#b0b8c1'><b>User ID:</b></span> <span foreground='#00bfff'>{mask(ts['user'])}</span>")
    ts_detail_userid.set_xalign(0)
    ts_detail_userid._raw = ts['user']
    sensitive_labels.append((ts_detail_userid, '<b>User ID:</b> {}'))
    # Login Name
    ts_detail_login = Gtk.Label()
    ts_detail_login.set_markup(f"<span foreground='#b0b8c1'><b>Login Name:</b></span> <span foreground='#00bfff'>{mask(ts['login_name'])}</span>")
    ts_detail_login.set_xalign(0)
    ts_detail_login._raw = ts['login_name']
    sensitive_labels.append((ts_detail_login, '<b>Login Name:</b> {}'))
    # Display Name
    ts_detail_display = Gtk.Label()
    ts_detail_display.set_markup(f"<span foreground='#b0b8c1'><b>Display Name:</b></span> <span foreground='#00bfff'>{mask(ts['display_name'])}</span>")
    ts_detail_display.set_xalign(0)
    ts_detail_display._raw = ts['display_name']
    sensitive_labels.append((ts_detail_display, '<b>Display Name:</b> {}'))
    # Hostname
    ts_detail_host = Gtk.Label()
    ts_detail_host.set_markup(f"<span foreground='#b0b8c1'><b>Host:</b></span> <span foreground='#00bfff'>{ts['hostname']}</span>")
    ts_detail_host.set_xalign(0)
    # Public Key (sensitive)
    ts_detail_pubkey = Gtk.Label()
    ts_detail_pubkey._raw = ts['public_key']
    ts_detail_pubkey.set_markup(f"<span foreground='#b0b8c1'><b>Public Key:</b></span> <span foreground='#00bfff'>{mask(ts_detail_pubkey._raw) if ts_detail_pubkey._raw != 'n/a' else 'n/a'}</span>")
    ts_detail_pubkey.set_xalign(0)
    ts_detail_pubkey.set_visible(False)
    sensitive_labels.append((ts_detail_pubkey, '<b>Public Key:</b> <span foreground="#00e5ff">{}</span>'))
    # DNS Name (sensitive)
    ts_detail_dnsname = Gtk.Label()
    ts_detail_dnsname._raw = ts['dns_name']
    ts_detail_dnsname.set_markup(f"<span foreground='#b0b8c1'><b>DNS Name:</b></span> <span foreground='#00bfff'>{mask(ts_detail_dnsname._raw) if ts_detail_dnsname._raw != 'n/a' else 'n/a'}</span>")
    ts_detail_dnsname.set_xalign(0)
    ts_detail_dnsname.set_visible(False)
    sensitive_labels.append((ts_detail_dnsname, '<b>DNS Name:</b> <span foreground="#00e5ff">{}</span>'))
    # OS
    ts_detail_os = Gtk.Label()
    ts_detail_os.set_markup(f"<span foreground='#b0b8c1'><b>OS:</b></span> <span foreground='#00bfff'>{ts['os']}</span>")
    ts_detail_os.set_xalign(0)
    ts_detail_os.set_visible(False)
    # Allowed IPs (sensitive)
    ts_detail_allowed = Gtk.Label()
    ts_detail_allowed._raw = ts['allowed_ips']
    ts_detail_allowed.set_markup(f"<span foreground='#b0b8c1'><b>Allowed IPs:</b></span> <span foreground='#00bfff'>{mask(ts_detail_allowed._raw) if ts_detail_allowed._raw != 'n/a' else 'n/a'}</span>")
    ts_detail_allowed.set_xalign(0)
    ts_detail_allowed.set_visible(False)
    sensitive_labels.append((ts_detail_allowed, '<b>Allowed IPs:</b> <span foreground="#00e5ff">{}</span>'))
    # Relay
    ts_detail_relay = Gtk.Label()
    ts_detail_relay.set_markup(f"<span foreground='#b0b8c1'><b>Relay:</b></span> <span foreground='#00bfff'>{ts['relay']}</span>")
    ts_detail_relay.set_xalign(0)
    ts_detail_relay.set_visible(False)
    # RxBytes/TxBytes
    ts_detail_rx = Gtk.Label()
    ts_detail_rx.set_markup(f"<span foreground='#b0b8c1'><b>RxBytes:</b></span> <span foreground='#00bfff'>{ts['rx_bytes']}</span>")
    ts_detail_rx.set_xalign(0)
    ts_detail_rx.set_visible(False)
    ts_detail_tx = Gtk.Label()
    ts_detail_tx.set_markup(f"<span foreground='#b0b8c1'><b>TxBytes:</b></span> <span foreground='#00bfff'>{ts['tx_bytes']}</span>")
    ts_detail_tx.set_xalign(0)
    ts_detail_tx.set_visible(False)
    # Created
    ts_detail_created = Gtk.Label()
    ts_detail_created.set_markup(f"<span foreground='#b0b8c1'><b>Created:</b></span> <span foreground='#00bfff'>{ts['created']}</span>")
    ts_detail_created.set_xalign(0)
    ts_detail_created.set_visible(False)
    # Key Expiry
    ts_detail_keyexpiry = Gtk.Label()
    ts_detail_keyexpiry.set_markup(f"<span foreground='#b0b8c1'><b>Key Expiry:</b></span> <span foreground='#00bfff'>{ts['key_expiry']}</span>")
    ts_detail_keyexpiry.set_xalign(0)
    ts_detail_keyexpiry.set_visible(False)
    # Exit Node/Option
    ts_detail_exit = Gtk.Label()
    ts_detail_exit.set_markup(f"<span foreground='#b0b8c1'><b>Exit Node:</b></span> <span foreground='#00bfff'>{ts['exit_node']}</span>")
    ts_detail_exit.set_xalign(0)
    ts_detail_exit.set_visible(False)
    ts_detail_exitopt = Gtk.Label()
    ts_detail_exitopt.set_markup(f"<span foreground='#b0b8c1'><b>Exit Node Option:</b></span> <span foreground='#00bfff'>{ts['exit_node_option']}</span>")
    ts_detail_exitopt.set_xalign(0)
    ts_detail_exitopt.set_visible(False)
    # Peer API URL (sensitive)
    ts_detail_peerapi = Gtk.Label()
    ts_detail_peerapi._raw = ts['peer_api_url']
    ts_detail_peerapi.set_markup(f"<span foreground='#b0b8c1'><b>Peer API URL:</b></span> <span foreground='#00bfff'>{mask(ts_detail_peerapi._raw) if ts_detail_peerapi._raw != 'n/a' else 'n/a'}</span>")
    ts_detail_peerapi.set_xalign(0)
    ts_detail_peerapi.set_visible(False)
    sensitive_labels.append((ts_detail_peerapi, '<b>Peer API URL:</b> <span foreground="#00e5ff">{}</span>'))
    # Health
    ts_detail_health = Gtk.Label()
    ts_detail_health.set_markup(f"<span foreground='#b0b8c1'><b>Health:</b></span> <span foreground='#00bfff'>{ts['health']}</span>")
    ts_detail_health.set_xalign(0)
    ts_detail_health.set_visible(False)
    # Magic DNS Suffix
    ts_detail_mdns = Gtk.Label()
    ts_detail_mdns.set_markup(f"<span foreground='#b0b8c1'><b>MagicDNS Suffix:</b></span> <span foreground='#00bfff'>{ts['magic_dns_suffix']}</span>")
    ts_detail_mdns.set_xalign(0)
    ts_detail_mdns.set_visible(False)
    # Tailnet Name
    ts_detail_tailnet = Gtk.Label()
    ts_detail_tailnet.set_markup(f"<span foreground='#b0b8c1'><b>Tailnet Name:</b></span> <span foreground='#00bfff'>{ts['tailnet_name']}</span>")
    ts_detail_tailnet.set_xalign(0)
    ts_detail_tailnet.set_visible(False)
    # Add all to the box
    for w in [ts_detail_ipv4, ts_detail_ipv6, ts_detail_userid, ts_detail_login, ts_detail_display, ts_detail_host, ts_detail_pubkey, ts_detail_dnsname, ts_detail_os, ts_detail_allowed, ts_detail_relay, ts_detail_rx, ts_detail_tx, ts_detail_created, ts_detail_keyexpiry, ts_detail_exit, ts_detail_exitopt, ts_detail_peerapi, ts_detail_health, ts_detail_mdns, ts_detail_tailnet]:
        w.set_visible(False)
        ts_detail_box.pack_start(w, False, False, 0)
    ts_box.pack_start(ts_detail_box, False, False, 0)
    vbox.pack_start(ts_box, False, False, 0)

    # Netbird section
    nb_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2)
    nb_lbl = Gtk.Label()
    nb_icon = "󰒍" if nb['active'] else "󰒎"
    nb_status = "<span foreground='#44ff44'>Active</span>" if nb['active'] else "<span foreground='#ff2a7f'>Inactive</span>"
    nb_lbl.set_markup(f"{nb_icon} <b><span foreground='#00bfff'>Netbird:</span></b> {nb_status}")
    nb_lbl.set_xalign(0)
    nb_box.pack_start(nb_lbl, False, False, 0)
    nb_detail_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=0)
    # Peer ID (sensitive)
    nb_detail_peer = Gtk.Label()
    nb_detail_peer._raw = nb['peer_id']
    nb_detail_peer.set_markup(f"<span foreground='#b0b8c1'><b>Peer ID:</b></span> <span foreground='#00bfff'>{mask(nb_detail_peer._raw) if nb_detail_peer._raw != 'n/a' else 'n/a'}</span>")
    nb_detail_peer.set_xalign(0)
    nb_detail_peer.set_visible(False)
    sensitive_labels.append((nb_detail_peer, '<b>Peer ID:</b> <span foreground="#00e5ff">{}</span>'))
    # Hostname
    nb_detail_host = Gtk.Label()
    nb_detail_host.set_markup(f"<span foreground='#b0b8c1'><b>Host:</b></span> <span foreground='#00bfff'>{nb['hostname']}</span>")
    nb_detail_host.set_xalign(0)
    nb_detail_host.set_visible(False)
    # Netbird IP (sensitive)
    nb_detail_ip = Gtk.Label()
    nb_detail_ip._raw = nb['ip']
    nb_detail_ip.set_markup(f"<span foreground='#b0b8c1'><b>Netbird IP:</b></span> <span foreground='#00bfff'>{mask(nb_detail_ip._raw) if nb_detail_ip._raw != 'n/a' else 'n/a'}</span>")
    nb_detail_ip.set_xalign(0)
    nb_detail_ip.set_visible(False)
    sensitive_labels.append((nb_detail_ip, '<b>Netbird IP:</b> <span foreground="#00e5ff">{}</span>'))
    # Connection type
    nb_detail_type = Gtk.Label()
    nb_detail_type.set_markup(f"<span foreground='#b0b8c1'><b>Type:</b></span> <span foreground='#00bfff'>{nb['type']}</span>")
    nb_detail_type.set_xalign(0)
    nb_detail_type.set_visible(False)
    # Add all details to the box (for More Details view)
    for w in [nb_detail_peer, nb_detail_host, nb_detail_ip, nb_detail_type]:
        nb_detail_box.pack_start(w, False, False, 0)
    nb_box.pack_start(nb_detail_box, False, False, 0)
    vbox.pack_start(nb_box, False, False, 0)

    # Zerotier section (moved above VPN)
    zt_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2)
    zt_lbl = Gtk.Label()
    zt_icon = "󰖂" if zt['active'] else "󰖃"
    zt_status = "<span foreground='#44ff44'>Active</span>" if zt['active'] else "<span foreground='#ff2a7f'>Inactive</span>"
    zt_lbl.set_markup(f"{zt_icon} <b><span foreground='#00bfff'>Zerotier:</span></b> {zt_status}")
    zt_lbl.set_xalign(0)
    zt_box.pack_start(zt_lbl, False, False, 0)
    # Zerotier details (only in expanded view)
    zt_detail_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=0)
    # Network ID (sensitive)
    zt_detail_netid = Gtk.Label()
    zt_detail_netid._raw = zt['net_id']
    zt_detail_netid.set_markup(f"<span foreground='#b0b8c1'><b>Network ID:</b></span> <span foreground='#00bfff'>{mask(zt_detail_netid._raw) if zt_detail_netid._raw != 'n/a' else 'n/a'}</span>")
    zt_detail_netid.set_xalign(0)
    zt_detail_netid.set_visible(False)
    sensitive_labels.append((zt_detail_netid, '<b>Network ID:</b> <span foreground="#00e5ff">{}</span>'))
    # Name
    zt_detail_name = Gtk.Label()
    zt_detail_name.set_markup(f"<span foreground='#b0b8c1'><b>Name:</b></span> <span foreground='#00bfff'>{zt['name']}</span>")
    zt_detail_name.set_xalign(0)
    zt_detail_name.set_visible(False)
    # Assigned IPs (sensitive)
    zt_detail_ips = Gtk.Label()
    zt_detail_ips._raw = zt['assigned_ips']
    zt_detail_ips.set_markup(f"<span foreground='#b0b8c1'><b>Assigned IPs:</b></span> <span foreground='#00bfff'>{mask(zt_detail_ips._raw) if zt_detail_ips._raw != 'n/a' else 'n/a'}</span>")
    zt_detail_ips.set_xalign(0)
    zt_detail_ips.set_visible(False)
    sensitive_labels.append((zt_detail_ips, '<b>Assigned IPs:</b> <span foreground="#00e5ff">{}</span>'))
    # Network status
    zt_detail_status = Gtk.Label()
    zt_detail_status.set_markup(f"<span foreground='#b0b8c1'><b>Network Status:</b></span> <span foreground='#00bfff'>{zt['net_status']}</span>")
    zt_detail_status.set_xalign(0)
    zt_detail_status.set_visible(False)
    # Add all details to the box (for More Details view only)
    for w in [zt_detail_netid, zt_detail_name, zt_detail_ips, zt_detail_status]:
        zt_detail_box.pack_start(w, False, False, 0)
    zt_box.pack_start(zt_detail_box, False, False, 0)
    vbox.pack_start(zt_box, False, False, 0)

    # VPN section
    vpn_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2)
    vpn_lbl = Gtk.Label()
    vpn_icon = "󰌾" if vpn['active'] else "󰌿"
    vpn_status = "<span foreground='#44ff44'>Active</span>" if vpn['active'] else "<span foreground='#ff2a7f'>Inactive</span>"
    vpn_lbl.set_markup(f"{vpn_icon} <b><span foreground='#00bfff'>VPN:</span></b> {vpn_status}")
    vpn_lbl.set_xalign(0)
    vpn_box.pack_start(vpn_lbl, False, False, 0)
    vpn_detail_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=0)
    # Only show VPN name in short view if active
    vpn_detail_name = Gtk.Label()
    vpn_detail_name.set_markup(f"<span foreground='#b0b8c1'><b>Name:</b></span> <span foreground='#00bfff'>{vpn.get('name','n/a')}</span>")
    vpn_detail_name.set_xalign(0)
    vpn_detail_name.set_visible(False)
    # All other details only in More Details view
    vpn_detail_type = Gtk.Label()
    vpn_detail_type.set_markup(f"<span foreground='#b0b8c1'><b>Type:</b></span> <span foreground='#00bfff'>{vpn.get('vpn_type','n/a')}</span>")
    vpn_detail_type.set_xalign(0)
    vpn_detail_type.set_visible(False)
    vpn_detail_gateway = Gtk.Label()
    vpn_detail_gateway._raw = vpn.get('gateway','n/a')
    vpn_detail_gateway.set_markup(f"<span foreground='#b0b8c1'><b>Gateway:</b></span> <span foreground='#00bfff'>{mask(vpn_detail_gateway._raw) if vpn_detail_gateway._raw != 'n/a' else 'n/a'}</span>")
    vpn_detail_gateway.set_xalign(0)
    vpn_detail_gateway.set_visible(False)
    sensitive_labels.append((vpn_detail_gateway, "<b>Gateway:</b> <span foreground='#00e5ff'>{}</span>"))
    vpn_detail_device = Gtk.Label()
    vpn_detail_device.set_markup(f"<span foreground='#b0b8c1'><b>Device:</b></span> <span foreground='#00bfff'>{vpn.get('device','n/a')}</span>")
    vpn_detail_device.set_xalign(0)
    vpn_detail_device.set_visible(False)
    vpn_detail_user = Gtk.Label()
    vpn_detail_user._raw = vpn.get('username','n/a')
    vpn_detail_user.set_markup(f"<span foreground='#b0b8c1'><b>Username:</b></span> <span foreground='#00bfff'>{mask(vpn_detail_user._raw) if vpn_detail_user._raw != 'n/a' else 'n/a'}</span>")
    vpn_detail_user.set_xalign(0)
    vpn_detail_user.set_visible(False)
    sensitive_labels.append((vpn_detail_user, "<b>Username:</b> <span foreground='#00e5ff'>{}</span>"))
    vpn_detail_dns = Gtk.Label()
    vpn_detail_dns._raw = vpn.get('dns','n/a')
    vpn_detail_dns.set_markup(f"<span foreground='#b0b8c1'><b>DNS:</b></span> <span foreground='#00bfff'>{mask(vpn_detail_dns._raw) if vpn_detail_dns._raw != 'n/a' else 'n/a'}</span>")
    vpn_detail_dns.set_xalign(0)
    vpn_detail_dns.set_visible(False)
    sensitive_labels.append((vpn_detail_dns, "<b>DNS:</b> <span foreground='#00e5ff'>{}</span>"))
    vpn_detail_vpnip = Gtk.Label()
    vpn_detail_vpnip._raw = vpn_ip if vpn['active'] and vpn_ip != 'n/a' else 'n/a'
    vpn_detail_vpnip.set_markup(f"<span foreground='#b0b8c1'><b>VPN IP:</b></span> <span foreground='#00bfff'>{mask(vpn_detail_vpnip._raw) if vpn_detail_vpnip._raw != 'n/a' else 'n/a'}</span>")
    vpn_detail_vpnip.set_xalign(0)
    vpn_detail_vpnip.set_visible(False)
    sensitive_labels.append((vpn_detail_vpnip, "<b>VPN IP:</b> <span foreground='#00e5ff'>{}</span>"))
    vpn_detail_pubip = Gtk.Label()
    vpn_detail_pubip._raw = real_ip if real_ip != 'n/a' else 'n/a'
    vpn_detail_pubip.set_markup(f"<span foreground='#b0b8c1'><b>Public IP:</b></span> <span foreground='#00bfff'>{mask(vpn_detail_pubip._raw) if vpn_detail_pubip._raw != 'n/a' else 'n/a'}</span>")
    vpn_detail_pubip.set_xalign(0)
    vpn_detail_pubip.set_visible(False)
    sensitive_labels.append((vpn_detail_pubip, "<b>Public IP:</b> <span foreground='#00e5ff'>{}</span>"))
    # Only show VPN name in short view if active
    vpn_box.pack_start(vpn_detail_name, False, False, 0)
    # Add all details to the box (for More Details view)
    for w in [vpn_detail_type, vpn_detail_gateway, vpn_detail_device, vpn_detail_user, vpn_detail_dns, vpn_detail_vpnip, vpn_detail_pubip]:
        vpn_detail_box.pack_start(w, False, False, 0)
    vpn_box.pack_start(vpn_detail_box, False, False, 0)
    vbox.pack_start(vpn_box, False, False, 0)

    # Keybind hint
    hint = Gtk.Label()
    hint.set_markup("<span foreground='#8aa2c5'>[Esc] Close | [M] More Details</span>")
    hint.set_xalign(0)
    vbox.pack_start(hint, False, False, 0)
    hint.set_markup("<span foreground='#8aa2c5'>[Esc] Close | [M] More Details | [S] Show/Hide Sensitive</span>")

    # Keyboard toggle for details (start hidden, show on M)
    details_shown = {'value': False}
    # Ensure details are hidden by default (less detailed mode)
    sensitive_shown = {'value': False}
    def update_sensitive_labels():
        for label, fmt in sensitive_labels:
            val = mask(label._raw)
            label.set_markup(fmt.format(val))

    def set_details_visible(visible):
        # Tailscale details (all details only in More Details view)
        for w in [ts_detail_ipv4, ts_detail_ipv6, ts_detail_userid, ts_detail_login, ts_detail_display, ts_detail_host, ts_detail_pubkey, ts_detail_dnsname, ts_detail_os, ts_detail_allowed, ts_detail_relay, ts_detail_rx, ts_detail_tx, ts_detail_created, ts_detail_keyexpiry, ts_detail_exit, ts_detail_exitopt, ts_detail_peerapi, ts_detail_health, ts_detail_mdns, ts_detail_tailnet]:
            w.set_visible(visible)
        # Netbird details
        for w in [nb_detail_peer, nb_detail_host, nb_detail_ip, nb_detail_type]:
            w.set_visible(visible)
        # Zerotier details (only in More Details view)
        for w in [zt_detail_netid, zt_detail_name, zt_detail_ips, zt_detail_status]:
            w.set_visible(visible)
        # VPN: only show name in short view, all details in More Details
        vpn_detail_name.set_visible(vpn['active'])
        for w in [vpn_detail_type, vpn_detail_gateway, vpn_detail_device, vpn_detail_user, vpn_detail_dns, vpn_detail_vpnip, vpn_detail_pubip]:
            w.set_visible(visible)
        # When showing details, update sensitive info display
        if visible:
            update_sensitive_labels()
        # Re-center window after resize to keep it on screen, using idle_add to ensure window is mapped
        GLib.idle_add(lambda: reposition(win))
    # Always start in less detailed mode
    set_details_visible(False)
    details_shown = {'value': False}
    def toggle_details():
        details_shown['value'] = not details_shown['value']
        set_details_visible(details_shown['value'])
        # Reposition after toggling details
        GLib.idle_add(lambda: reposition(win))
    def toggle_sensitive():
        sensitive_shown['value'] = not sensitive_shown['value']
        # Only update if details are visible
        if details_shown['value']:
            update_sensitive_labels()

    def on_key(win, event):
        key = Gdk.keyval_name(event.keyval)
        if key in ('Escape', 'q'):
            Gtk.main_quit()
        elif key in ('m', 'M'):
            toggle_details()
        elif key in ('s', 'S'):
            toggle_sensitive()
    win.connect("key-press-event", on_key)
    win.connect("delete-event", lambda *a: Gtk.main_quit())
    _last_pointer = [0, 0]
    def reposition(*args):
        if LAYER_SHELL_AVAILABLE:
            set_layer_shell_anchor(win)
            return
        display = Gdk.Display.get_default()
        seat = display.get_default_seat()
        pointer = seat.get_pointer()
        _, x, y = pointer.get_position()
        _last_pointer[0], _last_pointer[1] = x, y
        monitor = display.get_monitor_at_point(x, y)
        geo = monitor.get_geometry()
        alloc = win.get_allocation()
        win_width = alloc.width or 400
        win_height = alloc.height or 200
        px = min(max(geo.x, x - win_width // 2), geo.x + geo.width - win_width)
        py = min(max(geo.y, y + 10), geo.y + geo.height - win_height)
        win.move(px, py)
    win.connect("map-event", reposition)
    win.connect("size-allocate", reposition)
    win.show_all()
    # After showing, ensure details are hidden if needed
    set_details_visible(details_shown['value'])
    # Robustly position window below mouse after initial show
    GLib.idle_add(lambda: reposition(win))
    return win

def main():
    build_status_ui()
    Gtk.main()

if __name__ == "__main__":
    main()
