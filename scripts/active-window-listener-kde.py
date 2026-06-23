#!/usr/bin/env python3
import gi
gi.require_version('Gio', '2.0')
gi.require_version('GLib', '2.0')
from gi.repository import Gio, GLib
import subprocess
import sys
import os
import json
import re
import atexit
import shutil
import threading
import signal
import time

# Single-instance locking
def acquire_lock(lock_name):
    runtime_dir = os.environ.get("XDG_RUNTIME_DIR", "/tmp")
    lock_dir = os.path.join(runtime_dir, f"waybar-dock-listener-{lock_name}.lock.d")
    lock_pid_file = os.path.join(lock_dir, "pid")
    
    try:
        os.makedirs(lock_dir, exist_ok=False)
    except FileExistsError:
        if os.path.exists(lock_pid_file):
            try:
                with open(lock_pid_file, "r") as f:
                    old_pid = int(f.read().strip())
                os.kill(old_pid, 0)
                sys.exit(0)
            except (ValueError, OSError):
                pass
        shutil.rmtree(lock_dir, ignore_errors=True)
        try:
            os.makedirs(lock_dir, exist_ok=False)
        except Exception:
            sys.exit(0)
            
    with open(lock_pid_file, "w") as f:
        f.write(str(os.getpid()))
        
    def cleanup_lock():
        try:
            os.remove(lock_pid_file)
            os.rmdir(lock_dir)
        except Exception:
            pass
            
    atexit.register(cleanup_lock)

XML = """
<node>
  <interface name="org.waybar.ActiveWindow">
    <method name="update">
      <arg direction="in" type="s" name="title"/>
      <arg direction="in" type="s" name="app"/>
    </method>
    <method name="windowsChanged"/>
    <method name="desktopsChanged">
      <arg direction="in" type="s" name="mapping_json"/>
    </method>
  </interface>
</node>
"""

def trim_title(s, max_len=70):
    s = s.replace('\n', ' ').replace('\t', ' ')
    s = re.sub(r'\s+', ' ', s).strip()
    
    s = re.sub(r'(.*) - Mozilla Firefox$', r'\1', s)
    s = re.sub(r'(.*) - Zen Browser$', r'\1', s)
    s = re.sub(r'(.*) - Google Chrome$', r'\1', s)
    s = re.sub(r'(.*) - Floorp$', r'\1', s)
    s = re.sub(r'(.*) - Chromium$', r'\1', s)
    s = re.sub(r'(.*) - Brave$', r'\1', s)
    s = re.sub(r'(.*) - Vivaldi$', r'\1', s)
    
    if len(s) <= max_len:
        return s
    else:
        return s[:max_len - 3] + "..."

def clean_title(s):
    s = s.replace('\n', ' ').replace('\t', ' ')
    s = re.sub(r'\s+', ' ', s).strip()
    
    s = re.sub(r'(.*) - Mozilla Firefox$', r'\1', s)
    s = re.sub(r'(.*) - Zen Browser$', r'\1', s)
    s = re.sub(r'(.*) - Google Chrome$', r'\1', s)
    s = re.sub(r'(.*) - Floorp$', r'\1', s)
    s = re.sub(r'(.*) - Chromium$', r'\1', s)
    s = re.sub(r'(.*) - Brave$', r'\1', s)
    s = re.sub(r'(.*) - Vivaldi$', r'\1', s)
    return s

