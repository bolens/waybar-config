#!/usr/bin/env sh
set -eu

cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/waybar"
. "$HOME/.config/waybar/scripts/waybar-cache-helpers.sh"
cache_file="$cache_dir/tailscale-status.json"
lock_dir="$cache_dir/tailscale-status.lock.d"
ttl=15
stale_lock_ttl=25

mkdir -p "$cache_dir"


if [ "${1:-}" != "--refresh" ]; then
  age=$(cache_file_age "$cache_file")
  if [ "$age" -le "$ttl" ] 2>/dev/null; then
    cat "$cache_file"
    exit 0
  fi

  cleanup_stale_lock_dir "$lock_dir" "$stale_lock_ttl"

  if [ -f "$cache_file" ]; then
    [ -d "$lock_dir" ] || refresh_in_background
    cat "$cache_file"
    exit 0
  fi

  [ -d "$lock_dir" ] || refresh_in_background
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

ts_fields=$(printf '%s' "$status_json" | jq -r '[
  (.BackendState // "Unknown"),
  (.Self.HostName // "unknown"),
  (([.TailscaleIPs[]? | select(test("^[0-9.]+$"))][0]) // ""),
  ([.Peer[]? | select(.Online == true)] | length | tostring),
  (.ExitNodeStatus.Tailnet.Target // ""),
  (([.Health[]?][0:5] | join("\n")) // "")
] | @tsv')
tab=$(printf '\t')
old_ifs=$IFS
IFS=$tab
set -- $ts_fields
IFS=$old_ifs
backend="${1:-Unknown}"
hostname="${2:-unknown}"
ipv4="${3:-}"
online_peers="${4:-0}"
exit_node="${5:-}"
health="${6:-}"

class="normal"
icon="󰛳"
label=""

case "$backend" in
  Running)
    ;;
  NeedsLogin|NeedsMachineAuth|Stopped)
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
printf '%s\n' "$json" > "$tmp_cache"
mv -f "$tmp_cache" "$cache_file"