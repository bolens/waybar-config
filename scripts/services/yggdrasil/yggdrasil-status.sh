#!/usr/bin/env bash
# Yggdrasil mesh status module for Waybar.
set -eu
: "${WAYBAR_HOME:=${XDG_CONFIG_HOME:-$HOME/.config}/waybar}"
: "${WAYBAR_SCRIPTS:=$WAYBAR_HOME/scripts}"
. "$WAYBAR_SCRIPTS/lib/waybar-cache-helpers.sh"
. "$WAYBAR_SCRIPTS/lib/waybar-settings.sh"

cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/waybar"
cache_file="$cache_dir/yggdrasil-status.json"
lock_dir="$cache_dir/yggdrasil-status.lock.d"
ttl="$(waybar_module_interval yggdrasil 30)"
stale_lock_ttl=20

mkdir -p "$cache_dir"

finish_refresh() {
  local json="$1"
  printf '%s\n' "$json"
  local tmp="$cache_file.tmp.$$"
  printf '%s\n' "$json" >"$tmp"
  mv -f "$tmp" "$cache_file"
  "$WAYBAR_SCRIPTS/lib/waybar-signal.sh" yggdrasil
  exit 0
}

if [ "${1:-}" != "--refresh" ]; then
  if serve_cache_or_refresh "$cache_file" "$ttl" "$lock_dir" "$stale_lock_ttl"; then
    exit 0
  fi
  emit_waybar_json "󰙨 ..." "Refreshing Yggdrasil status in background" "disabled"
  exit 0
fi

service_name=$(waybar_settings_get '.services.yggdrasil.service_name' 'yggdrasil.service')
endpoint=$(waybar_settings_get '.services.yggdrasil.endpoint' '/var/run/yggdrasil.sock')
# Normalize socket path → yggdrasilctl endpoint (JSONC cannot store unix:///… — // is a comment).
case "$endpoint" in
  unix:* | tcp:* | "") ;;
  /*) endpoint="unix://$endpoint" ;;
esac

service_active=0
if systemctl is-active -q "$service_name" 2>/dev/null; then
  service_active=1
elif pgrep -x yggdrasil >/dev/null 2>&1; then
  service_active=1
fi

# Offline (or not installed) before needing yggdrasilctl — CI stubs service inactive first.
if [ "$service_active" -eq 0 ]; then
  finish_refresh "$(emit_waybar_json "󰙨 Off" "Yggdrasil daemon is offline" "offline")"
fi

if ! command -v yggdrasilctl >/dev/null 2>&1; then
  emit_disconnected "Yggdrasil not installed" "$cache_file"
fi

ygg_cmd=(yggdrasilctl -json)
if [ -n "$endpoint" ]; then
  ygg_cmd+=(-endpoint="$endpoint")
fi

self_json=$(timeout 3 "${ygg_cmd[@]}" getSelf 2>/dev/null || true)
peers_json=$(timeout 3 "${ygg_cmd[@]}" getPeers 2>/dev/null || true)
# yggdrasilctl logs fatal errors to stdout; accept only JSON objects.
if ! printf '%s' "$self_json" | jq -e 'type == "object"' >/dev/null 2>&1; then
  self_json=""
fi
if ! printf '%s' "$peers_json" | jq -e 'type == "object"' >/dev/null 2>&1; then
  peers_json='{}'
fi

if [ -z "$self_json" ]; then
  finish_refresh "$(emit_waybar_json "󰙨 On" "Yggdrasil running (admin socket unreachable)\nEndpoint: $endpoint\nTip: add your user to the yggdrasil group" "warning")"
fi

parsed=$(jq -nc --argjson self "$self_json" --argjson raw "$peers_json" '
  def peer_map:
    if type != "object" then {}
    elif (.peers | type) == "object" then .peers
    else . end;
  ($raw | peer_map | to_entries
    | map(select(.value | type == "object"))
    | length) as $count
  | {
      address: ($self.address // "unknown"),
      subnet: ($self.subnet // ""),
      coords: (if ($self.coords // null) == null then "" else ($self.coords | tostring) end),
      peers: $count
    }
')

address=$(printf '%s' "$parsed" | jq -r '.address')
subnet=$(printf '%s' "$parsed" | jq -r '.subnet')
coords=$(printf '%s' "$parsed" | jq -r '.coords')
peer_count=$(printf '%s' "$parsed" | jq -r '.peers')

class="normal"
if [ "$peer_count" = "0" ]; then
  class="warning"
fi

text="󰙨 $peer_count"
tooltip=$(printf 'Yggdrasil\n\nAddress: %s\nSubnet: %s\nCoords: %s\nPeers: %s\n\nLeft: peer list · Right: restart service · Middle: refresh' \
  "$address" "${subnet:-n/a}" "${coords:-n/a}" "$peer_count")

finish_refresh "$(emit_waybar_json "$text" "$tooltip" "$class")"
