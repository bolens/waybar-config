#!/usr/bin/env python3
"""Rewrite Plasma/Qt HTML notification bodies for Pango daemons (mako).

DrKonqi sends ``<html><tt>…</tt></html>`` bodies. Mako advertises body-markup
but only understands Pango, so those toasts render as escaped entities.

When the session notification server is mako, this listener:

1. Monitors ``Notify`` via BecomeMonitor (method calls only — returns are not
   reliably delivered to monitors on dbus-broker)
2. After a short delay, finds the toast via ``makoctl list -j`` and replaces
   it in place (``replaces_id``) with a plain body
3. Stamps ``x-waybar-notify-sanitized`` so rewritten traffic is ignored

No-op when Plasma (or another Qt HTML server) owns Notifications.
"""

from __future__ import annotations

import json
import os
import subprocess
import sys
import time

_LIB = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "lib")
if _LIB not in sys.path:
    sys.path.insert(0, _LIB)

import gi  # noqa: E402

gi.require_version("Gio", "2.0")
gi.require_version("GLib", "2.0")
from gi.repository import Gio, GLib  # noqa: E402

from kde_listener.lock import acquire_lock  # noqa: E402
from notify_markup import (  # noqa: E402
    HINT_SANITIZED,
    sanitize_notification_body,
)

_LOCK_NAME = "notify-sanitize"
_TARGET_SERVERS = frozenset({"mako"})
_SERVER_CACHE_SEC = 30.0
# Let mako accept the toast before we replace it in place.
_REWRITE_DELAY_MS = 40


def _hints_has_sanitized(hints: GLib.Variant | None) -> bool:
    if hints is None or not hints.is_of_type(GLib.VariantType("a{sv}")):
        return False
    for i in range(hints.n_children()):
        entry = hints.get_child_value(i)
        if entry.get_child_value(0).get_string() == HINT_SANITIZED:
            return True
    return False


def _with_sanitized_hint(hints: GLib.Variant | None) -> GLib.Variant:
    builder = GLib.VariantBuilder.new(GLib.VariantType("a{sv}"))
    if hints is not None and hints.is_of_type(GLib.VariantType("a{sv}")):
        for i in range(hints.n_children()):
            entry = hints.get_child_value(i)
            key = entry.get_child_value(0).get_string()
            if key == HINT_SANITIZED:
                continue
            boxed = entry.get_child_value(1)
            inner = boxed.get_variant() if boxed.get_type().is_variant() else boxed
            builder.add_value(
                GLib.Variant.new_dict_entry(GLib.Variant("s", key), GLib.Variant("v", inner))
            )
    builder.add_value(
        GLib.Variant.new_dict_entry(
            GLib.Variant("s", HINT_SANITIZED),
            GLib.Variant("v", GLib.Variant("b", True)),
        )
    )
    return builder.end()


def _makoctl_list() -> list:
    try:
        out = subprocess.check_output(
            ["makoctl", "list", "-j"],
            text=True,
            stderr=subprocess.DEVNULL,
            timeout=2,
        )
        data = json.loads(out or "[]")
        return data if isinstance(data, list) else []
    except Exception:
        return []


