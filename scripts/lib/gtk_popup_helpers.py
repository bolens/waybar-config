"""Shared GTK popup helpers for Waybar network popups (VPN / ethernet)."""

from __future__ import annotations

import json
import os
import re
import shutil
import subprocess
from typing import Callable


def have_cmd(cmd: str) -> bool:
    return shutil.which(cmd) is not None


def get_mouse_position(gdk_module=None) -> tuple[int, int]:
    """Best-effort pointer position across Hyprland / X11 / sway / GTK."""
    Gdk = gdk_module
    if Gdk is None:
        try:
            import gi

            gi.require_version("Gdk", "3.0")
            from gi.repository import Gdk as Gdk  # noqa: E402
        except Exception:
            Gdk = None

    comp = (os.environ.get("WAYBAR_COMPOSITOR") or "").strip().lower()
    if comp == "hyprland" or os.environ.get("HYPRLAND_INSTANCE_SIGNATURE"):
        try:
            out = subprocess.check_output(["hyprctl", "cursorpos"], text=True).strip()
            x, y = map(int, out.split(","))
            return x, y
        except Exception:
            pass

    try:
        import Xlib.display

        display = Xlib.display.Display()
        root = display.screen().root
        pointer = root.query_pointer()
        return pointer.root_x, pointer.root_y
    except Exception:
        pass

    try:
        out = subprocess.check_output(
            ["xdotool", "getmouselocation", "--shell"], text=True
        )
        vals = dict(line.split("=") for line in out.strip().splitlines() if "=" in line)
        return int(vals["X"]), int(vals["Y"])
    except Exception:
        pass

    try:
        out = subprocess.check_output(["swaymsg", "-t", "get_seats"], text=True)
        seats = json.loads(out)
        for seat in seats:
            if "devices" in seat:
                for dev in seat["devices"]:
                    if dev.get("type") == "pointer" and "xy" in dev:
                        return tuple(dev["xy"])  # type: ignore[return-value]
    except Exception:
        pass

    if Gdk is not None:
        try:
            display = Gdk.Display.get_default()
            if display is not None:
                seat = display.get_default_seat()
                if seat is not None:
                    pointer = seat.get_pointer()
                    if pointer is not None and hasattr(pointer, "get_position"):
                        _screen, x, y = pointer.get_position()
                        return int(x), int(y)
                monitor = (
                    display.get_primary_monitor()
                    if hasattr(display, "get_primary_monitor")
                    else None
                )
                if monitor is None and hasattr(display, "get_monitor"):
                    monitor = display.get_monitor(0)
                if monitor is not None:
                    geo = monitor.get_geometry()
                    return geo.x + geo.width // 2, geo.y + geo.height // 2
        except Exception:
            pass

    return 960, 540


_PUBLIC_IP_URLS = (
    "https://api64.ipify.org?format=text",
    "https://ifconfig.me/ip",
    "https://icanhazip.com",
    "https://checkip.amazonaws.com",
)


def _fetch_ip_from_urls(
    *,
    curl_extra: list[str] | None = None,
    timeout: float = 2.0,
    debug: Callable[[str], None] | None = None,
) -> str | None:
    log = debug or (lambda _msg: None)
    if not have_cmd("curl"):
        return None
    extra = curl_extra or []
    for url in _PUBLIC_IP_URLS:
        try:
            ip = subprocess.check_output(
                ["curl", "-fsS", "--connect-timeout", "2", "--max-time", "4", *extra, url],
                text=True,
                timeout=timeout,
            ).strip()
            ip = re.sub(r"\s+", "", ip)
            log(f"Public IP fetched from {url}: {ip}")
            if re.match(r"^[\d.:a-fA-F]+$", ip):
                return ip
        except Exception as e:
            log(f"Error fetching public IP from {url}: {e}")
    return None


def get_public_ip(
    *,
    debug: Callable[[str], None] | None = None,
) -> str:
    log = debug or (lambda _msg: None)
    if not have_cmd("curl") and not have_cmd("wget"):
        log("curl/wget not installed")
        return "curl not installed"
    ip = _fetch_ip_from_urls(debug=debug)
    if ip:
        return ip
    return "n/a"


def get_real_and_vpn_ip(
    *,
    debug: Callable[[str], None] | None = None,
) -> tuple[str, str]:
    """Return (real_ip, vpn_ip) using curl --interface for the default route iface."""
    log = debug or (lambda _msg: None)
    if not have_cmd("curl"):
        log("curl not installed")
        return ("curl not installed", "curl not installed")
    vpn_ip = _fetch_ip_from_urls(debug=debug) or "n/a"
    try:
        if not have_cmd("ip"):
            log("ip not installed")
            raise RuntimeError("ip not installed")
        default_iface = subprocess.check_output(
            "ip route get 1 | awk '{print $5; exit}'",
            shell=True,
            text=True,
            timeout=2,
        ).strip()
        log(f"Default iface: {default_iface}")
        real_ip = (
            _fetch_ip_from_urls(
                curl_extra=["--interface", default_iface],
                debug=debug,
            )
            or "n/a"
        )
    except Exception as e:
        log(f"Error fetching real IP: {e}")
        real_ip = vpn_ip
    return real_ip, vpn_ip
