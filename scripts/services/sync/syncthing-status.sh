#!/usr/bin/env sh
# Syncthing status module for Waybar.
set -eu
: "${WAYBAR_HOME:=${XDG_CONFIG_HOME:-$HOME/.config}/waybar}"
: "${WAYBAR_SCRIPTS:=$WAYBAR_HOME/scripts}"
script_dir="${0%/*}"
. "$WAYBAR_SCRIPTS/lib/waybar-cache-helpers.sh"

cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/waybar"
cache_file="$cache_dir/syncthing-status.json"
lock_dir="$cache_dir/syncthing-status.lock.d"
ttl="$(waybar_module_interval syncthing 30)"
stale_lock_ttl=20

mkdir -p "$cache_dir"

script_dir="${0%/*}"
. "$WAYBAR_SCRIPTS/lib/waybar-cache-helpers.sh"

if [ "${1:-}" != "--refresh" ]; then
  if serve_cache_or_refresh "$cache_file" "$ttl" "$lock_dir" "$stale_lock_ttl"; then
    exit 0
  fi
  emit_waybar_json "󰛵 ..." "Refreshing Syncthing status in background" "disabled"
  exit 0
fi

# Locate Syncthing config
config_path=""
for p in "$HOME/.local/state/syncthing/config.xml" "$HOME/.config/syncthing/config.xml"; do
  if [ -f "$p" ]; then
    config_path="$p"
    break
  fi
done

if [ -z "$config_path" ] || ! command -v jq >/dev/null 2>&1 || ! command -v curl >/dev/null 2>&1; then
  # No configuration or required tools, but check if the service is running at least
  if pgrep -x syncthing >/dev/null 2>&1; then
    emit_waybar_json "󰛵 On" "Syncthing is running (GUI/API details unavailable)" "normal"
  else
    emit_waybar_json "󰛵 Off" "Syncthing is offline" "offline"
  fi
  exit 0
fi

# Parse API key and GUI address
api_key=$(sed -n '/<gui /,/<\/gui>/p' "$config_path" | grep -oP '<apikey>\K[^<]+' || true)
if [ -z "$api_key" ]; then
  api_key=$(sed -n '/<gui /,/<\/gui>/p' "$config_path" | sed -n 's/.*<apikey>\(.*\)<\/apikey>.*/\1/p' || true)
fi

gui_address=$(sed -n '/<gui /,/<\/gui>/p' "$config_path" | grep -oP '<address>\K[^<]+' || true)
if [ -z "$gui_address" ]; then
  gui_address=$(sed -n '/<gui /,/<\/gui>/p' "$config_path" | sed -n 's/.*<address>\(.*\)<\/address>.*/\1/p' || true)
fi

# Fallbacks
[ -n "$api_key" ] || api_key=""
[ -n "$gui_address" ] || gui_address="127.0.0.1:8384"

# Handle dynamic port/protocol (e.g. 127.0.0.1:8384 or dynamic+https, etc.)
# Strip protocol prefix if present
gui_host_port=$(echo "$gui_address" | sed -E 's|https?://||')
if sed -n '/<gui /,/<\/gui>/p' "$config_path" | grep -qi 'tls="true"'; then
  protocol="https"
else
  protocol="http"
fi

api_url="$protocol://$gui_host_port/rest"

# API key via curl -H @file (0600) so it never appears on argv (/proc cmdline).
_st_auth=$(mktemp -d "${TMPDIR:-/tmp}/waybar-st-auth.XXXXXX")
chmod 700 "$_st_auth"
# shellcheck disable=SC2064
trap 'rm -rf "${_st_auth:-}"' EXIT
printf 'X-API-Key: %s\n' "$api_key" >"$_st_auth/hdr"
chmod 600 "$_st_auth/hdr"
unset api_key

syncthing_curl() {
  timeout 3 curl -k -s -H "@$_st_auth/hdr" "$@" || true
}

# Query system status
sys_status=$(syncthing_curl "$api_url/system/status")
if [ -z "$sys_status" ] && [ "$protocol" = "https" ]; then
  # Try fallback to HTTP
  protocol="http"
  api_url="$protocol://$gui_host_port/rest"
  sys_status=$(syncthing_curl "$api_url/system/status")
fi

if [ -z "$sys_status" ]; then
  # Check if process is running
  if pgrep -x syncthing >/dev/null 2>&1; then
    json=$(emit_waybar_json "󰛵 Stalled" "Syncthing process active but API unreachable" "warning")
  else
    json=$(emit_waybar_json "󰛵 Off" "Syncthing daemon is offline" "offline")
  fi
  printf '%s\n' "$json"
  printf '%s\n' "$json" >"$cache_file"
  rm -rf "$_st_auth"
  unset _st_auth
  trap - EXIT
  exit 0
fi

# Extract general system status info
uptime_s=$(echo "$sys_status" | jq -r '.uptime // 0')
my_id=$(echo "$sys_status" | jq -r '.myID // "unknown"')

# Query active connections
connections_json=$(syncthing_curl "$api_url/system/connections")
connected_devices=0
total_devices=0
device_tooltip=""

if [ -n "$connections_json" ]; then
  total_devices=$(echo "$connections_json" | jq '.connections | length' 2>/dev/null || echo 0)
  connected_devices=$(echo "$connections_json" | jq '[.connections[] | select(.connected)] | length' 2>/dev/null || echo 0)

  # Format connections summary for tooltip
  device_tooltip=$(echo "$connections_json" | jq -r '
    .connections | to_entries | map(
      "• " + (.key[0:7]) + "... " + (if .value.connected then "Connected (" + (.value.type // "unknown") + ")" else "Disconnected" end)
    ) | join("\n")
  ' 2>/dev/null || echo "")
fi

uptime_m=$((uptime_s / 60))
uptime_h=$((uptime_m / 60))
uptime_d=$((uptime_h / 24))

if [ "$uptime_d" -gt 0 ]; then
  uptime_str="${uptime_d}d $((uptime_h % 24))h"
elif [ "$uptime_h" -gt 0 ]; then
  uptime_str="${uptime_h}h $((uptime_m % 60))m"
else
  uptime_str="${uptime_m}m"
fi

text="󰛵 $connected_devices/$total_devices"
class="normal"
if [ "$connected_devices" -eq 0 ] && [ "$total_devices" -gt 0 ]; then
  class="warning"
fi

tooltip=$(printf 'Syncthing Status\n\nDaemon: Online (Uptime: %s)\nLocal Device ID: %s\nGUI Address: %s\n\nConnected Devices: %s / %s\n%s\n\nLeft: open Web GUI · Right: restart service · Middle: refresh' \
  "$uptime_str" "${my_id:0:15}..." "$protocol://$gui_host_port" "$connected_devices" "$total_devices" "$device_tooltip")

json=$(emit_waybar_json "$text" "$tooltip" "$class")
printf '%s\n' "$json"

tmp_cache="$cache_file.tmp.$$"
printf '%s\n' "$json" >"$tmp_cache"
mv -f "$tmp_cache" "$cache_file"

# Signal Waybar to refresh the module UI
"$WAYBAR_SCRIPTS/lib/waybar-signal.sh" syncthing

rm -rf "${_st_auth:-}"
unset _st_auth
trap - EXIT
