"""Plasma notification tracking via dbus-monitor text parsing.

Plasma's Notifications D-Bus API has no stable typed listener for unread
history, so we scrape `dbus-monitor` lines for Notify / method-return /
NotificationClosed and keep a local unread count + history cache for Waybar.
"""

import os
import re
import subprocess
import sys
import threading
import time

import gi

gi.require_version("Gio", "2.0")
gi.require_version("GLib", "2.0")
from gi.repository import Gio, GLib  # noqa: E402

from kde_listener.signals import waybar_rtmin  # noqa: E402


class NotificationsMixin:
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
        click_hint = "\n\nLeft: open · Right: DND · Middle: settings"
        if count > 0:
            if inhibited:
                class_name = "dnd-notification"
                alt_name = "dnd-notification"
                tooltip = f"{count} unread notification(s) (Do not disturb){click_hint}"
            else:
                class_name = "notification"
                alt_name = "notification"
                tooltip = f"{count} unread notification(s){click_hint}"
        else:
            if inhibited:
                class_name = "dnd-none"
                alt_name = "dnd-none"
                tooltip = f"Do not disturb{click_hint}"
            else:
                class_name = "none"
                alt_name = "none"
                tooltip = f"Notifications{click_hint}"

        status = {
            "text": text,
            "class": class_name,
            "alt": alt_name,
            "tooltip": tooltip
        }

        self.write_json_atomically(self.status_cache, status)
        self.write_json_atomically(self.history_cache, self.notifications)
        waybar_rtmin("notifications")

    def start_dbus_monitor(self):
        def monitor_thread():
            cmd = [
                "dbus-monitor",
                "interface='org.freedesktop.Notifications'",
                "sender='org.freedesktop.Notifications'",
            ]
            try:
                self.dbus_monitor_proc = subprocess.Popen(
                    cmd, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True
                )
                for line in self.dbus_monitor_proc.stdout:
                    GLib.idle_add(self.process_dbus_monitor_line, line.rstrip("\r\n"))
            except Exception as e:
                print(f"Error running dbus-monitor: {e}", file=sys.stderr)

        threading.Thread(target=monitor_thread, daemon=True).start()

    def unescape_dbus_str(self, s):
        return s.replace('\\"', '"').replace('\\\\', '\\')

    def check_notify_args_complete(self):
        # Notify is positional: app_name, replaces_id, app_icon, summary, body, …
        # We only need the first five; later args (actions, hints, timeout) are ignored.
        if self.notif_method == "Notify" and len(self.notif_args) >= 5:
            app_name = self.unescape_dbus_str(str(self.notif_args[0]))
            replaces_id = int(self.notif_args[1])
            app_icon = self.unescape_dbus_str(str(self.notif_args[2]))
            summary = self.unescape_dbus_str(str(self.notif_args[3]))
            body = self.unescape_dbus_str(str(self.notif_args[4]))

            GLib.idle_add(self.handle_notify_call, self.notif_serial, app_name, app_icon, summary, body, replaces_id)
            self.notif_method = None

    def process_dbus_monitor_line(self, line):
        # Hand-rolled state machine over dbus-monitor's human-readable dump:
        # multiline string bodies, serial → reply_serial matching for the
        # returned notification id, and NotificationClosed (id, reason).
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
        # Close reasons (org.freedesktop.Notifications): 1=expired, 2=dismissed,
        # 3=CloseNotification, 4=undefined. Count down for 2/3/4 only — expired
        # (1) is left in history until the user clears unread.
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
