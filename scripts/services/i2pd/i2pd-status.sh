#!/usr/bin/env bash
# i2pd Status module for Waybar.
set -eu
: "${WAYBAR_HOME:=${XDG_CONFIG_HOME:-$HOME/.config}/waybar}"
: "${WAYBAR_SCRIPTS:=$WAYBAR_HOME/scripts}"
script_dir="${0%/*}"
. "$WAYBAR_SCRIPTS/lib/waybar-cache-helpers.sh"

cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/waybar"
cache_file="$cache_dir/i2pd-status.json"
lock_dir="$cache_dir/i2pd-status.lock.d"
ttl="$(waybar_module_interval i2pd 30)"
stale_lock_ttl=20

mkdir -p "$cache_dir"

script_dir="${0%/*}"
. "$WAYBAR_SCRIPTS/lib/waybar-cache-helpers.sh"
. "$WAYBAR_SCRIPTS/lib/waybar-settings.sh"

if [ "${1:-}" != "--refresh" ]; then
  if serve_cache_or_refresh "$cache_file" "$ttl" "$lock_dir" "$stale_lock_ttl"; then
    exit 0
  fi
  emit_waybar_json "󱚽 ..." "Refreshing i2pd status in background" "disabled"
  exit 0
fi

# Check service status
i2pd_service=$(waybar_settings_get '.services.i2pd.service_name' 'i2pd.service')
service_active=0
if systemctl is-active -q "$i2pd_service" 2>/dev/null; then
  service_active=1
elif pgrep -x i2pd >/dev/null 2>&1 || pgrep -x i2pd-daemon >/dev/null 2>&1; then
  service_active=1
fi

if [ "$service_active" -eq 0 ]; then
  json=$(emit_waybar_json "󱚽 Off" "i2pd router daemon is offline" "offline")
  printf '%s\n' "$json"
  printf '%s\n' "$json" >"$cache_file"
  exit 0
fi

# Fetch and parse Web Console
user=$(waybar_settings_get '.services.i2pd.console_user' 'i2pd')
# Prefer env, then secrets overlay / settings (secrets via waybar_settings_get merge)
pass="${WAYBAR_I2PD_CONSOLE_PASS:-$(waybar_settings_get '.services.i2pd.console_pass' '')}"
console_url=$(waybar_settings_get '.services.i2pd.console_url' 'http://127.0.0.1:7070/')

# Auth via temp netrc (0600) so the password never appears on curl argv (/proc cmdline).
web_data=""
if [ -n "$pass" ]; then
  _i2pd_auth=$(mktemp -d "${TMPDIR:-/tmp}/waybar-i2pd-auth.XXXXXX")
  chmod 700 "$_i2pd_auth"
  # shellcheck disable=SC2064
  trap 'rm -rf "${_i2pd_auth:-}"' EXIT
  I2PD_NETRC_PATH="$_i2pd_auth/netrc" I2PD_CONSOLE_USER="$user" I2PD_CONSOLE_PASS="$pass" python3 <<'PY'
import os
from pathlib import Path
path = Path(os.environ["I2PD_NETRC_PATH"])
user = os.environ["I2PD_CONSOLE_USER"]
password = os.environ["I2PD_CONSOLE_PASS"]
path.write_text(
    f"machine 127.0.0.1\nlogin {user}\npassword {password}\n"
    f"machine localhost\nlogin {user}\npassword {password}\n"
)
path.chmod(0o600)
PY
  web_data=$(timeout 3 curl --netrc-file "$_i2pd_auth/netrc" -H "Host: localhost:7070" -s "$console_url" || true)
  rm -rf "$_i2pd_auth"
  unset _i2pd_auth
  trap - EXIT
else
  web_data=$(timeout 3 curl -H "Host: localhost:7070" -s "$console_url" || true)
fi
unset pass

if [ -z "$web_data" ]; then
  json=$(emit_waybar_json "󱚽 On" "i2pd running (Web Console unreachable)" "normal")
  printf '%s\n' "$json"
  printf '%s\n' "$json" >"$cache_file"
  exit 0
fi

# Parse parameters
uptime_str=$(echo "$web_data" | sed -n 's/.*<b>Uptime:<\/b> \([^<]*\).*/\1/p' | sed -n '1p' || echo "Unknown")
net_status=$(echo "$web_data" | sed -n 's/.*<b>Network status:<\/b> \([^<]*\).*/\1/p' | sed -n '1p' || echo "Unknown")
client_tunnels=$(echo "$web_data" | sed -n 's/.*<b>Client Tunnels:<\/b> \([0-9]*\).*/\1/p' | sed -n '1p' || echo "0")
transit_tunnels=$(echo "$web_data" | sed -n 's/.*<b>Transit Tunnels:<\/b> \([0-9]*\).*/\1/p' | sed -n '1p' || echo "0")

# Clean output whitespace
uptime_str=$(echo "$uptime_str" | xargs)
net_status=$(echo "$net_status" | xargs)
client_tunnels=$(echo "$client_tunnels" | xargs)
transit_tunnels=$(echo "$transit_tunnels" | xargs)

# Class determination
class="normal"
case "$(echo "$net_status" | tr '[:upper:]' '[:lower:]')" in
  *testing* | *clock* | *unknown*)
    class="warning"
    ;;
  *disconnected* | *error*)
    class="critical"
    ;;
esac

text="󱚽 $client_tunnels/$transit_tunnels"
tooltip=$(printf 'i2pd Router Console\n\nNetwork Status: %s\nUptime: %s\n\nClient Tunnels: %s\nTransit Tunnels: %s\n\nLeft: open web console · Right: restart service · Middle: refresh' \
  "$net_status" "$uptime_str" "$client_tunnels" "$transit_tunnels")

json=$(emit_waybar_json "$text" "$tooltip" "$class")
printf '%s\n' "$json"

tmp_cache="$cache_file.tmp.$$"
printf '%s\n' "$json" >"$tmp_cache"
mv -f "$tmp_cache" "$cache_file"

# Signal Waybar to refresh the module UI
"$WAYBAR_SCRIPTS/lib/waybar-signal.sh" i2pd
