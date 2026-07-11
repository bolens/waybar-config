#!/usr/bin/env bash
# Dump CoolerControl /handshake, /devices, /status shapes for local API mapping.
# Uses secrets: Bearer token preferred; falls back to POST /login if token fails. Never prints credentials.
#
# Usage:
#   scripts/services/coolercontrol/coolercontrol-api-dump.sh
#   scripts/services/coolercontrol/coolercontrol-api-dump.sh --write  # → ~/.cache/waybar/coolercontrol-api-dump.json
set -euo pipefail
: "${WAYBAR_HOME:=${XDG_CONFIG_HOME:-$HOME/.config}/waybar}"
: "${WAYBAR_SCRIPTS:=$WAYBAR_HOME/scripts}"
. "$WAYBAR_SCRIPTS/lib/waybar-settings.sh"

WRITE=0
[[ "${1:-}" == "--write" ]] && WRITE=1

api_url=$(waybar_settings_get '.services.coolercontrol.api_url' 'http://127.0.0.1:11987')
api_url="${api_url%/}"
ui_user=$(waybar_settings_get '.services.coolercontrol.ui_user' 'CCAdmin')
ui_pass=$(waybar_settings_get '.services.coolercontrol.ui_pass' '')
token=$(waybar_settings_get '.services.coolercontrol.token' '')

if [[ -z "$token" || "$token" == "null" || "$token" == "CHANGE_ME" ]]; then token=""; fi
if [[ -z "$ui_pass" || "$ui_pass" == "null" || "$ui_pass" == "CHANGE_ME" ]]; then ui_pass=""; fi

if [[ -z "$token" && -z "$ui_pass" ]]; then
  echo "No CoolerControl credentials in data/waybar-secrets.jsonc" >&2
  echo "Run: sudo $WAYBAR_SCRIPTS/services/coolercontrol/coolercontrol-set-ui-pass.sh" >&2
  exit 1
fi

out=$(
  CC_API_URL="$api_url" CC_UI_USER="$ui_user" CC_UI_PASS="$ui_pass" CC_TOKEN="$token" python3 <<'PY'
import json, os, subprocess, tempfile
from pathlib import Path

api = os.environ["CC_API_URL"].rstrip("/")
user = os.environ.get("CC_UI_USER", "CCAdmin")
password = os.environ.get("CC_UI_PASS", "")
token = os.environ.get("CC_TOKEN", "")
base = api.replace("https://", "http://") if api.startswith("https://") else api

def curl(args):
    r = subprocess.run(args, capture_output=True, text=True, timeout=8)
    return r

def req(method, path, headers=None, jar=None, netrc=None):
    args = ["curl", "-sS", "--max-time", "5", "-w", "\n%{http_code}", "-X", method]
    if netrc:
        args += ["--netrc-file", netrc]
    if jar:
        args += ["-b", jar, "-c", jar]
    if headers:
        for h in headers:
            args += ["-H", h]
    args.append(f"{base}{path}")
    r = curl(args)
    body, _, code = (r.stdout or "").rpartition("\n")
    try:
        code_i = int(code.strip() or "0")
    except ValueError:
        code_i = 0
    return code_i, body

headers = None
jar = None
td = None
auth = "none"
try:
    # Prefer Bearer; fall back to UI password login if token missing or /status fails.
    if token:
        headers = [f"Authorization: Bearer {token}"]
        st_try, st_body = req("GET", "/status", headers=headers)
        if st_try == 200 and st_body.strip():
            auth = "bearer"
        else:
            headers = None
            token = ""  # force password path below
    if auth != "bearer" and password:
        td = tempfile.TemporaryDirectory(prefix="cc-dump.")
        netrc = Path(td.name) / "netrc"
        jar = str(Path(td.name) / "cookies")
        netrc.write_text(
            f"machine 127.0.0.1\nlogin {user}\npassword {password}\n"
            f"machine localhost\nlogin {user}\npassword {password}\n"
        )
        netrc.chmod(0o600)
        code, _ = req("POST", "/login", netrc=str(netrc), jar=jar)
        if code != 200:
            print(json.dumps({"ok": False, "error": f"POST /login HTTP {code}", "auth": "basic"}, indent=2))
            raise SystemExit(1)
        auth = "basic+cookie"
    elif auth != "bearer":
        print(json.dumps({"ok": False, "error": "no usable credentials after token failure", "auth": "none"}, indent=2))
        raise SystemExit(1)

    hs_c, hs_b = req("GET", "/handshake", headers=headers, jar=jar)
    st_c, st_b = req("GET", "/status", headers=headers, jar=jar)
    dv_c, dv_b = req("GET", "/devices", headers=headers, jar=jar)

    def parse(body):
        try:
            return json.loads(body) if body.strip() else None
        except Exception:
            return {"_raw_preview": body[:200]}

    status = parse(st_b)
    devices = parse(dv_b)

    # Compact map for humans / fixtures (no secrets)
    summary = {
        "ok": st_c == 200 and dv_c == 200,
        "api_base": base,
        "auth": auth,
        "http": {"handshake": hs_c, "status": st_c, "devices": dv_c},
        "handshake": parse(hs_b),
        "status_device_count": len((status or {}).get("devices") or []) if isinstance(status, dict) else None,
        "devices_count": len((devices or {}).get("devices") or []) if isinstance(devices, dict) else None,
        "device_index": [],
        "status": status,
        "devices": devices,
    }
    if isinstance(devices, dict):
        for d in devices.get("devices") or []:
            if not isinstance(d, dict):
                continue
            summary["device_index"].append({
                "uid": d.get("uid"),
                "name": d.get("name"),
                "d_type": d.get("d_type"),
                "type_index": d.get("type_index"),
            })
    if isinstance(status, dict):
        for d in status.get("devices") or []:
            if not isinstance(d, dict):
                continue
            hist = d.get("status_history") or []
            latest = hist[-1] if hist else {}
            temps = [
                {"name": t.get("name"), "temp": t.get("temp")}
                for t in (latest.get("temps") or []) if isinstance(t, dict)
            ]
            channels = [
                {k: ch.get(k) for k in ("name", "rpm", "duty", "watts", "freq") if ch.get(k) is not None}
                for ch in (latest.get("channels") or []) if isinstance(ch, dict)
            ]
            summary.setdefault("status_preview", []).append({
                "uid": d.get("uid"),
                "d_type": d.get("d_type"),
                "temps": temps[:8],
                "channels": channels[:8],
            })

    print(json.dumps(summary, indent=2))
    raise SystemExit(0 if summary["ok"] else 2)
finally:
    if td is not None:
        td.cleanup()
PY
)

printf '%s\n' "$out"
if [[ "$WRITE" -eq 1 ]]; then
  cache="${XDG_CACHE_HOME:-$HOME/.cache}/waybar/coolercontrol-api-dump.json"
  mkdir -p "$(dirname "$cache")"
  printf '%s\n' "$out" >"$cache"
  chmod 600 "$cache"
  echo "Wrote $cache" >&2
fi