class ActiveWindowServer:
    def __init__(self):
        self.script_id = None
        self.cache_dir = os.path.expanduser("~/.cache/waybar")
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

    def on_bus_acquired(self, conn, name):
        node = Gio.DBusNodeInfo.new_for_xml(XML)
        conn.register_object(
            "/ActiveWindow",
            node.interfaces[0],
            self.handle_method_call,
            None,
            None
        )

    def on_name_acquired(self, conn, name):
        self.script_id = self.load_kwin_script()

    def on_name_lost(self, conn, name):
        self.cleanup()
        sys.exit(1)

    def handle_method_call(self, conn, sender, path, interface, method, params, invocation):
        if method == "update":
            title, app = params.unpack()
            self.update_active_window(title, app)
            invocation.return_value(None)
        elif method == "windowsChanged":
            if self.windows_changed_timeout_id != 0:
                GLib.source_remove(self.windows_changed_timeout_id)
            self.windows_changed_timeout_id = GLib.timeout_add(250, self.flush_windows_changed)
            invocation.return_value(None)
        elif method == "desktopsChanged":
            mapping_json = params.unpack()[0]
            self.update_kde_desktops(mapping_json)
            invocation.return_value(None)

    def update_active_window(self, title, app):
        self.pending_title = title
        self.pending_app = app
        if self.active_window_timeout_id != 0:
            GLib.source_remove(self.active_window_timeout_id)
        self.active_window_timeout_id = GLib.timeout_add(150, self.flush_active_window_update)

    def flush_active_window_update(self):
        self.active_window_timeout_id = 0
        title = self.pending_title
        app = self.pending_app
        
        trimmed = trim_title(title)
        if not title:
            data = {
                "text": "󰇄  Desktop",
                "tooltip": "No active window",
                "class": "desktop"
            }
        else:
            data = {
                "text": f"󰖲  {trimmed}",
                "tooltip": title,
                "class": "active"
            }
        
        tmp_file = self.cache_file + ".tmp"
        with open(tmp_file, "w") as f:
            json.dump(data, f)
        os.replace(tmp_file, self.cache_file)

        # Write raw title to active-window-title.raw for scrolling module
        raw_title_file = os.path.join(self.cache_dir, "active-window-title.raw")
        cleaned_title = clean_title(title) if title else ""
        try:
            with open(raw_title_file + ".tmp", "w") as f:
                f.write(cleaned_title)
            os.replace(raw_title_file + ".tmp", raw_title_file)
        except Exception:
            pass
        
        subprocess.run(["pkill", "-x", "-RTMIN+13", "waybar"], capture_output=True)
        return False

    def flush_windows_changed(self):
        self.windows_changed_timeout_id = 0
        script_dir = os.path.dirname(os.path.abspath(__file__))
        signal_script = os.path.join(script_dir, "dock-windows-signal.sh")
        if os.path.exists(signal_script):
            subprocess.run([signal_script], stderr=subprocess.DEVNULL)
        return False

    def clear_workspace_cache(self):
        import glob
        try:
            for fpath in glob.glob(os.path.join(self.cache_dir, "workspaces-*.json")):
                try:
                    os.remove(fpath)
                except OSError:
                    pass
        except Exception:
            pass

    def update_kde_desktops(self, mapping_json):
        try:
            data = json.loads(mapping_json)
            cache_file = os.path.join(self.cache_dir, "kde-active-desktops.json")
            tmp_file = cache_file + ".tmp"
            with open(tmp_file, "w") as f:
                json.dump(data, f)
            os.replace(tmp_file, cache_file)
            self.clear_workspace_cache()
            subprocess.run(["pkill", "-x", "-RTMIN+16", "waybar"], stderr=subprocess.DEVNULL)
        except Exception as e:
            print(f"Error updating KDE desktops: {e}", file=sys.stderr)

