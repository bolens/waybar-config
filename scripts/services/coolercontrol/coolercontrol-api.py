#!/usr/bin/env python3
"""CoolerControl API helper for Waybar status/click scripts.

Subcommands:
  fetch-bundle   → JSON: status, devices, modes, modes_active, write_access
  probe-write    → JSON: {"write_access": true|false|null, "http": N}
  cycle          → activate next/prev mode (requires write); JSON result
  activate       → activate mode by uid
  list-modes     → JSON modes + active

Auth: Bearer token preferred; if token auth fails (or missing), fall back to
POST /login with ui_pass + cookie.
Write probe: PATCH /settings with {} → 200 writable, 403 readonly.

Test hooks (env):
  WAYBAR_CC_API_URL, WAYBAR_CC_TOKEN, WAYBAR_CC_UI_USER, WAYBAR_CC_UI_PASS
  WAYBAR_CC_FIXTURE_DIR  → read status.json, devices.json, modes.json,
                           modes_active.json, write_http.txt (status code)
"""
from __future__ import annotations

import json
import os
import subprocess
import sys
import tempfile
import time
from pathlib import Path
from typing import Any


def _env(name: str, default: str = "") -> str:
    return os.environ.get(name, default) or default


def _bases(api: str) -> list[str]:
    api = api.rstrip("/")
    http = api.replace("https://", "http://") if api.startswith("https://") else api
    https = api if api.startswith("https://") else api.replace("http://", "https://")
    # Prefer http on loopback (daemon allows plain HTTP locally).
    out = [http]
    if https != http:
        out.append(https)
    return out


def _curl(args: list[str]) -> subprocess.CompletedProcess[str] | None:
    try:
        return subprocess.run(args, capture_output=True, text=True, timeout=6)
    except Exception:
        return None


def _http(
    base: str,
    method: str,
    path: str,
    *,
    headers: list[str] | None = None,
    cookie_jar: str | None = None,
    netrc: str | None = None,
    body: str | None = None,
    content_type: str | None = None,
) -> tuple[int, str]:
    args = ["curl", "-sS", "--max-time", "4", "-w", "\n%{http_code}", "-X", method]
    if base.startswith("https://"):
        args.append("-k")
    if netrc:
        args += ["--netrc-file", netrc]
    if cookie_jar:
        args += ["-b", cookie_jar, "-c", cookie_jar]
    if headers:
        for h in headers:
            args += ["-H", h]
    if content_type:
        args += ["-H", f"Content-Type: {content_type}"]
    if body is not None:
        args += ["--data-binary", body]
    args.append(f"{base}{path}")
    r = _curl(args)
    if r is None:
        return 0, ""
    out = r.stdout or ""
    body_out, _, code = out.rpartition("\n")
    try:
        return int(code.strip() or "0"), body_out
    except ValueError:
        return 0, body_out


