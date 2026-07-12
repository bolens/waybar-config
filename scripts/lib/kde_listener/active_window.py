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
            unpacked = params.unpack()
            title = unpacked[0] if len(unpacked) > 0 else ""
            app = unpacked[1] if len(unpacked) > 1 else ""
            # Output is resolved in flush via KWin.activeOutputName (KWin
            # callDBus with a 3rd string arg was silently failing on Plasma).
            self.update_active_window(title, app, "")
            invocation.return_value(None)
        elif method == "windowsChanged":
            # Debounce KWin windowAdded/Removed spam into one dock refresh.
            if self.windows_changed_timeout_id != 0:
                GLib.source_remove(self.windows_changed_timeout_id)
            self.windows_changed_timeout_id = GLib.timeout_add(250, self.flush_windows_changed)
            invocation.return_value(None)
        elif method == "desktopsChanged":
            mapping_json = params.unpack()[0]
            self.update_kde_desktops(mapping_json)
            invocation.return_value(None)

    @staticmethod
    def _safe_output_name(name: str) -> str:
        import re

        safe = re.sub(r"[^A-Za-z0-9_-]", "_", name or "")
        return safe or "unknown"

    @staticmethod
    def _ensure_writable(path: str) -> None:
        """Drop root-/other-owned or mode-locked cache files that block writes."""
        try:
            if not os.path.exists(path):
                return
            writable = os.access(path, os.W_OK)
            mode = os.stat(path).st_mode
            owner_write = bool(mode & 0o200)
            # Root passes access(W_OK) even on 0444; still require owner-write bit.
            if writable and owner_write:
                return
            os.remove(path)
        except OSError:
            pass

    def update_active_window(self, title, app, output=""):
        # Short debounce: coalesce caption spam without lagging the dock highlight.
        self.pending_title = title
        self.pending_app = app
        self.pending_output = output or ""
        if self.active_window_timeout_id != 0:
            GLib.source_remove(self.active_window_timeout_id)
        self.active_window_timeout_id = GLib.timeout_add(50, self.flush_active_window_update)

    def _resolve_active_output(self, output: str) -> str:
        """Prefer KWin-script output; fall back to KWin.activeOutputName()."""
        if output:
            return output
        try:
            res = subprocess.run(
                [
                    "qdbus6",
                    "org.kde.KWin",
                    "/KWin",
                    "org.kde.KWin.activeOutputName",
                ],
                capture_output=True,
                text=True,
                timeout=1,
                check=False,
            )
            name = (res.stdout or "").strip()
            if name:
                return name
        except (OSError, subprocess.TimeoutExpired):
            pass
        return ""

    def _known_output_names(self) -> list[str]:
        """Outputs that already have (or need) per-output title caches."""
        names: list[str] = []
        prefix = "active-window-title-"
        suffix = ".raw"
        try:
            for fname in os.listdir(self.cache_dir):
                if fname.startswith(prefix) and fname.endswith(suffix):
                    mid = fname[len(prefix) : -len(suffix)]
                    if mid and mid != "unknown":
                        names.append(mid)
        except OSError:
            pass
        return names

    def flush_active_window_update(self):
        self.active_window_timeout_id = 0
        title = self.pending_title
        output = self._resolve_active_output(getattr(self, "pending_output", "") or "")

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

        cleaned_title = clean_title(title) if title else ""

        def write_json(path: str, payload: dict) -> None:
            self._ensure_writable(path)
            tmp_file = path + ".tmp"
            with open(tmp_file, "w", encoding="utf-8") as f:
                json.dump(payload, f)
            os.replace(tmp_file, path)

        def write_raw(path: str, text: str) -> None:
            self._ensure_writable(path)
            try:
                with open(path + ".tmp", "w", encoding="utf-8") as f:
                    f.write(text)
                os.replace(path + ".tmp", path)
            except OSError:
                pass

        def write_output_caches(safe: str) -> None:
            try:
                write_json(os.path.join(self.cache_dir, f"active-window-{safe}.json"), data)
            except OSError as e:
                print(f"Error writing active-window-{safe}.json: {e}", file=sys.stderr)
            write_raw(
                os.path.join(self.cache_dir, f"active-window-title-{safe}.raw"),
                cleaned_title,
            )

        # Global caches (non-per-output consumers + fallback).
        try:
            write_json(self.cache_file, data)
        except OSError as e:
            print(f"Error writing active-window.json: {e}", file=sys.stderr)
        write_raw(os.path.join(self.cache_dir, "active-window-title.raw"), cleaned_title)

        # Per-output caches watched by active-window-scroll when per_output is on.
        # KWin scripts often omit win.output; activeOutputName() fills that gap.
        # If we still cannot resolve an output, mirror to every known per-output raw
        # so zscroll keeps updating instead of freezing on a stale empty file.
        if output:
            write_output_caches(self._safe_output_name(output))
        else:
            for name in self._known_output_names():
                write_output_caches(self._safe_output_name(name))

        # Refresh dock highlight only — keep list cache (no qdbus Match storm).
        signal_script = os.path.join(waybar_scripts_dir(), "dock", "dock-windows-signal.sh")
        if os.path.exists(signal_script):
            subprocess.run(
                [signal_script, "--force", "--focus-only"],
                stderr=subprocess.DEVNULL,
            )

        return False

    def flush_windows_changed(self):
        self.windows_changed_timeout_id = 0
        signal_script = os.path.join(waybar_scripts_dir(), "dock", "dock-windows-signal.sh")
        if os.path.exists(signal_script):
            # Window add/remove: full list rebuild.
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
        function activeWin() {
            try {
                if (workspace.activeWindow) return workspace.activeWindow;
            } catch (e) {}
            try {
                if (workspace.activeClient) return workspace.activeClient;
            } catch (e2) {}
            return null;
        }
        function notifyActiveWindow() {
            var win = activeWin();
            var title = win ? (win.caption || "") : "";
            var app = (win && win.resourceClass) ? win.resourceClass.toString() : "";
            // Two-string callDBus only — a third arg broke updates on Plasma.
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

        function onActivated(client) {
            if (currentConn) {
                try {
                    currentConn.captionChanged.disconnect(notifyActiveWindow);
                } catch(e) {}
            }
            currentConn = client || activeWin();
            if (currentConn) {
                try {
                    currentConn.captionChanged.connect(notifyActiveWindow);
                } catch(e2) {}
            }
            notifyActiveWindow();
        }

        if (workspace.windowActivated) {
            workspace.windowActivated.connect(onActivated);
        }
        if (workspace.clientActivated) {
            workspace.clientActivated.connect(onActivated);
        }
        if (workspace.activeWindowChanged) {
            workspace.activeWindowChanged.connect(notifyActiveWindow);
        }

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
        notifyActiveWindow();
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
