#!/usr/bin/env python3
"""KDE Plasma active-window / notifications / clipboard session listener."""
import json
import os
import signal
import subprocess
import sys
import threading

_LIB = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "lib")
if _LIB not in sys.path:
    sys.path.insert(0, _LIB)

import gi  # noqa: E402

gi.require_version("Gio", "2.0")
gi.require_version("GLib", "2.0")
from gi.repository import Gio, GLib  # noqa: E402

from kde_listener.active_window import ActiveWindowMixin  # noqa: E402
from kde_listener.clipboard import ClipboardMixin  # noqa: E402
from kde_listener.compositor import detect_compositor  # noqa: E402
from kde_listener.lock import acquire_lock  # noqa: E402
from kde_listener.notifications import NotificationsMixin  # noqa: E402
from kde_listener.refreshers import RefreshersMixin  # noqa: E402


class ActiveWindowServer(
    ActiveWindowMixin,
    ClipboardMixin,
    NotificationsMixin,
    RefreshersMixin,
):
    def __init__(self):
        self.script_id = None
        self.cache_dir = os.path.join(os.environ.get("XDG_CACHE_HOME", os.path.expanduser("~/.cache")), "waybar")
        self.cache_file = os.path.join(self.cache_dir, "active-window.json")
        os.makedirs(self.cache_dir, exist_ok=True)

        self.count_file = os.path.join(self.cache_dir, "kde-unread-count.txt")
        self.status_cache = os.path.join(self.cache_dir, "notifications-status.json")
        self.history_cache = os.path.join(self.cache_dir, "kde-notifications-history.json")
        self.clipboard_cache = os.path.join(self.cache_dir, "clipboard-status.json")

        self.kdeconnect_refreshing = False
        self.kdeconnect_pending = False
        self.kdeconnect_lock = threading.Lock()

        self.upower_refreshing = False
        self.upower_pending = False
        self.upower_lock = threading.Lock()

        self.network_refreshing = False
        self.network_pending = False
        self.network_lock = threading.Lock()
        self.network_timeout_id = 0

        self.pending_title = None
        self.pending_app = None
        self.pending_output = ""
        self.active_window_timeout_id = 0
        self.windows_changed_timeout_id = 0

        # Notifications monitoring state
        self.notif_method = None
        self.notif_serial = None
        self.notif_args = []
        self.notif_in_string = False
        self.notif_current_string = ""
        self.notifications = []
        self.notif_pending = {}

        # Load notification history on startup
        if os.path.exists(self.history_cache):
            try:
                with open(self.history_cache, "r") as f:
                    self.notifications = json.load(f)
                if not isinstance(self.notifications, list):
                    self.notifications = []
            except Exception as e:
                print(f"Error loading history: {e}", file=sys.stderr)

        self.unread_count = 0
        if os.path.exists(self.count_file):
            try:
                with open(self.count_file, "r") as f:
                    self.unread_count = int(f.read().strip())
            except Exception:
                pass

        self.owner_id = Gio.bus_own_name(
            Gio.BusType.SESSION,
            "org.waybar.activewindow",
            Gio.BusNameOwnerFlags.NONE,
            self.on_bus_acquired,
            self.on_name_acquired,
            self.on_name_lost
        )

        self.session_bus = Gio.bus_get_sync(Gio.BusType.SESSION, None)

        self.session_bus.signal_subscribe(
            None,
            "org.kde.klipper.klipper",
            "clipboardHistoryUpdated",
            "/klipper",
            None,
            Gio.DBusSignalFlags.NONE,
            self.on_clipboard_changed,
            None
        )

        self.session_bus.signal_subscribe(
            None,
            "org.kde.KeyboardLayouts",
            "layoutChanged",
            "/Layouts",
            None,
            Gio.DBusSignalFlags.NONE,
            self.on_keyboard_layout_changed,
            None
        )

        self.session_bus.signal_subscribe(
            None,
            "org.freedesktop.DBus.Properties",
            "PropertiesChanged",
            "/org/kde/KWin/NightLight",
            None,
            Gio.DBusSignalFlags.NONE,
            self.on_nightlight_changed,
            None
        )

        self.session_bus.signal_subscribe(
            None,
            "org.kde.Solid.PowerManagement.Actions.BrightnessControl",
            "brightnessChanged",
            "/org/kde/Solid/PowerManagement/Actions/BrightnessControl",
            None,
            Gio.DBusSignalFlags.NONE,
            self.on_brightness_changed,
            None
        )

        self.session_bus.signal_subscribe(
            "org.kde.kdeconnect",
            None,
            None,
            None,
            None,
            Gio.DBusSignalFlags.NONE,
            self.on_kdeconnect_changed,
            None
        )

        self.session_bus.signal_subscribe(
            "org.kde.KWin",
            "org.kde.KWin.VirtualDesktopManager",
            None,
            "/VirtualDesktopManager",
            None,
            Gio.DBusSignalFlags.NONE,
            self.on_virtual_desktops_changed,
            None
        )

        self.system_bus = Gio.bus_get_sync(Gio.BusType.SYSTEM, None)

        self.system_bus.signal_subscribe(
            "org.freedesktop.NetworkManager",
            "org.freedesktop.NetworkManager",
            "StateChanged",
            "/org/freedesktop/NetworkManager",
            None,
            Gio.DBusSignalFlags.NONE,
            self.on_network_changed,
            None
        )

        self.system_bus.signal_subscribe(
            "org.freedesktop.NetworkManager",
            "org.freedesktop.DBus.Properties",
            "PropertiesChanged",
            "/org/freedesktop/NetworkManager",
            None,
            Gio.DBusSignalFlags.NONE,
            self.on_network_changed,
            None
        )

        self.system_bus.signal_subscribe(
            "org.freedesktop.UPower",
            None,
            None,
            None,
            None,
            Gio.DBusSignalFlags.NONE,
            self.on_upower_changed,
            None
        )

        self.system_bus.signal_subscribe(
            "net.hadess.PowerProfiles",
            "org.freedesktop.DBus.Properties",
            "PropertiesChanged",
            "/net/hadess/PowerProfiles",
            None,
            Gio.DBusSignalFlags.NONE,
            self.on_powerprofiles_changed,
            None
        )

        # Start dbus-monitor subprocess in a thread to monitor notifications
        self.start_dbus_monitor()

        # Prime caches asynchronously/initially
        self.update_notifications_cache()
        threading.Thread(target=self.check_and_write_clipboard, daemon=True).start()

        # Signal handlers for notification control from external helper scripts
        GLib.unix_signal_add(GLib.PRIORITY_DEFAULT, signal.SIGUSR1, self.handle_sigusr1)
        GLib.unix_signal_add(GLib.PRIORITY_DEFAULT, signal.SIGUSR2, self.handle_sigusr2)

        self.loop = GLib.MainLoop()

    def cleanup(self):
        if self.script_id:
            subprocess.run([
                "qdbus6", "org.kde.KWin", f"/Scripting/Script{self.script_id}",
                "org.kde.kwin.Script.stop"
            ], capture_output=True)
        subprocess.run([
            "qdbus6", "org.kde.KWin", "/Scripting",
            "org.kde.kwin.Scripting.unloadScript", "active_window_watcher"
        ], capture_output=True)
        proc = getattr(self, "dbus_monitor_proc", None)
        if proc is not None:
            try:
                proc.terminate()
            except Exception:
                pass

    def run(self):
        try:
            self.loop.run()
        except KeyboardInterrupt:
            pass
        finally:
            self.cleanup()


if __name__ == "__main__":
    if detect_compositor() != "kde":
        sys.exit(0)
    acquire_lock("kde-activewindow")
    ActiveWindowServer().run()