class CcClient:
    def __init__(self) -> None:
        self.api = _env("WAYBAR_CC_API_URL", _env("CC_API_URL", "http://127.0.0.1:11987"))
        self.user = _env("WAYBAR_CC_UI_USER", _env("CC_UI_USER", "CCAdmin"))
        self.password = _env("WAYBAR_CC_UI_PASS", _env("CC_UI_PASS", ""))
        self.token = _env("WAYBAR_CC_TOKEN", _env("CC_TOKEN", ""))
        if self.token in ("CHANGE_ME", "null"):
            self.token = ""
        if self.password in ("CHANGE_ME", "null"):
            self.password = ""
        self.fixture_dir = _env("WAYBAR_CC_FIXTURE_DIR", "")
        self._base: str | None = None
        self._headers: list[str] | None = None
        self._jar: str | None = None
        self._td: tempfile.TemporaryDirectory[str] | None = None
        self.auth_method: str | None = None  # "bearer" | "basic" | "fixture"

    def close(self) -> None:
        if self._td is not None:
            self._td.cleanup()
            self._td = None

    def __enter__(self) -> CcClient:
        return self

    def __exit__(self, *args: object) -> None:
        self.close()

    def _fixture(self, name: str) -> str | None:
        if not self.fixture_dir:
            return None
        path = Path(self.fixture_dir) / name
        if path.is_file():
            return path.read_text()
        return None

    def _accept_session(
        self,
        base: str,
        *,
        headers: list[str] | None,
        jar: str | None,
        td: tempfile.TemporaryDirectory[str] | None,
        method: str,
    ) -> None:
        self._base = base
        self._headers = headers
        self._jar = jar
        self._td = td
        self.auth_method = method

    def _status_ok(self, base: str, *, headers: list[str] | None, jar: str | None) -> bool:
        code, body = _http(base, "GET", "/status", headers=headers, cookie_jar=jar)
        return code == 200 and bool(body.strip())

    def _try_bearer(self, base: str) -> bool:
        if not self.token:
            return False
        headers = [f"Authorization: Bearer {self.token}"]
        if not self._status_ok(base, headers=headers, jar=None):
            return False
        self._accept_session(base, headers=headers, jar=None, td=None, method="bearer")
        return True

    def _try_password(self, base: str) -> bool:
        if not self.password:
            return False
        td = tempfile.TemporaryDirectory(prefix="cc-api.")
        try:
            netrc = Path(td.name) / "netrc"
            jar = str(Path(td.name) / "cookies")
            netrc.write_text(
                f"machine 127.0.0.1\nlogin {self.user}\npassword {self.password}\n"
                f"machine localhost\nlogin {self.user}\npassword {self.password}\n"
            )
            netrc.chmod(0o600)
            code, _ = _http(base, "POST", "/login", netrc=str(netrc), cookie_jar=jar)
            if code != 200:
                td.cleanup()
                return False
            if not self._status_ok(base, headers=None, jar=jar):
                td.cleanup()
                return False
            self._accept_session(base, headers=None, jar=jar, td=td, method="basic")
            return True
        except Exception:
            td.cleanup()
            return False

    def authenticate(self) -> bool:
        if self.fixture_dir:
            # Fixtures imply auth ok when status.json exists.
            if self._fixture("status.json") is not None:
                self.auth_method = "fixture"
                return True
            return False

        for base in _bases(self.api):
            # Prefer Bearer token; only fall back to ui_pass if token missing or fails.
            if self._try_bearer(base):
                return True
            if self._try_password(base):
                return True
        return False

    def request(
        self,
        method: str,
        path: str,
        *,
        body: str | None = None,
        content_type: str | None = None,
    ) -> tuple[int, str]:
        if self.fixture_dir:
            # Map fixture files for GETs; write probe via write_http.txt
            if method == "PATCH" and path == "/settings":
                raw = self._fixture("write_http.txt")
                try:
                    return int((raw or "403").strip()), "{}"
                except ValueError:
                    return 403, "{}"
            mapping = {
                ("GET", "/status"): "status.json",
                ("GET", "/devices"): "devices.json",
                ("GET", "/modes"): "modes.json",
                ("GET", "/modes-active"): "modes_active.json",
            }
            name = mapping.get((method, path))
            if name:
                data = self._fixture(name)
                if data is not None:
                    return 200, data
                return 404, ""
            if method == "POST" and path.startswith("/modes-active/"):
                # Record activation for tests
                act = Path(self.fixture_dir) / "last_activate.txt"
                act.write_text(path.rsplit("/", 1)[-1] + "\n")
                wh = self._fixture("write_http.txt")
                code = int((wh or "200").strip() or "200")
                return code, "{}"
            return 404, ""

        if not self._base:
            if not self.authenticate():
                return 0, ""
        assert self._base is not None
        return _http(
            self._base,
            method,
            path,
            headers=self._headers,
            cookie_jar=self._jar,
            body=body,
            content_type=content_type,
        )

    def get_json(self, path: str) -> tuple[int, Any]:
        code, body = self.request("GET", path)
        if code != 200 or not body.strip():
            return code, None
        try:
            return code, json.loads(body)
        except Exception:
            return code, None

    def probe_write(self) -> tuple[bool | None, int]:
        """Return (writable, http_code). None writable = probe failed.

        Empty PATCH /settings is CoolerControl's documented writability probe:
        200 = writable, 401/403 = read-only auth, other codes = inconclusive.
        """
        code, _ = self.request(
            "PATCH",
            "/settings",
            body="{}",
            content_type="application/json",
        )
        if code == 200:
            return True, code
        if code in (401, 403):
            return False, code
        return None, code

    def probe_write_cached(self) -> tuple[bool | None, int]:
        """Cache write-access probe to avoid PATCH on every status refresh.

        Env:
          WAYBAR_CC_WRITE_PROBE_TTL — seconds (default 600). 0 disables cache.
          WAYBAR_CC_WRITE_CACHE — override cache file path.
          WAYBAR_CC_FORCE_WRITE_PROBE=1 — bypass cache.
        """
        ttl = int(_env("WAYBAR_CC_WRITE_PROBE_TTL", "600") or "600")
        if _env("WAYBAR_CC_FORCE_WRITE_PROBE") in ("1", "true", "yes") or ttl <= 0:
            return self.probe_write()

        cache_path = Path(
            _env("WAYBAR_CC_WRITE_CACHE")
            or str(
                Path(os.environ.get("XDG_CACHE_HOME", str(Path.home() / ".cache")))
                / "waybar"
                / "coolercontrol-write.json"
            )
        )
        try:
            if cache_path.is_file():
                age = time.time() - cache_path.stat().st_mtime
                if age < ttl:
                    data = json.loads(cache_path.read_text(encoding="utf-8"))
                    wa = data.get("write_access")
                    code = int(data.get("http") or 0)
                    if wa is True or wa is False or wa is None:
                        return wa, code
        except Exception:
            pass

        writable, code = self.probe_write()
        try:
            cache_path.parent.mkdir(parents=True, exist_ok=True)
            tmp = cache_path.with_suffix(f".tmp.{os.getpid()}")
            tmp.write_text(
                json.dumps({"write_access": writable, "http": code}),
                encoding="utf-8",
            )
            tmp.replace(cache_path)
        except Exception:
            pass
        return writable, code


