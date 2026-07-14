#!/usr/bin/env bash
# Safe CoolerControl auth self-check (never prints credentials).
set -euo pipefail
: "${WAYBAR_HOME:=${XDG_CONFIG_HOME:-$HOME/.config}/waybar}"
: "${WAYBAR_SCRIPTS:=$WAYBAR_HOME/scripts}"
. "$WAYBAR_SCRIPTS/lib/waybar-settings.sh"

api=$(waybar_settings_get '.services.coolercontrol.api_url' 'http://127.0.0.1:11987')
api="${api%/}"
base="${api/https:/http:}"
user=$(waybar_settings_get '.services.coolercontrol.ui_user' 'CCAdmin')
pass=$(waybar_settings_get '.services.coolercontrol.ui_pass' '')
token=$(waybar_settings_get '.services.coolercontrol.token' '')

echo "daemon: $(pgrep -x coolercontrold >/dev/null && echo up || echo down)"
echo "secrets: ui_pass=$([ -n "$pass" ] && [ "$pass" != CHANGE_ME ] && echo yes || echo no) token=$([ -n "$token" ] && [[ "$token" == cc_* ]] && echo "yes(len=${#token})" || echo no)"

unauth=$(curl -sS -m 3 -o /dev/null -w '%{http_code}' "$base/status" || true)
echo "unauth /status: $unauth"

td=$(mktemp -d /tmp/cc-check.XXXXXX)
chmod 700 "$td"
cleanup() {
  rm -rf "$td"
  unset pass token
}
trap cleanup EXIT

bearer_status=skip
bearer_devices=skip
login=skip
login_reject=skip
cookie_status=skip

if [[ -n "$token" && "$token" == cc_* ]]; then
  # Header via @file so the token never appears on curl argv.
  printf 'Authorization: Bearer %s\n' "$token" >"$td/bearer.hdr"
  chmod 600 "$td/bearer.hdr"
  bearer_status=$(curl -sS -m 5 -o "$td/status.json" -w '%{http_code}' -H "@$td/bearer.hdr" "$base/status" || true)
  bearer_devices=$(curl -sS -m 5 -o "$td/devices.json" -w '%{http_code}' -H "@$td/bearer.hdr" "$base/devices" || true)
fi
unset token

if [[ -n "$pass" && "$pass" != CHANGE_ME ]]; then
  cat >"$td/netrc" <<NETRC
machine 127.0.0.1
login $user
password $pass
machine localhost
login $user
password $pass
NETRC
  chmod 600 "$td/netrc"
  cat >"$td/netrc.bad" <<NETRC
machine 127.0.0.1
login $user
password invalid-auth-check
machine localhost
login $user
password invalid-auth-check
NETRC
  chmod 600 "$td/netrc.bad"
  login=$(curl -sS -m 5 -o /dev/null -w '%{http_code}' -X POST --netrc-file "$td/netrc" -c "$td/cookies" "$base/login" || true)
  login_reject=$(curl -sS -m 5 -o /dev/null -w '%{http_code}' -X POST --netrc-file "$td/netrc.bad" "$base/login" || true)
  if [[ "$login" == 200 ]]; then
    cookie_status=$(curl -sS -m 5 -o "$td/status-cookie.json" -w '%{http_code}' -b "$td/cookies" -c "$td/cookies" "$base/status" || true)
  fi
fi

echo "bearer /status: $bearer_status"
echo "bearer /devices: $bearer_devices"
echo "POST /login: $login"
echo "POST /login reject: $login_reject"
echo "cookie /status: $cookie_status"

python3 - "$td" <<'PY'
import json, sys
from pathlib import Path
td = Path(sys.argv[1])
for label, name in (("bearer_status","status.json"), ("cookie_status","status-cookie.json"), ("bearer_devices","devices.json")):
    p = td / name
    if not p.is_file() or p.stat().st_size == 0:
        continue
    data = json.loads(p.read_text())
    if isinstance(data, dict) and data.get("error"):
        print(f"{label}: ERROR {data.get('error')}")
        continue
    if label.endswith("devices"):
        devs = data.get("devices") or []
        print(f"{label}: OK devices={len(devs)} {[d.get('name') for d in devs[:8]]}")
    else:
        devs = data.get("devices") or []
        temps = chans = 0
        for d in devs:
            latest = (d.get("status_history") or [None])[-1] or {}
            temps += len(latest.get("temps") or [])
            chans += len(latest.get("channels") or [])
        print(f"{label}: OK devices={len(devs)} temps={temps} channels={chans}")
PY

# Module dry-run with writable cache
export XDG_CACHE_HOME="$td/cache"
mkdir -p "$XDG_CACHE_HOME"
mod=$("$WAYBAR_SCRIPTS/services/coolercontrol/coolercontrol-status.sh" --refresh)
python3 -c 'import json,sys; d=json.loads(sys.argv[1]); print("module:", d.get("class"), repr(d.get("text")));
[print(" ",l) for l in (d.get("tooltip") or "").splitlines()[:12]]' "$mod"

ok=1
[[ "$bearer_status" == 200 || "$cookie_status" == 200 ]] || ok=0
[[ "$login" == skip || ("$login" == 200 && "$login_reject" != 200) ]] || ok=0
if [[ "$ok" -eq 1 ]]; then
  echo "RESULT: OK — credentials work for Waybar monitoring"
  exit 0
fi
echo "RESULT: FAIL — see HTTP codes above"
exit 1
