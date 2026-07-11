import glob
import html
import json
import os
import subprocess
import sys

import gi

gi.require_version("Gio", "2.0")
gi.require_version("GLib", "2.0")
from gi.repository import Gio, GLib  # noqa: E402

from kde_listener.paths import waybar_scripts_dir  # noqa: E402
from kde_listener.signals import waybar_rtmin  # noqa: E402
from kde_listener.titles import clean_title, trim_title  # noqa: E402

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


class ActiveWindowMixin:
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

        trimmed = trim_title(title)
        if not title:
            data = {
                "text": "󰇄  Desktop",
                "tooltip": "No active window",
                "class": "desktop"
            }
        else:
            data = {
                "text": f"󰖲  {html.escape(trimmed)}",
                "tooltip": html.escape(title),
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

        return False

    def flush_windows_changed(self):
        self.windows_changed_timeout_id = 0
        signal_script = os.path.join(waybar_scripts_dir(), "dock", "dock-windows-signal.sh")
        if os.path.exists(signal_script):
            subprocess.run([signal_script], stderr=subprocess.DEVNULL)
        return False

    def clear_workspace_cache(self):
        """
        Invalidates output-specific workspaces JSON caches (e.g. workspaces-DP-1.json).
        This bypasses the 0.2-second cache TTL inside workspaces-query.py, avoiding
        stale layout displays during desktop transitions when signals arrive before
        DBus states have finished writing.
        """
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
            waybar_rtmin("workspaces")
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

    def on_virtual_desktops_changed(self, conn, sender_name, object_path, interface_name, signal_name, parameters, user_data):
        if signal_name in ("currentChanged", "desktopCreated", "desktopRemoved", "desktopDataChanged"):
            self.clear_workspace_cache()
            waybar_rtmin("workspaces")
