#!/usr/bin/env bash
# IPFS (Kubo) status module for Waybar.
set -eu
: "${WAYBAR_HOME:=${XDG_CONFIG_HOME:-$HOME/.config}/waybar}"
: "${WAYBAR_SCRIPTS:=$WAYBAR_HOME/scripts}"
. "$WAYBAR_SCRIPTS/lib/waybar-cache-helpers.sh"
. "$WAYBAR_SCRIPTS/lib/waybar-settings.sh"

cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/waybar"
cache_file="$cache_dir/ipfs-status.json"
lock_dir="$cache_dir/ipfs-status.lock.d"
ttl="$(waybar_module_interval ipfs 30)"
stale_lock_ttl=20

mkdir -p "$cache_dir"

finish_refresh() {
  local json="$1"
  printf '%s\n' "$json"
  local tmp="$cache_file.tmp.$$"
  printf '%s\n' "$json" >"$tmp"
  mv -f "$tmp" "$cache_file"
  "$WAYBAR_SCRIPTS/lib/waybar-signal.sh" ipfs
  exit 0
}

if [ "${1:-}" != "--refresh" ]; then
  if serve_cache_or_refresh "$cache_file" "$ttl" "$lock_dir" "$stale_lock_ttl"; then
    exit 0
  fi
  emit_waybar_json "󰡨 ..." "Refreshing IPFS status in background" "disabled"
  exit 0
fi

if ! command -v ipfs >/dev/null 2>&1 && ! command -v curl >/dev/null 2>&1; then
  emit_disconnected "IPFS (kubo) not installed" "$cache_file"
fi

service_name=$(waybar_settings_get '.services.ipfs.service_name' 'ipfs.service')
api_url=$(waybar_settings_get '.services.ipfs.api_url' 'http://127.0.0.1:5001')
api_url="${api_url%/}"

service_active=0
if systemctl is-active -q "$service_name" 2>/dev/null; then
  service_active=1
elif systemctl --user is-active -q "$service_name" 2>/dev/null; then
  service_active=1
elif pgrep -x ipfs >/dev/null 2>&1; then
  service_active=1
fi

if [ "$service_active" -eq 0 ]; then
  # API may still answer even if unit naming differs — try a quick probe.
  id_probe=$(timeout 2 curl -s -X POST "$api_url/api/v0/id" 2>/dev/null || true)
  if [ -z "$id_probe" ]; then
    finish_refresh "$(emit_waybar_json "󰡨 Off" "IPFS daemon is offline" "offline")"
  fi
  id_json=$id_probe
else
  id_json=""
fi

ipfs_api() {
  timeout 3 curl -s -X POST "$@" || true
}

[ -n "${id_json:-}" ] || id_json=$(ipfs_api "$api_url/api/v0/id")
if [ -z "$id_json" ]; then
  if [ "$service_active" -eq 1 ]; then
    finish_refresh "$(emit_waybar_json "󰡨 On" "IPFS running (API unreachable at $api_url)" "warning")"
  else
    finish_refresh "$(emit_waybar_json "󰡨 Off" "IPFS daemon is offline" "offline")"
  fi
fi

peers_json=$(ipfs_api "$api_url/api/v0/swarm/peers")
bw_json=$(ipfs_api "$api_url/api/v0/stats/bw")
[ -n "$peers_json" ] || peers_json='null'
[ -n "$bw_json" ] || bw_json='null'

parsed=$(jq -n \
  --argjson id "$id_json" \
  --argjson peers "$peers_json" \
  --argjson bw "$bw_json" '
  def human:
    if . == null then "n/a"
    elif . < 1024 then "\(.|floor) B"
    elif . < 1048576 then "\((. / 1024 * 10 | floor) / 10) KiB"
    elif . < 1073741824 then "\((. / 1048576 * 10 | floor) / 10) MiB"
    else "\((. / 1073741824 * 10 | floor) / 10) GiB"
    end;
  {
    peer_id: ($id.ID // "unknown"),
    agent: ($id.AgentVersion // ""),
    peers: (if ($peers.Peers // null) == null then 0 else ($peers.Peers | length) end),
    rate_in: (($bw.RateIn // 0) | human),
    rate_out: (($bw.RateOut // 0) | human),
    total_in: (($bw.TotalIn // 0) | human),
    total_out: (($bw.TotalOut // 0) | human)
  }
')

peer_id=$(printf '%s' "$parsed" | jq -r '.peer_id')
agent=$(printf '%s' "$parsed" | jq -r '.agent')
peer_count=$(printf '%s' "$parsed" | jq -r '.peers')
rate_in=$(printf '%s' "$parsed" | jq -r '.rate_in')
rate_out=$(printf '%s' "$parsed" | jq -r '.rate_out')
total_in=$(printf '%s' "$parsed" | jq -r '.total_in')
total_out=$(printf '%s' "$parsed" | jq -r '.total_out')

# Shorten peer id for tooltip readability
short_id="$peer_id"
if [ "${#peer_id}" -gt 20 ]; then
  short_id="${peer_id:0:8}…${peer_id: -6}"
fi

class="normal"
if [ "$peer_count" = "0" ]; then
  class="warning"
fi

text="󰡨 $peer_count"
tooltip=$(printf 'IPFS (Kubo)\n\nPeer: %s\nAgent: %s\nSwarm peers: %s\nRate: ↓%s ↑%s\nTotal: ↓%s ↑%s\n\nLeft: open WebUI · Right: restart service · Middle: refresh' \
  "$short_id" "${agent:-n/a}" "$peer_count" "$rate_in" "$rate_out" "$total_in" "$total_out")

finish_refresh "$(emit_waybar_json "$text" "$tooltip" "$class")"
