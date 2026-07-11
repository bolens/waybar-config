import os
import subprocess
import threading

import gi

gi.require_version("GLib", "2.0")
from gi.repository import GLib  # noqa: E402

from kde_listener.paths import waybar_scripts_dir  # noqa: E402
from kde_listener.signals import waybar_rtmin  # noqa: E402


class RefreshersMixin:
    def on_keyboard_layout_changed(self, conn, sender_name, object_path, interface_name, signal_name, parameters, user_data):
        waybar_rtmin("keyboard_layout")

    def on_nightlight_changed(self, conn, sender_name, object_path, interface_name, signal_name, parameters, user_data):
        cache_dir = os.path.join(os.environ.get("XDG_CACHE_HOME", os.path.expanduser("~/.cache")), "waybar")
        cache_file = os.path.join(cache_dir, "nightlight-status.json")
        try:
            if os.path.exists(cache_file):
                os.remove(cache_file)
        except OSError:
            pass
        waybar_rtmin("nightlight")

    def on_brightness_changed(self, conn, sender_name, object_path, interface_name, signal_name, parameters, user_data):
        brightness_script = os.path.join(waybar_scripts_dir(), "system", "brightness-status.sh")
        if os.path.exists(brightness_script):
            subprocess.run([brightness_script, "--refresh"], stderr=subprocess.DEVNULL)
            waybar_rtmin("brightness")

    # NetworkManager fires rapid bursts of StateChanged/PropertiesChanged signals
    # during interface state shifts. Debounce by 500ms to avoid launching concurrent
    # updates that cause write conflicts or trigger Broken Pipe failures in Waybar.
    def on_network_changed(self, conn, sender_name, object_path, interface_name, signal_name, parameters, user_data):
        if self.network_timeout_id != 0:
            GLib.source_remove(self.network_timeout_id)
        self.network_timeout_id = GLib.timeout_add(500, self.debounce_network_refresh)

    def debounce_network_refresh(self):
        self.network_timeout_id = 0
        with self.network_lock:
            if self.network_refreshing:
                self.network_pending = True
                return False
            self.network_refreshing = True
        self.trigger_network_refresh()
        return False

    # Executes refreshes asynchronously in a background thread to prevent blocking
    # the main GLib mainloop during slower network status (NM/VPN/Tailscale) requests.
    def trigger_network_refresh(self):
        vpn_script = os.path.join(waybar_scripts_dir(), "network", "vpn-status.sh")
        ts_script = os.path.join(waybar_scripts_dir(), "network", "tailscale-status.sh")

        def run_refresh():
            try:
                if os.path.exists(vpn_script):
                    subprocess.run([vpn_script, "--refresh"], stderr=subprocess.DEVNULL)
                    waybar_rtmin("vpn")
                if os.path.exists(ts_script):
                    subprocess.run([ts_script, "--refresh"], stderr=subprocess.DEVNULL)
                    waybar_rtmin("tailscale")
            finally:
                with self.network_lock:
                    self.network_refreshing = False
                    if self.network_pending:
                        self.network_pending = False
                        GLib.idle_add(self.trigger_network_refresh)

        threading.Thread(target=run_refresh, daemon=True).start()

    def on_kdeconnect_changed(self, conn, sender_name, object_path, interface_name, signal_name, parameters, user_data):
        with self.kdeconnect_lock:
            if self.kdeconnect_refreshing:
                self.kdeconnect_pending = True
                return
            self.kdeconnect_refreshing = True

        self.trigger_kdeconnect_refresh()

    def trigger_kdeconnect_refresh(self):
        kdeconnect_script = os.path.join(waybar_scripts_dir(), "services", "devices", "kdeconnect-status.sh")
        if not os.path.exists(kdeconnect_script):
            with self.kdeconnect_lock:
                self.kdeconnect_refreshing = False
            return

        def run_refresh():
            try:
                subprocess.run([kdeconnect_script, "--refresh"], stderr=subprocess.DEVNULL)
                waybar_rtmin("kdeconnect")
            finally:
                with self.kdeconnect_lock:
                    self.kdeconnect_refreshing = False
                    if self.kdeconnect_pending:
                        self.kdeconnect_pending = False
                        GLib.idle_add(self.trigger_kdeconnect_refresh)

        threading.Thread(target=run_refresh, daemon=True).start()

    def on_upower_changed(self, conn, sender_name, object_path, interface_name, signal_name, parameters, user_data):
        with self.upower_lock:
            if self.upower_refreshing:
                self.upower_pending = True
                return
            self.upower_refreshing = True

        self.trigger_upower_refresh()

    def trigger_upower_refresh(self):
        battery_script = os.path.join(waybar_scripts_dir(), "services", "devices", "device-battery-status.sh")
        if not os.path.exists(battery_script):
            with self.upower_lock:
                self.upower_refreshing = False
            return

        def run_refresh():
            try:
                subprocess.run([battery_script, "--refresh"], stderr=subprocess.DEVNULL)
                waybar_rtmin("device_battery")
            finally:
                with self.upower_lock:
                    self.upower_refreshing = False
                    if self.upower_pending:
                        self.upower_pending = False
                        GLib.idle_add(self.trigger_upower_refresh)

        threading.Thread(target=run_refresh, daemon=True).start()

    def on_powerprofiles_changed(self, conn, sender_name, object_path, interface_name, signal_name, parameters, user_data):
        waybar_rtmin("powerprofiles")
