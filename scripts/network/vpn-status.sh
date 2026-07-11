#!/usr/bin/env sh
set -eu
: "${WAYBAR_HOME:=${XDG_CONFIG_HOME:-$HOME/.config}/waybar}"
: "${WAYBAR_SCRIPTS:=$WAYBAR_HOME/scripts}"

cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/waybar"
. "$WAYBAR_SCRIPTS/lib/waybar-cache-helpers.sh"
cache_file="$cache_dir/vpn-status.json"
lock_dir="$cache_dir/vpn-status.lock.d"
ttl="$(waybar_module_interval vpn 15)"
stale_lock_ttl=20

mkdir -p "$cache_dir"


if [ "${1:-}" != "--refresh" ]; then
  if serve_cache_or_refresh "$cache_file" "$ttl" "$lock_dir" "$stale_lock_ttl"; then
    exit 0
  fi
  emit_waybar_json "󰦝" "Refreshing VPN status in background" "disabled"
  exit 0
fi

icon="󰦝"
class="normal"

# NetworkManager VPN connection check:
# We query active connections and search for active connections of type 'vpn' with state 'activated'.
# Timeout command limits execution time to 2 seconds to avoid blocking when NetworkManager is unresponsive.
nm_state="inactive"
nm_name="none"
if command -v nmcli >/dev/null 2>&1; then
  nm_line=$(timeout 2 nmcli -t -f NAME,TYPE,STATE connection show --active 2>/dev/null \
    | awk -F: '$2=="vpn" && $3=="activated" {print $1; exit}' || true)
  if [ -n "$nm_line" ]; then
    nm_state="active"
    nm_name="$nm_line"
  fi
fi

# Tailscale connection check:
# To prevent slow background execution, we first attempt to read from the cached tailscale status JSON file.
# If the cache is stale or missing, we fall back to running the tailscale status tool directly.
ts_state="unavailable"
ts_host="n/a"
ts_ip="n/a"
if command -v tailscale >/dev/null 2>&1; then
  ts_cache="$cache_dir/tailscale-status.json"
  ts_cached="$(read_fresh_cache_file "$ts_cache" 15 2>/dev/null || true)"
  if [ -n "$ts_cached" ]; then
    ts_state=$(printf '%s' "$ts_cached" | jq -r '.backend // "unknown"')
    ts_host=$(printf '%s' "$ts_cached" | jq -r '.hostname // "n/a"')
    ts_ip=$(printf '%s' "$ts_cached" | jq -r '.ipv4 // "n/a"')
    [ -n "$ts_ip" ] || ts_ip="n/a"
  else
    ts_json=$(timeout 2 tailscale status --json 2>/dev/null || true)
    if [ -n "$ts_json" ]; then
      ts_state=$(printf '%s' "$ts_json" | jq -r '.BackendState // "unknown"')
      ts_host=$(printf '%s' "$ts_json" | jq -r '.Self.HostName // "n/a"')
      ts_ip=$(printf '%s' "$ts_json" | jq -r '([.Self.TailscaleIPs[]? | select(test("^[0-9.]+$"))][0]) // "n/a"')
    fi
  fi
fi

# Netbird connection check:
# Runs netbird status and parses stdout for active online state indicators.
nb_state="unavailable"
if command -v netbird >/dev/null 2>&1; then
  if timeout 2 netbird status 2>/dev/null | rg -qi "connected|online"; then
    nb_state="active"
  else
    nb_state="inactive"
  fi
fi

# ZeroTier connection check:
# Queries zerotier-cli info to check if the daemon is online and connected.
zt_state="unavailable"
if command -v zerotier-cli >/dev/null 2>&1; then
  if timeout 2 zerotier-cli info 2>/dev/null | rg -qi "online"; then
    zt_state="active"
  else
    zt_state="inactive"
  fi
fi

# Mullvad connection check:
mv_state="unavailable"
if command -v mullvad >/dev/null 2>&1; then
  mv_out=$(timeout 2 mullvad status 2>/dev/null || true)
  if printf '%s\n' "$mv_out" | grep -qi "connected"; then
    mv_state="active"
  else
    mv_state="inactive"
  fi
fi

active_count=0
[ "$nm_state" = "active" ] && active_count=$((active_count + 1))
[ "$ts_state" = "Running" ] && active_count=$((active_count + 1))
[ "$nb_state" = "active" ] && active_count=$((active_count + 1))
[ "$zt_state" = "active" ] && active_count=$((active_count + 1))
[ "$mv_state" = "active" ] && active_count=$((active_count + 1))

if [ "$active_count" -eq 0 ]; then
  class="offline"
fi

text="$icon"

tooltip=$(printf 'VPN Summary\n\nNetworkManager VPN: %s (%s)\nTailscale: %s\nTailscale host: %s\nTailscale IPv4: %s\nMullvad: %s\nNetbird: %s\nZeroTier: %s\n\nActive tunnels: %s\n\nLeft: open VPN status popup · Right: settings · Middle: refresh' \
  "$nm_state" "$nm_name" "$ts_state" "$ts_host" "$ts_ip" "$mv_state" "$nb_state" "$zt_state" "$active_count")

json=$(emit_waybar_json "$text" "$tooltip" "$class")

printf '%s\n' "$json"

tmp_cache="$cache_file.tmp.$$"
printf '%s\n' "$json" > "$tmp_cache"
mv -f "$tmp_cache" "$cache_file"

