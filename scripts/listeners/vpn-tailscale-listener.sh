#!/usr/bin/env bash
# Refresh VPN + Tailscale Waybar modules when tunnels change.
#
# Lifecycle: started by waybar-launch.sh / healed by waybar-healthcheck.sh via
# listener-ctl.sh (lock name: vpn-tailscale). Pattern matches privacy-listener:
# event FIFO + periodic tick, then status --refresh + waybar-signal.sh <key>.
set -euo pipefail
: "${WAYBAR_HOME:=${XDG_CONFIG_HOME:-$HOME/.config}/waybar}"
: "${WAYBAR_SCRIPTS:=$WAYBAR_HOME/scripts}"

script_dir="$(CDPATH='' cd -- "$(dirname "$0")" && pwd)"
cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/waybar"
vpn_cache="$cache_dir/vpn-status.json"
ts_cache="$cache_dir/tailscale-status.json"
poll_seconds=20

# shellcheck source=dock-windows-listener-lock.sh
WAYBAR_LISTENER_LOCK_NAME=vpn-tailscale
. "$script_dir/dock-windows-listener-lock.sh"

mkdir -p "$cache_dir"

prev_vpn=""
prev_ts=""

refresh_modules() {
  local vpn_json ts_json
  vpn_json="$("$WAYBAR_SCRIPTS/network/vpn-status.sh" --refresh 2>/dev/null || true)"
  ts_json="$("$WAYBAR_SCRIPTS/network/tailscale-status.sh" --refresh 2>/dev/null || true)"

  if [ -n "$vpn_json" ] && [ "$vpn_json" != "$prev_vpn" ]; then
    "$WAYBAR_SCRIPTS/lib/waybar-signal.sh" vpn "$vpn_cache" 2>/dev/null || true
    prev_vpn="$vpn_json"
  fi
  if [ -n "$ts_json" ] && [ "$ts_json" != "$prev_ts" ]; then
    "$WAYBAR_SCRIPTS/lib/waybar-signal.sh" tailscale "$ts_cache" 2>/dev/null || true
    prev_ts="$ts_json"
  fi
}

refresh_modules

fifo="${cache_dir}/vpn-tailscale-trigger.$$.fifo"
rm -f "$fifo"
mkfifo "$fifo"

cleanup() {
  rm -f "$fifo" 2>/dev/null || true
  pkill -P "$$" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

# NetworkManager events (VPN up/down, device state).
if command -v nmcli >/dev/null 2>&1; then
  (nmcli monitor 2>/dev/null | while read -r _; do
    echo "nm" >"$fifo" 2>/dev/null || true
  done) &
fi

# Periodic fallback (covers Tailscale / Mullvad / Netbird / ZeroTier).
(
  while true; do
    sleep "$poll_seconds"
    echo "tick" >"$fifo" 2>/dev/null || true
  done
) &

exec 3<"$fifo"
while read -r _line <&3; do
  refresh_modules
done