class NotifySanitizeServer:
    def __init__(self) -> None:
        self._mako_cached: bool | None = None
        self._mako_cached_at = 0.0
        self._bus = Gio.bus_get_sync(Gio.BusType.SESSION, None)
        self._monitor = self._open_monitor_connection()
        self._monitor.add_filter(self._message_filter, None)

    def _open_monitor_connection(self) -> Gio.DBusConnection:
        # BecomeMonitor puts the connection into monitor-only mode, so Notify
        # replacements must use a separate session bus connection (self._bus).
        address = Gio.dbus_address_get_for_bus_sync(Gio.BusType.SESSION, None)
        conn = Gio.DBusConnection.new_for_address_sync(
            address,
            (
                Gio.DBusConnectionFlags.AUTHENTICATION_CLIENT
                | Gio.DBusConnectionFlags.MESSAGE_BUS_CONNECTION
            ),
            None,
            None,
        )
        rules = [
            "type='method_call',interface='org.freedesktop.Notifications',member='Notify'",
        ]
        conn.call_sync(
            "org.freedesktop.DBus",
            "/org/freedesktop/DBus",
            "org.freedesktop.DBus.Monitoring",
            "BecomeMonitor",
            GLib.Variant("(asu)", (rules, 0)),
            None,
            Gio.DBusCallFlags.NONE,
            -1,
            None,
        )
        # new_for_address connections do not process messages until started.
        conn.start_message_processing()
        return conn

    def _server_is_mako(self) -> bool:
        now = time.monotonic()
        if (
            self._mako_cached is not None
            and (now - self._mako_cached_at) < _SERVER_CACHE_SEC
        ):
            return self._mako_cached
        try:
            result = self._bus.call_sync(
                "org.freedesktop.Notifications",
                "/org/freedesktop/Notifications",
                "org.freedesktop.Notifications",
                "GetServerInformation",
                None,
                GLib.VariantType("(ssss)"),
                Gio.DBusCallFlags.NONE,
                1500,
                None,
            )
            name = result.unpack()[0].lower()
            self._mako_cached = name in _TARGET_SERVERS
        except Exception:
            self._mako_cached = False
        self._mako_cached_at = now
        return self._mako_cached

    def _message_filter(self, _connection, message, incoming, _user_data=None):
        # PyGObject passes user_data as a 4th arg even when None.
        # Never do sync D-Bus from inside a filter — defer to the main loop.
        if not incoming or message is None:
            return message
        if message.get_message_type() != Gio.DBusMessageType.METHOD_CALL:
            return message
        if (
            message.get_interface() == "org.freedesktop.Notifications"
            and message.get_member() == "Notify"
        ):
            try:
                body = message.get_body()
                if body is None or body.n_children() < 8:
                    return message
                # Snapshot variants — the message may be freed after filter returns.
                snapshot = (
                    body.get_child_value(0).get_string(),
                    body.get_child_value(2).get_string(),
                    body.get_child_value(3).get_string(),
                    body.get_child_value(4).get_string(),
                    body.get_child_value(5),
                    body.get_child_value(6),
                    body.get_child_value(7).get_int32(),
                )
            except Exception:
                return message
            GLib.idle_add(self._handle_notify_snapshot, *snapshot)
        return message

    def _handle_notify_snapshot(
        self,
        app_name: str,
        app_icon: str,
        summary: str,
        body_text: str,
        actions: GLib.Variant | None,
        hints: GLib.Variant | None,
        expire: int,
    ) -> bool:
        if _hints_has_sanitized(hints):
            return False
        if not self._server_is_mako():
            return False

        sanitized = sanitize_notification_body(body_text)
        if sanitized is None:
            return False

        GLib.timeout_add(
            _REWRITE_DELAY_MS,
            self._rewrite_visible,
            app_name,
            app_icon,
            summary,
            body_text,
            sanitized,
            actions,
            hints,
            expire,
        )
        return False

    def _find_notification_id(self, app_name: str, summary: str, body_text: str) -> int | None:
        for item in _makoctl_list():
            if not isinstance(item, dict):
                continue
            if item.get("app_name") != app_name:
                continue
            if item.get("summary") != summary:
                continue
            if item.get("body") != body_text:
                continue
            try:
                return int(item["id"])
            except (KeyError, TypeError, ValueError):
                continue
        return None

    def _rewrite_visible(
        self,
        app_name: str,
        app_icon: str,
        summary: str,
        original_body: str,
        sanitized_body: str,
        actions: GLib.Variant | None,
        hints: GLib.Variant | None,
        expire: int,
    ) -> bool:
        notif_id = self._find_notification_id(app_name, summary, original_body)
        if notif_id is None:
            # Toast may still be buffering — one more try shortly.
            GLib.timeout_add(
                80,
                self._rewrite_visible_retry,
                app_name,
                app_icon,
                summary,
                original_body,
                sanitized_body,
                actions,
                hints,
                expire,
            )
            return False
        self._replace_notification(
            notif_id,
            app_name,
            app_icon,
            summary,
            sanitized_body,
            actions,
            hints,
            expire,
        )
        return False

    def _rewrite_visible_retry(
        self,
        app_name: str,
        app_icon: str,
        summary: str,
        original_body: str,
        sanitized_body: str,
        actions: GLib.Variant | None,
        hints: GLib.Variant | None,
        expire: int,
    ) -> bool:
        notif_id = self._find_notification_id(app_name, summary, original_body)
        if notif_id is None:
            return False
        self._replace_notification(
            notif_id,
            app_name,
            app_icon,
            summary,
            sanitized_body,
            actions,
            hints,
            expire,
        )
        return False

    def _replace_notification(
        self,
        notif_id: int,
        app_name: str,
        app_icon: str,
        summary: str,
        sanitized_body: str,
        actions: GLib.Variant | None,
        hints: GLib.Variant | None,
        expire: int,
    ) -> None:
        try:
            if actions is None:
                actions = GLib.Variant("as", [])
            new_hints = _with_sanitized_hint(hints)
            params = GLib.Variant.new_tuple(
                GLib.Variant("s", app_name),
                GLib.Variant("u", int(notif_id)),
                GLib.Variant("s", app_icon),
                GLib.Variant("s", summary),
                GLib.Variant("s", sanitized_body),
                actions,
                new_hints,
                GLib.Variant("i", int(expire)),
            )
            self._bus.call_sync(
                "org.freedesktop.Notifications",
                "/org/freedesktop/Notifications",
                "org.freedesktop.Notifications",
                "Notify",
                params,
                GLib.VariantType("(u)"),
                Gio.DBusCallFlags.NONE,
                3000,
                None,
            )
        except Exception as exc:
            print(f"notify-sanitize: replace failed: {exc}", file=sys.stderr)

    def run(self) -> None:
        loop = GLib.MainLoop()
        loop.run()


def main() -> int:
    acquire_lock(_LOCK_NAME)
    try:
        NotifySanitizeServer().run()
    except Exception as exc:
        print(f"notify-sanitize: failed to start: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
