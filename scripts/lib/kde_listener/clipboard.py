import json
import os
import sys
import threading

import gi

gi.require_version("Gio", "2.0")
gi.require_version("GLib", "2.0")
from gi.repository import Gio  # noqa: E402

from kde_listener.signals import waybar_rtmin  # noqa: E402


class ClipboardMixin:
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
        waybar_rtmin("clipboard")

    def write_json_atomically(self, path, data):
        tmp_file = path + f".tmp.{os.getpid()}"
        try:
            with open(tmp_file, "w") as f:
                json.dump(data, f)
            os.replace(tmp_file, path)
        except Exception as e:
            print(f"Error writing to {path}: {e}", file=sys.stderr)
