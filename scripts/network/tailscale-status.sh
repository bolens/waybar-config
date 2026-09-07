#!/usr/bin/env sh
# Tailscale status for Waybar (hides when tailscaled / tailscale CLI absent).
set -eu
: "${WAYBAR_HOME:=${XDG_CONFIG_HOME:-$HOME/.config}/waybar}"
: "${WAYBAR_SCRIPTS:=$WAYBAR_HOME/scripts}"

cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/waybar"
# shellcheck source=../lib/waybar-cache-helpers.sh
. "$WAYBAR_SCRIPTS/lib/waybar-cache-helpers.sh"
cache_file="$cache_dir/tailscale-status.json"
lock_dir="$cache_dir/tailscale-status.lock.d"
ttl="$(waybar_module_interval tailscale 15)"
stale_lock_ttl=25

mkdir -p "$cache_dir"

if [ "${1:-}" != "--refresh" ]; then
  if serve_cache_or_refresh "$cache_file" "$ttl" "$lock_dir" "$stale_lock_ttl"; then
    exit 0
  fi
  jq -cn \
    --arg text "󰛳" \
    --arg tooltip "Refreshing Tailscale status in background" \
    --arg class "disabled" \
    '{text:$text, tooltip:$tooltip, class:$class}'
  exit 0
fi

if ! command -v tailscale >/dev/null 2>&1; then
  jq -cn \
    --arg text "󰛳 --" \
    --arg tooltip "Tailscale not installed" \
    --arg class "disabled" \
    '{text:$text, tooltip:$tooltip, class:$class}'
  exit 0
fi

status_json=$(timeout 2 tailscale status --json 2>/dev/null || true)
if [ -z "$status_json" ]; then
  jq -cn \
    --arg text "󰛴 OFF" \
    --arg tooltip "Tailscale daemon unavailable" \
    --arg class "offline" \
    '{text:$text, tooltip:$tooltip, class:$class}'
  exit 0
fi

ts_fields=$(printf '%s' "$status_json" | jq -c '[
  (.BackendState // "Unknown"),
  (.Self.HostName // "unknown"),
  (([.TailscaleIPs[]? | select(test("^[0-9.]+$"))][0]) // ""),
  ([.Peer[]? | select(.Online == true)] | length | tostring),
  (.ExitNodeStatus.Tailnet.Target // ""),
  (([.Health[]?][0:5] | join("\n")) // "")
]')
# JSON indexing preserves empty strings and embedded tabs/newlines.
backend=$(printf '%s' "$ts_fields" | jq -r '.[0]')
hostname=$(printf '%s' "$ts_fields" | jq -r '.[1]')
ipv4=$(printf '%s' "$ts_fields" | jq -r '.[2]')
online_peers=$(printf '%s' "$ts_fields" | jq -r '.[3]')
exit_node=$(printf '%s' "$ts_fields" | jq -r '.[4]')
health=$(printf '%s' "$ts_fields" | jq -r '.[5]')

class="normal"
icon="󰛳"
label=""

case "$backend" in
  Running)
    ;;
  NeedsLogin | NeedsMachineAuth | Stopped)
    class="offline"
    label="OFF"
    ;;
  *)
    class="warning"
    label="$backend"
    ;;
esac

if [ "$backend" = "Running" ] && [ -n "$health" ]; then
  class="warning"
fi

if [ "$backend" != "Running" ]; then
  icon="󰛴"
fi

text="$icon"
[ -n "$label" ] && text="$icon $label"

tooltip=$(printf 'Backend: %s\nHost: %s\nIPv4: %s\nOnline peers: %s' "$backend" "$hostname" "${ipv4:-n/a}" "$online_peers")
if [ -n "$exit_node" ]; then
  tooltip=$(printf '%s\nExit node: %s' "$tooltip" "$exit_node")
fi
if [ -n "$health" ]; then
  tooltip=$(printf '%s\n\nHealth:\n%s' "$tooltip" "$health")
fi

tooltip=$(printf '%s\n\nLeft: tailscale status · Right: admin panel · Middle: refresh' "$tooltip")

json=$(jq -cn \
  --arg text "$text" \
  --arg tooltip "$tooltip" \
  --arg class "$class" \
  --arg backend "$backend" \
  --arg hostname "$hostname" \
  --arg ipv4 "${ipv4:-}" \
  --arg online_peers "$online_peers" \
  --arg exit_node "$exit_node" \
  --arg health "$health" \
  '{text:$text, tooltip:$tooltip, class:$class, backend:$backend, hostname:$hostname, ipv4:$ipv4, online_peers:$online_peers, exit_node:$exit_node, health:$health}')

printf '%s\n' "$json"

tmp_cache="$cache_file.tmp.$$"
printf '%s\n' "$json" >"$tmp_cache"
mv -f "$tmp_cache" "$cache_file"