# load_kwin_script:
# Under Wayland, standard active window query tools like xdotool or xprop do not work.
# To retrieve window titles and workspace layout transitions under KDE, we inject a custom
# Javascript script directly into KWin's scripting engine. This script runs inside KWin's
# process space, binds to workspace events, and triggers DBus callbacks to this server.
    def load_kwin_script(self):
        script_content = """
        var currentConn = null;
        function notifyActiveWindow() {
            var win = workspace.activeWindow;
            var title = win ? win.caption : "";
            var app = (win && win.resourceClass) ? win.resourceClass.toString() : "";
            callDBus(
                "org.waybar.activewindow",
                "/ActiveWindow",
                "org.waybar.ActiveWindow",
                "update",
                title,
                app
            );
            notifyDesktops();
        }

        workspace.windowActivated.connect(function(client) {
            if (currentConn) {
                try {
                    currentConn.captionChanged.disconnect(notifyActiveWindow);
                } catch(e) {}
            }
            currentConn = client;
            if (client) {
                client.captionChanged.connect(notifyActiveWindow);
            }
            notifyActiveWindow();
        });

        workspace.windowAdded.connect(function() {
            callDBus(
                "org.waybar.activewindow",
                "/ActiveWindow",
                "org.waybar.ActiveWindow",
                "windowsChanged"
            );
        });
        workspace.windowRemoved.connect(function() {
            callDBus(
                "org.waybar.activewindow",
                "/ActiveWindow",
                "org.waybar.ActiveWindow",
                "windowsChanged"
            );
        });

        function notifyDesktops() {
            var mapping = {};
            if (workspace.screens && workspace.screens.length) {
                for (var i = 0; i < workspace.screens.length; i++) {
                    var output = workspace.screens[i];
                    if (!output) continue;
                    var name = output.name || output.toString() || ("Screen" + i);
                    var desc = null;
                    if (typeof workspace.currentDesktopForScreen === "function") {
                        try {
                            desc = workspace.currentDesktopForScreen(output);
                        } catch(e) {
                            // Fallback
                        }
                    }
                    if (!desc) {
                        desc = workspace.currentDesktop;
                    }
                    if (desc) {
                        mapping[name] = desc.id;
                    }
                }
            } else {
                var screens = Array.from({length: 8}, (_, i) => i);
                for (var i = 0; i < screens.length; i++) {
                    var scr = screens[i];
                    var name = null;
                    try {
                        name = workspace.screenAt ? workspace.screenAt(scr) : null;
                    } catch(e) {}
                    if (name && typeof name.name === "string") {
                        name = name.name;
                    } else if (name && typeof name.toString === "function") {
                        name = name.toString();
                    } else {
                        name = "Screen" + scr;
                    }
                    var desc = null;
                    if (typeof workspace.currentDesktopForScreen === "function") {
                        try {
                            desc = workspace.currentDesktopForScreen(scr);
                        } catch(e) {}
                    }
                    if (!desc) {
                        desc = workspace.currentDesktop;
                    }
                    if (desc) {
                        mapping[name] = desc.id;
                    }
                }
            }
            if (Object.keys(mapping).length === 0 && workspace.currentDesktop) {
                mapping["default"] = workspace.currentDesktop.id;
            }
            callDBus(
                "org.waybar.activewindow",
                "/ActiveWindow",
                "org.waybar.ActiveWindow",
                "desktopsChanged",
                JSON.stringify(mapping)
            );
        }

        workspace.currentDesktopChanged.connect(notifyDesktops);
        if (workspace.desktopChanged) {
            workspace.desktopChanged.connect(notifyDesktops);
        }
        notifyDesktops();
        """
        
        script_path = "/tmp/active_window_watcher.js"
        with open(script_path, "w") as f:
            f.write(script_content)
            
        # Cleanup first
        subprocess.run([
            "qdbus6", "org.kde.KWin", "/Scripting",
            "org.kde.kwin.Scripting.unloadScript", "active_window_watcher"
        ], capture_output=True)
        
        res = subprocess.run([
            "qdbus6", "org.kde.KWin", "/Scripting",
            "org.kde.kwin.Scripting.loadScript", script_path, "active_window_watcher"
        ], capture_output=True, text=True)
        script_id = res.stdout.strip()
        
        if script_id.isdigit():
            subprocess.run([
                "qdbus6", "org.kde.KWin", f"/Scripting/Script{script_id}",
                "org.kde.kwin.Script.run"
            ], capture_output=True)
            return script_id
        return None

    def cleanup(self):
        if self.script_id:
            subprocess.run([
                "qdbus6", "org.kde.KWin", "/Scripting",
                "org.kde.kwin.Scripting.unloadScript", "active_window_watcher"
            ], capture_output=True)
        try:
            if hasattr(self, 'dbus_monitor_proc'):
                self.dbus_monitor_proc.terminate()
        except Exception:
            pass

    def start_dbus_monitor(self):
        # We run dbus-monitor in a background pipe stream to track incoming desktop notifications
        # directly from the session bus. We capture notification parameters and maintain unread counters.
        monitor_cmd = [
            "dbus-monitor",
            "interface='org.freedesktop.Notifications'"
        ]
        self.dbus_monitor_proc = subprocess.Popen(
            monitor_cmd,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            text=True,
            bufsize=1
        )
        threading.Thread(target=self.read_dbus_monitor_stdout, daemon=True).start()

    def on_clipboard_changed(self, conn, sender_name, object_path, interface_name, signal_name, parameters, user_data):
        threading.Thread(target=self.check_and_write_clipboard, daemon=True).start()

    def check_and_write_clipboard(self):
        try:
            # Query current klipper contents to verify clip cache synchronization
            res = self.session_bus.call_sync(
                "org.kde.klipper.klipper",
                "/klipper",
                "org.kde.klipper.klipper",
                "getClipboardHistoryMenu",
                None,
                None,
                Gio.DBusCallFlags.NONE,
                -1,
                None
            )
            val = res.get_child_value(0).get_string()
            self.write_clipboard_json(val)
        except Exception:
            pass

    def write_clipboard_json(self, val):
        lines = [line.strip() for line in val.split("\n") if line.strip()]
        count = len(lines)
        if count == 0:
            status = {
                "text": "0",
                "alt": "empty",
                "class": "empty",
                "tooltip": "Clipboard empty"
            }
        else:
            latest = lines[0]
            preview = latest if len(latest) <= 200 else latest[:197] + "..."
            tooltip = f"Clipboard history: {count} entries (Klipper)\nLatest:\n{preview}\n\nLeft: open history · Right: clear · Middle: edit/sync"
            status = {
                "text": str(count),
                "alt": "normal",
                "class": "normal",
                "tooltip": tooltip
            }
        self.write_json_atomically(self.clipboard_cache, status)
        subprocess.run(["pkill", "-x", "-RTMIN+9", "waybar"], stderr=subprocess.DEVNULL)

    def write_json_atomically(self, path, data):
        tmp_file = path + f".tmp.{os.getpid()}"
        try:
            with open(tmp_file, "w") as f:
                json.dump(data, f)
            os.replace(tmp_file, path)
        except Exception as e:
            print(f"Error writing to {path}: {e}", file=sys.stderr)

    def get_inhibited(self):
        try:
            val = self.session_bus.call_sync(
                "org.kde.plasmashell",
                "/org/freedesktop/Notifications",
                "org.freedesktop.DBus.Properties",
                "Get",
                GLib.Variant("(ss)", ("org.freedesktop.Notifications", "Inhibited")),
                None,
                Gio.DBusCallFlags.NONE,
                -1,
                None
            )
            return val.get_child_value(0).get_variant().get_boolean()
        except Exception:
            return False

    def update_notifications_cache(self):
        inhibited = self.get_inhibited()
        count = self.unread_count
        
        try:
            # Write unread notifications count file atomically
            tmp_count = self.count_file + f".tmp.{os.getpid()}"
            with open(tmp_count, "w") as f:
                f.write(str(count))
            os.replace(tmp_count, self.count_file)
        except Exception as e:
            print(f"Error writing count file: {e}", file=sys.stderr)
            
        text = str(count) if count > 0 else ""
        if count > 0:
            if inhibited:
                class_name = "dnd-notification"
                alt_name = "dnd-notification"
                tooltip = f"{count} unread notification(s) (Do not disturb)"
            else:
                class_name = "notification"
                alt_name = "notification"
                tooltip = f"{count} unread notification(s)"
        else:
            if inhibited:
                class_name = "dnd-none"
                alt_name = "dnd-none"
                tooltip = "Do not disturb"
            else:
                class_name = "none"
                alt_name = "none"
                tooltip = "Notifications"
                
        status = {
            "text": text,
            "class": class_name,
            "alt": alt_name,
            "tooltip": tooltip
        }
        
        self.write_json_atomically(self.status_cache, status)
        self.write_json_atomically(self.history_cache, self.notifications)
        subprocess.run(["pkill", "-x", "-RTMIN+10", "waybar"], stderr=subprocess.DEVNULL)

    def start_dbus_monitor(self):
        def monitor_thread():
            cmd = ["dbus-monitor", "interface='org.freedesktop.Notifications'", "sender='org.freedesktop.Notifications'"]
            try:
                proc = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True)
                for line in proc.stdout:
                    GLib.idle_add(self.process_dbus_monitor_line, line.rstrip('\r\n'))
            except Exception as e:
                print(f"Error running dbus-monitor: {e}", file=sys.stderr)
        threading.Thread(target=monitor_thread, daemon=True).start()

    def unescape_dbus_str(self, s):
        return s.replace('\\"', '"').replace('\\\\', '\\')

    def check_notify_args_complete(self):
        if self.notif_method == "Notify" and len(self.notif_args) >= 5:
            app_name = self.unescape_dbus_str(str(self.notif_args[0]))
            replaces_id = int(self.notif_args[1])
            app_icon = self.unescape_dbus_str(str(self.notif_args[2]))
            summary = self.unescape_dbus_str(str(self.notif_args[3]))
            body = self.unescape_dbus_str(str(self.notif_args[4]))
            
            GLib.idle_add(self.handle_notify_call, self.notif_serial, app_name, app_icon, summary, body, replaces_id)
            self.notif_method = None

    def process_dbus_monitor_line(self, line):
        if self.notif_in_string:
            if line.endswith('"') and not line.endswith('\\"'):
                self.notif_current_string += "\n" + line[:-1]
                self.notif_args.append(self.notif_current_string)
                self.notif_in_string = False
                self.check_notify_args_complete()
            else:
                self.notif_current_string += "\n" + line
            return
            
        stripped = line.strip()
        if "member=Notify" in line and "method call" in line:
            self.notif_method = "Notify"
            m = re.search(r'serial=(\d+)', line)
            self.notif_serial = int(m.group(1)) if m else None
            self.notif_args = []
            return
            
        if "method return" in line:
            m = re.search(r'reply_serial=(\d+)', line)
            reply_serial = int(m.group(1)) if m else None
            self.notif_method = ("Reply", reply_serial)
            self.notif_args = []
            return
            
        if "member=NotificationClosed" in line and "signal" in line:
            self.notif_method = "NotificationClosed"
            self.notif_args = []
            return
            
        if "member=PropertiesChanged" in line and "signal" in line:
            if "path=/org/freedesktop/Notifications" in line:
                GLib.idle_add(self.handle_properties_changed)
            return
            
        if self.notif_method == "Notify":
            if len(self.notif_args) >= 5:
                return
            if stripped.startswith('string "'):
                val = stripped[8:]
                if val.endswith('"') and not val.endswith('\\"'):
                    self.notif_args.append(val[:-1])
                    self.check_notify_args_complete()
                else:
                    self.notif_in_string = True
                    self.notif_current_string = val
            elif stripped.startswith('uint32 '):
                try:
                    val = int(stripped[7:])
                    self.notif_args.append(val)
                    self.check_notify_args_complete()
                except ValueError:
                    pass
                    
        elif isinstance(self.notif_method, tuple) and self.notif_method[0] == "Reply":
            if stripped.startswith('uint32 '):
                try:
                    notif_id = int(stripped[7:])
                    reply_serial = self.notif_method[1]
                    GLib.idle_add(self.handle_notify_return, reply_serial, notif_id)
                except ValueError:
                    pass
                self.notif_method = None
                
        elif self.notif_method == "NotificationClosed":
            if stripped.startswith('uint32 '):
                try:
                    val = int(stripped[7:])
                    self.notif_args.append(val)
                    if len(self.notif_args) == 2:
                        GLib.idle_add(self.handle_notification_closed, self.notif_args[0], self.notif_args[1])
                        self.notif_method = None
                except ValueError:
                    pass

    def handle_notify_call(self, serial, app_name, app_icon, summary, body_text, replaces_id):
        self.notif_pending[serial] = {
            "app_name": app_name,
            "app_icon": app_icon,
            "summary": summary,
            "body": body_text,
            "replaces_id": replaces_id,
            "timestamp": int(time.time())
        }

    def handle_notify_return(self, reply_serial, notif_id):
        if reply_serial in self.notif_pending:
            notif_data = self.notif_pending.pop(reply_serial)
            notif_data["id"] = notif_id
            replaces_id = notif_data.pop("replaces_id", 0)
            
            replaced = False
            if replaces_id > 0:
                for idx, item in enumerate(self.notifications):
                    if item.get("id") == replaces_id:
                        self.notifications[idx] = notif_data
                        replaced = True
                        break
            if not replaced:
                for idx, item in enumerate(self.notifications):
                    if item.get("id") == notif_id:
                        self.notifications[idx] = notif_data
                        replaced = True
                        break
                        
            if not replaced:
                self.notifications.append(notif_data)
                self.unread_count += 1
                
            if len(self.notifications) > 50:
                self.notifications.pop(0)
                
            self.update_notifications_cache()

    def handle_notification_closed(self, notif_id, reason):
        if reason in (2, 3, 4):
            initial_len = len(self.notifications)
            self.notifications = [n for n in self.notifications if n.get("id") != notif_id]
            if len(self.notifications) != initial_len:
                self.unread_count = max(0, self.unread_count - 1)
                self.update_notifications_cache()

    def handle_properties_changed(self):
        self.update_notifications_cache()

    def handle_sigusr1(self):
        self.unread_count = 0
        self.update_notifications_cache()
        return True

    def handle_sigusr2(self):
        self.notifications = []
        self.unread_count = 0
        self.update_notifications_cache()
        return True

    def on_keyboard_layout_changed(self, conn, sender_name, object_path, interface_name, signal_name, parameters, user_data):
        subprocess.run(["pkill", "-x", "-RTMIN+2", "waybar"], stderr=subprocess.DEVNULL)

    def on_nightlight_changed(self, conn, sender_name, object_path, interface_name, signal_name, parameters, user_data):
        cache_dir = os.path.expanduser("~/.cache/waybar")
        cache_file = os.path.join(cache_dir, "nightlight-status.json")
        try:
            if os.path.exists(cache_file):
                os.remove(cache_file)
        except OSError:
            pass
        subprocess.run(["pkill", "-x", "-RTMIN+14", "waybar"], stderr=subprocess.DEVNULL)

    def on_brightness_changed(self, conn, sender_name, object_path, interface_name, signal_name, parameters, user_data):
        script_dir = os.path.dirname(os.path.abspath(__file__))
        brightness_script = os.path.join(script_dir, "brightness-status.sh")
        if os.path.exists(brightness_script):
            subprocess.run([brightness_script, "--refresh"], stderr=subprocess.DEVNULL)
            subprocess.run(["pkill", "-x", "-RTMIN+8", "waybar"], stderr=subprocess.DEVNULL)

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
        script_dir = os.path.dirname(os.path.abspath(__file__))
        vpn_script = os.path.join(script_dir, "vpn-status.sh")
        ts_script = os.path.join(script_dir, "tailscale-status.sh")
        
        def run_refresh():
            try:
                if os.path.exists(vpn_script):
                    subprocess.run([vpn_script, "--refresh"], stderr=subprocess.DEVNULL)
                    subprocess.run(["pkill", "-x", "-RTMIN+5", "waybar"], stderr=subprocess.DEVNULL)
                if os.path.exists(ts_script):
                    subprocess.run([ts_script, "--refresh"], stderr=subprocess.DEVNULL)
                    subprocess.run(["pkill", "-x", "-RTMIN+12", "waybar"], stderr=subprocess.DEVNULL)
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
        script_dir = os.path.dirname(os.path.abspath(__file__))
        kdeconnect_script = os.path.join(script_dir, "kdeconnect-status.sh")
        if not os.path.exists(kdeconnect_script):
            with self.kdeconnect_lock:
                self.kdeconnect_refreshing = False
            return
            
        def run_refresh():
            try:
                subprocess.run([kdeconnect_script, "--refresh"], stderr=subprocess.DEVNULL)
                subprocess.run(["pkill", "-x", "-RTMIN+18", "waybar"], stderr=subprocess.DEVNULL)
            finally:
                with self.kdeconnect_lock:
                    self.kdeconnect_refreshing = False
                    if self.kdeconnect_pending:
                        self.kdeconnect_pending = False
                        GLib.idle_add(self.trigger_kdeconnect_refresh)
                        
        threading.Thread(target=run_refresh, daemon=True).start()

    def on_virtual_desktops_changed(self, conn, sender_name, object_path, interface_name, signal_name, parameters, user_data):
        if signal_name in ("currentChanged", "desktopCreated", "desktopRemoved", "desktopDataChanged"):
            self.clear_workspace_cache()
            subprocess.run(["pkill", "-x", "-RTMIN+16", "waybar"], stderr=subprocess.DEVNULL)

    def on_upower_changed(self, conn, sender_name, object_path, interface_name, signal_name, parameters, user_data):
        with self.upower_lock:
            if self.upower_refreshing:
                self.upower_pending = True
                return
            self.upower_refreshing = True
        
        self.trigger_upower_refresh()

    def trigger_upower_refresh(self):
        script_dir = os.path.dirname(os.path.abspath(__file__))
        battery_script = os.path.join(script_dir, "device-battery-status.sh")
        if not os.path.exists(battery_script):
            with self.upower_lock:
                self.upower_refreshing = False
            return
            
        def run_refresh():
            try:
                subprocess.run([battery_script, "--refresh"], stderr=subprocess.DEVNULL)
                subprocess.run(["pkill", "-x", "-RTMIN+4", "waybar"], stderr=subprocess.DEVNULL)
            finally:
                with self.upower_lock:
                    self.upower_refreshing = False
                    if self.upower_pending:
                        self.upower_pending = False
                        GLib.idle_add(self.trigger_upower_refresh)
                        
        threading.Thread(target=run_refresh, daemon=True).start()

    def on_powerprofiles_changed(self, conn, sender_name, object_path, interface_name, signal_name, parameters, user_data):
        subprocess.run(["pkill", "-x", "-RTMIN+3", "waybar"], stderr=subprocess.DEVNULL)

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

    def run(self):
        try:
            self.loop.run()
        except KeyboardInterrupt:
            pass
        finally:
            self.cleanup()

if __name__ == "__main__":
    acquire_lock("kde-activewindow")
    server = ActiveWindowServer()
    server.run()
