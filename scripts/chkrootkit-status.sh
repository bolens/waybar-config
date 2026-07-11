#!/usr/bin/env sh
set -eu
script_dir="${0%/*}"
. "$script_dir/waybar-cache-helpers.sh"

cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/waybar"
cache_file="$cache_dir/chkrootkit-status.json"
lock_dir="$cache_dir/chkrootkit-status.lock.d"
ttl="$(waybar_module_interval chkrootkit 15)"
stale_lock_ttl=20

mkdir -p "$cache_dir"

script_dir="${0%/*}"
# Handle sourcing when run directly or by Waybar
if [ -f "$script_dir/waybar-cache-helpers.sh" ]; then
  . "$script_dir/waybar-cache-helpers.sh"
else
  . "${WAYBAR_HOME:-${XDG_CONFIG_HOME:-$HOME/.config}/waybar}/scripts/waybar-cache-helpers.sh"
fi
. "${WAYBAR_HOME:-${XDG_CONFIG_HOME:-$HOME/.config}/waybar}/scripts/waybar-settings.sh"
service_name=$(waybar_settings_get '.services.chkrootkit.service_name' 'chkrootkit-scan.service')

check_systemd_scan_service \
  "$service_name" \
  "chkrootkit-scan" \
  "chkrootkit Rootkit Scanner" \
  "Chkroot" \
  "󰖳" \
  "$cache_file" \
  "$lock_dir" \
  "$ttl" \
  "$stale_lock_ttl" \
  "86400" \
  "Scan Stale (> 24 hours)" \
  "Left: start daily scan · Right: view service logs · Middle: refresh" \
  "$0" \
  "${1:-}"