def cmd_fetch_bundle() -> int:
    with CcClient() as client:
        if not client.authenticate():
            print(json.dumps({"ok": False, "error": "auth_failed"}))
            return 2
        _, status = client.get_json("/status")
        _, devices = client.get_json("/devices")
        _, modes = client.get_json("/modes")
        _, modes_active = client.get_json("/modes-active")
        writable, whttp = client.probe_write_cached()
        print(
            json.dumps(
                {
                    "ok": status is not None,
                    "status": status,
                    "devices": devices,
                    "modes": modes,
                    "modes_active": modes_active,
                    "write_access": writable,
                    "write_http": whttp,
                    "auth": client.auth_method,
                }
            )
        )
        return 0 if status is not None else 2


def cmd_probe_write() -> int:
    with CcClient() as client:
        if not client.authenticate():
            print(json.dumps({"write_access": None, "http": 0, "error": "auth_failed"}))
            return 2
        # Explicit probe-write always hits the API (and refreshes cache).
        writable, code = client.probe_write()
        try:
            cache_path = Path(
                _env("WAYBAR_CC_WRITE_CACHE")
                or str(
                    Path(os.environ.get("XDG_CACHE_HOME", str(Path.home() / ".cache")))
                    / "waybar"
                    / "coolercontrol-write.json"
                )
            )
            cache_path.parent.mkdir(parents=True, exist_ok=True)
            tmp = cache_path.with_suffix(f".tmp.{os.getpid()}")
            tmp.write_text(
                json.dumps({"write_access": writable, "http": code}),
                encoding="utf-8",
            )
            tmp.replace(cache_path)
        except Exception:
            pass
        print(json.dumps({"write_access": writable, "http": code}))
        return 0


def _mode_list(modes_obj: Any) -> list[dict[str, Any]]:
    if not isinstance(modes_obj, dict):
        return []
    modes = modes_obj.get("modes") or []
    return [m for m in modes if isinstance(m, dict) and m.get("uid")]


def cmd_list_modes() -> int:
    with CcClient() as client:
        if not client.authenticate():
            print(json.dumps({"ok": False, "error": "auth_failed"}))
            return 2
        _, modes = client.get_json("/modes")
        _, active = client.get_json("/modes-active")
        print(
            json.dumps(
                {
                    "ok": True,
                    "modes": _mode_list(modes),
                    "modes_active": active,
                }
            )
        )
        return 0


def cmd_activate(uid: str) -> int:
    with CcClient() as client:
        if not client.authenticate():
            print(json.dumps({"ok": False, "error": "auth_failed"}))
            return 2
        writable, _ = client.probe_write()
        if writable is not True:
            print(json.dumps({"ok": False, "error": "read_only", "write_access": writable}))
            return 3
        code, body = client.request("POST", f"/modes-active/{uid}")
        print(json.dumps({"ok": code == 200, "http": code, "uid": uid, "body": body[:200]}))
        return 0 if code == 200 else 4


def cmd_cycle(direction: str) -> int:
    direction = direction if direction in ("next", "prev") else "next"
    with CcClient() as client:
        if not client.authenticate():
            print(json.dumps({"ok": False, "error": "auth_failed"}))
            return 2
        writable, _ = client.probe_write()
        if writable is not True:
            print(json.dumps({"ok": False, "error": "read_only", "write_access": False}))
            return 3
        _, modes_obj = client.get_json("/modes")
        _, active = client.get_json("/modes-active")
        modes = _mode_list(modes_obj)
        if not modes:
            print(json.dumps({"ok": False, "error": "no_modes"}))
            return 5
        current = None
        if isinstance(active, dict):
            current = active.get("current_mode_uid")
        uids = [str(m["uid"]) for m in modes]
        names = {str(m["uid"]): str(m.get("name") or m["uid"]) for m in modes}
        if current in uids:
            idx = uids.index(str(current))
        else:
            idx = -1 if direction == "next" else 0
        if direction == "next":
            idx = (idx + 1) % len(uids)
        else:
            idx = (idx - 1) % len(uids)
        target = uids[idx]
        code, _ = client.request("POST", f"/modes-active/{target}")
        print(
            json.dumps(
                {
                    "ok": code == 200,
                    "http": code,
                    "uid": target,
                    "name": names.get(target, target),
                    "direction": direction,
                }
            )
        )
        return 0 if code == 200 else 4


def main(argv: list[str]) -> int:
    if len(argv) < 2:
        print(
            "usage: coolercontrol-api.py fetch-bundle|probe-write|list-modes|cycle next|prev|activate UID",
            file=sys.stderr,
        )
        return 1
    cmd = argv[1]
    if cmd == "fetch-bundle":
        return cmd_fetch_bundle()
    if cmd == "probe-write":
        return cmd_probe_write()
    if cmd == "list-modes":
        return cmd_list_modes()
    if cmd == "cycle":
        return cmd_cycle(argv[2] if len(argv) > 2 else "next")
    if cmd == "activate":
        if len(argv) < 3:
            print("activate requires mode uid", file=sys.stderr)
            return 1
        return cmd_activate(argv[2])
    print(f"unknown command: {cmd}", file=sys.stderr)
    return 1


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
